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
    MetadataEntityType.values.where(
      (v) =>
          v != MetadataEntityType.image &&
          ((contribution.definition['kinds'] as List?)?.contains(v.name) ??
              true),
    ),
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
    late final Map<String, dynamic> page;
    try {
      page = Map<String, dynamic>.from(
        await invoke(id, {
          'query': request.title,
          'kind': request.entity.name,
          if (request.creator.isNotEmpty) 'creator': request.creator,
          if (request.locale.isNotEmpty) 'language': request.locale,
          if (request.cursor != null) 'cursor': request.cursor,
        }, selectedScopes) as Map,
      );
    } on PluginDenied catch (error) {
      throw switch (error.code) {
        'permission_denied' => const MetadataFailure(
          MetadataFailureKind.authentication,
          'Check the provider credential and collection access in Plugins & themes.',
        ),
        'resource_limit' => const MetadataFailure(
          MetadataFailureKind.rateLimit,
          'The provider is rate limiting requests. Try again later.',
        ),
        'deadline_exceeded' => const MetadataFailure(
          MetadataFailureKind.network,
          'The provider took too long. Try again.',
        ),
        'invalid_response' => const MetadataFailure(
          MetadataFailureKind.invalidResponse,
          'The provider returned an invalid response. Check for a plugin update.',
        ),
        'unsupported_capability' => const MetadataFailure(
          MetadataFailureKind.unavailable,
          'This provider does not support the requested media type.',
        ),
        _ => const MetadataFailure(
          MetadataFailureKind.network,
          'The provider could not complete the search. Check your connection and plugin setup.',
        ),
      };
    }
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
