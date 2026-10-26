import 'dart:convert';

import '../../metadata/application/metadata_contracts.dart';
import '../../catalog/application/extension_catalog.dart';
import 'contribution_registry.dart';
import 'plugin_platform.dart';

typedef InvokeContribution = Future<Object?> Function(
  String id,
  Map<String, Object?> params,
  List<PluginScope> scopes, {
  List<ExtensionTitle> selection,
});

/// Provider identity includes contribution ID, installed publisher and version.
class InstalledMetadataProvider
    implements MetadataProvider, VersionedMetadataProvider {
  InstalledMetadataProvider(this.contribution, this.invoke, this.scopes);
  final PluginContribution contribution;
  final InvokeContribution invoke;
  final List<PluginScope> scopes;
  @override
  String get id => contribution.id;
  @override
  String get checkpointIdentity => jsonEncode([
    id,
    contribution.plugin.publisher,
    contribution.plugin.version,
    contribution.plugin.instance,
    contribution.plugin.revision,
  ]);
  String get publisher => contribution.plugin.publisher;
  String get version => contribution.plugin.version;
  @override
  Set<MetadataEntityType> get entities => Set.unmodifiable(
    MetadataEntityType.values.where((v) => v != MetadataEntityType.image),
  );
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async {
    request.validate();
    if (request.provider != id ||
        !entities.contains(request.entity) ||
        request.page > 1 && request.cursor == null) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Provider or cursor is unavailable. Restart this search.',
      );
    }
    final selectedScopes = scopes.isNotEmpty
        ? scopes
        : [
            PluginScope(request.collectionId, switch (request.entity) {
              MetadataEntityType.movie => ExtensionMedia.movie,
              MetadataEntityType.television => ExtensionMedia.television,
              MetadataEntityType.musicTrack ||
              MetadataEntityType.musicAlbum => ExtensionMedia.music,
              MetadataEntityType.audiobook => ExtensionMedia.audiobook,
              MetadataEntityType.ebook => ExtensionMedia.ebook,
              _ => ExtensionMedia.comic,
            }, 'Selected collection'),
          ];
    if (selectedScopes.single.collection.isEmpty) {
      throw const PluginDenied();
    }
    final page = Map<String, dynamic>.from(
      await invoke(id, {
        'query': request.title,
        'kind': request.entity.name,
        if (request.creator.isNotEmpty) 'creator': request.creator,
        if (request.locale.isNotEmpty) 'language': request.locale,
        if (request.cursor != null) 'cursor': request.cursor,
      }, selectedScopes) as Map,
    );
    final next = page['nextCursor'] as String?;
    return MetadataSearchPage(
      request: request,
      attribution: contribution.plugin.name,
      nextPage: next == null ? null : request.page + 1,
      nextCursor: next,
      candidates: [
        for (final raw in page['items'] as List)
          MetadataCandidate(
            provider: id,
            id: (raw as Map)['id'] as String,
            entity: request.entity,
            attribution: contribution.plugin.name,
            implementation: MetadataImplementation(
              plugin: contribution.plugin.id,
              publisher: publisher,
              version: version,
              contribution: id,
              instance: contribution.plugin.instance,
              permissionRevision: contribution.plugin.revision,
              collection: selectedScopes.single.collection,
            ),
            values: {
              if (raw['fields'] is Map)
                ...Map<String, dynamic>.from(raw['fields'] as Map),
              if ((raw['fields'] as Map?)?['genres'] is List)
                'genres': ((raw['fields'] as Map)['genres'] as List).join(', '),
              'id': raw['id'],
              'metadataSource': id,
              'title': raw['title'],
              if (raw['authors'] != null) 'authors': raw['authors'],
              if (raw['authors'] != null)
                'author': (raw['authors'] as List).join(', '),
              if (raw['authors'] != null)
                'artist': (raw['authors'] as List).join(', '),
            },
          ),
      ],
    );
  }
}
