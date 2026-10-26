import 'dart:convert';

import '../features/plugins/application/plugin_platform.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../core/persistence/state_repository.dart';
import 'library_service.dart';

class LegacyPluginMutations implements PluginMutations, PluginFieldMutations {
  const LegacyPluginMutations(this.service, this.catalog, this.backend);
  final LibraryService service;
  final PluginBackend backend;
  final ExtensionCatalogQueries catalog;
  String fieldKey(ExtensionTitle title) =>
      'plugins:fields:${jsonEncode([title.collection, title.kind.name, title.id])}';
  @override
  Future<Map<String, dynamic>> readFields(ExtensionTitle title) async =>
      Map<String, dynamic>.from(
        (await service.readState(fieldKey(title)))?['fields'] as Map? ?? {},
      );
  @override
  Future<void> mergeFields(
    PluginRecord plugin,
    ExtensionTitle expected,
    Map<String, dynamic> fields,
    String key,
    void Function() checkAccess,
  ) => service.maintenance.activity(
    () => MutationCoordinator.forOwner(service.persistenceOwner)
        .run('catalog:commands', () async {
          checkAccess();
          final latest = await catalog.source.titles(
            expected.collection,
            expected.kind,
          );
          if (!latest.any(
            (t) => t.id == expected.id && t.revision == expected.revision,
          )) {
            throw const PluginDenied('conflict');
          }
          final stateKey = fieldKey(expected);
          final before = await service.readState(stateKey);
          checkAccess();
          final approval = await backend.command('approve', {
            'id': plugin.id,
            'revision': plugin.revision,
            'collection': expected.collection,
          });
          checkAccess();
          await service.transport.invokeMethod<void>('pluginFields', {
            'approval': approval,
            'collection': expected.collection,
            'key': stateKey,
            'publisher': plugin.publisher,
            'plugin': plugin.id,
            'expected': before == null ? null : jsonEncode(before),
            'fields': fields,
            'operation': key,
          });
          checkAccess();
        }),
  );
  @override
  Future<void> replaceTags(
    PluginRecord plugin,
    ExtensionTitle expected,
    List<String> tags,
    String idempotencyKey,
    void Function() checkAccess,
  ) => service.maintenance.activity(
    () => MutationCoordinator.forOwner(service.persistenceOwner)
        .run('catalog:commands', () async {
          if (!{
            ExtensionMedia.movie,
            ExtensionMedia.television,
            ExtensionMedia.video,
          }.contains(expected.kind)) {
            throw const PluginDenied('unsupported_capability');
          }
          checkAccess();
          final raw = await service.load();
          final rows = (raw['assets'] as List).cast<Map>();
          final current = rows
              .where(
                (row) =>
                    row['collectionId'] == expected.collection &&
                    row['id'] == expected.id,
              )
              .single;
          final latest = await catalog.source.titles(
            expected.collection,
            expected.kind,
          );
          checkAccess();
          if (latest
              .where(
                (t) => t.id == expected.id && t.revision == expected.revision,
              )
              .isEmpty) {
            throw const PluginDenied('conflict');
          }
          final approval = await backend.command('approve', {
            'id': plugin.id,
            'revision': plugin.revision,
            'collection': expected.collection,
          });
          checkAccess();
          await service.transport.invokeMethod<void>('pluginTags', {
            'approval': approval,
            'expected': jsonEncode(current),
            'collection': expected.collection,
            'id': expected.id,
            'tags': tags,
            'idempotencyKey': idempotencyKey,
          });
          checkAccess();
        }),
  );
}
