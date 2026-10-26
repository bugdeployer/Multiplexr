import '../core/platform/platform_transport.dart';
import '../features/metadata/application/metadata_workflow.dart';
import '../metadata/metadata_targets.dart';
import '../features/metadata/application/music_metadata_target.dart';
import '../features/metadata/application/reading_metadata_target.dart';
import '../media/music_repository.dart';
import '../catalog/domain/catalog_models.dart';
import '../media/contracts.dart';

import 'dart:convert';

import '../core/platform/native_plugin_backend.dart';
import '../experience/plugins/plugin_manager.dart';
import '../library/legacy_plugin_mutations.dart';
import '../library/library_controller.dart';
import '../library/library_models.dart';
import '../reading/reading_app_controller.dart';
import '../settings.dart';
import '../features/catalog/application/extension_catalog.dart';

PluginManager createPluginManager({
  required LibraryController library,
  required ReadingAppController reading,
  required SettingsController settings,
  required ExtensionCatalogQueries catalog,
  required MetadataWorkflow Function() metadataWorkflow,
}) {
  final backend = NativePluginBackend();
  final gateway = PluginGateway(
    backend: backend,
    catalog: catalog,
    mutations: LegacyPluginMutations(library.service, catalog, backend),
    authorized: catalog.source.authorized,
    blocked: () =>
        settings.locked ||
        settings.covered ||
        library.service.maintenance.exclusive,
    generation: () => library.service.maintenance.generation,
    now: DateTime.now,
  );
  final manager = PluginManager(
    reviewWorkflow: metadataWorkflow,
    backend: backend,
    gateway: gateway,
    commitAuthority: (candidate, operation) =>
        NativeCatalogCommit.run(() async {
          if (gateway.blocked()) throw const PluginDenied();
          final identity = candidate.implementation!.toJson();
          final approval = await backend.command('metadataPermit', identity);
          if (gateway.blocked()) throw const PluginDenied();
          return {...identity, 'approval': approval as String};
        }, operation),
    restoredInventory: () async {
      final value = await library.service.readState('plugins:portable');
      return [
        for (final row in value?['inventory'] as List? ?? [])
          Map<String, dynamic>.from(row as Map),
      ];
    },
    metadataTarget: (title) async {
      switch (title.kind) {
        case ExtensionMedia.movie:
        case ExtensionMedia.television:
        case ExtensionMedia.video:
          await library.load();
          return library.metadataJobs.target(
            library
                .items(title.collection)
                .singleWhere((a) => a.id == title.id),
          );
        case ExtensionMedia.music:
          return MusicMetadataTarget(
            MusicRepository(library),
            trackId: MediaId(MediaKind.music, title.collection, title.id),
          );
        case ExtensionMedia.audiobook:
          return AudiobookMetadataTarget(
            library.audiobookCatalog(collectionId: title.collection),
            MediaId(MediaKind.audiobook, title.collection, title.id),
          );
        case ExtensionMedia.ebook:
        case ExtensionMedia.comic:
          return ReadingMetadataTarget(
            reading.library,
            CatalogIdentity(
              title.collection,
              title.id,
              CatalogEntityKind.title,
            ),
            reading.library.metadataJobs.provider,
          ).initialize();
      }
    },
    scopes: () async {
      await library.load();
      await reading.load();
      return [
        for (final c in library.collections)
          if (library.canAccessCollection(c.id))
            for (final kind
                in (c.kind == MediaKind.music
                    ? [ExtensionMedia.music]
                    : c.kind == MediaKind.audiobook
                    ? [ExtensionMedia.audiobook]
                    : c.subtype == VideoSubtype.videos
                    ? [ExtensionMedia.video]
                    : c.subtype == VideoSubtype.movies
                    ? [ExtensionMedia.movie]
                    : c.subtype == VideoSubtype.tv
                    ? [ExtensionMedia.television]
                    : [ExtensionMedia.movie, ExtensionMedia.television]))
              PluginScope(c.id, kind, '${c.name} · ${kind.name}'),
        for (final c in reading.bundle?.catalog.collections ?? [])
          if (reading.canAccess(c.id))
            PluginScope(
              c.id,
              c.subtype.name == 'ebook'
                  ? ExtensionMedia.ebook
                  : ExtensionMedia.comic,
              c.name,
            ),
      ];
    },
  );
  String security() => jsonEncode([
    settings.locked,
    settings.covered,
    library.service.maintenance.generation,
    for (final c in library.collections)
      [c.id, library.canAccessCollection(c.id)],
    for (final c in reading.bundle?.catalog.collections ?? [])
      [c.id, reading.canAccess(c.id)],
  ]);
  Map<String, String> catalogState() => {
    for (final c in library.collections)
      if (library.canAccessCollection(c.id))
        c.id: jsonEncode([
          c.name,
          for (final item in library.indexedItems(c.id)) item.toJson(),
        ]),
    for (final c in reading.bundle?.catalog.collections ?? [])
      if (reading.canAccess(c.id))
        c.id: jsonEncode([
          c.name,
          for (final title in reading.bundle!.catalog.titles.where(
            (t) => t.catalog.id.collectionId == c.id,
          ))
            [
              title.catalog.id.entityId,
              title.catalog.metadata.title,
              title.catalog.metadata.authors,
              title.catalog.metadata.description,
              title.catalog.metadata.language,
              title.catalog.metadata.identifier,
            ],
        ]),
  };
  var previousCatalog = <String, String>{};
  var previous = security();
  var checkingCatalog = false, closed = false;
  Future<void> checkCatalog(String? origin) async {
    if (checkingCatalog || closed) return;
    checkingCatalog = true;
    try {
      final current = catalogState();
      for (final c in library.collections.where(
        (c) => c.kind == MediaKind.music || c.kind == MediaKind.audiobook,
      )) {
        if (!library.canAccessCollection(c.id)) continue;
        final titles = await catalog.source.titles(
          c.id,
          c.kind == MediaKind.music
              ? ExtensionMedia.music
              : ExtensionMedia.audiobook,
        );
        if (library.canAccessCollection(c.id)) {
          current[c.id] = jsonEncode([
            c.name,
            for (final t in titles) [t.id, t.revision],
          ]);
        }
      }
      if (closed || gateway.blocked()) return;
      final changes = {
        ...current.keys,
        ...previousCatalog.keys,
      }.where((id) => previousCatalog[id] != current[id]).toSet();
      previousCatalog = current;
      if (changes.isNotEmpty) {
        manager.signalCatalogChange(changes, origin: origin);
      }
    } catch (_) {
      /* Best-effort event delivery never blocks catalog operations. */
    } finally {
      checkingCatalog = false;
    }
  }

  void changed() {
    if (manager.registry.family('event.handler').isNotEmpty) {
      checkCatalog(manager.commandOrigin);
    }
    final next = security();
    if (next != previous) {
      previous = next;
      manager.revoke();
      if (!settings.locked && !settings.covered) {
        manager.refresh();
      }
    }
  }

  settings.addListener(changed);
  library.addListener(changed);
  reading.addListener(changed);
  final detachMaintenance = library.service.maintenance.register(
    invalidate: manager.revoke,
    drain: () async {
      await backend.command('disableAll');
    },
  );
  manager.onDispose = () {
    closed = true;
    detachMaintenance();
    settings.removeListener(changed);
    library.removeListener(changed);
    reading.removeListener(changed);
  };
  manager.refresh();
  return manager;
}
