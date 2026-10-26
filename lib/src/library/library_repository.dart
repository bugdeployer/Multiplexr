import '../settings/domain/collection_settings_schema.dart';
import '../core/persistence/state_repository.dart';
import 'library_service.dart';
import 'library_models.dart';

import '../features/catalog/application/library_ports.dart';
import '../core/platform/application_failure_adapter.dart';
export '../features/catalog/application/library_ports.dart';

class LegacyLibraryRepository implements LibraryRepository {
  const LegacyLibraryRepository(this.service, {this.authorized});
  final bool Function(String)? authorized;
  Future<void> _write(Iterable<String> ids, Future<void> Function() write) =>
      MutationCoordinator.forOwner(service.persistenceOwner)
          .run('catalog:commands', () async {
            if (ids.any((id) => authorized?.call(id) == false)) {
              throw StateError('Collection access is required.');
            }
            await write();
          });
  final LibraryService service;
  @override
  Future<LibrarySnapshot> load() async {
    try {
      return await _load();
    } catch (error) {
      throw applicationFailure(error);
    }
  }

  Future<LibrarySnapshot> _load() async {
    final data = await service.load();
    final videoCollections = (data['collections'] as List? ?? [])
        .where(
          (c) =>
              c['type'] == null ||
              c['type'] == 'video' ||
              c['type'] == 'audiobook' ||
              c['type'] == 'audio',
        )
        .toList();
    final originalSubtypes = {
      for (final c in videoCollections.where(
        (c) => c['type'] == null || c['type'] == 'video',
      ))
        c['id']: VideoSubtype.values.byName(c['subtype']),
    };
    final nextCollections = videoCollections
        .map((c) => VideoCollection.fromJson(Map<String, dynamic>.from(c)))
        .toList();
    final nextAssets = (data['assets'] as List? ?? [])
        .where((a) => originalSubtypes.containsKey(a['collectionId']))
        .map(
          (a) => VideoAsset.fromJson(
            Map<String, dynamic>.from(a),
            originalSubtypes[a['collectionId']]!,
          ),
        )
        .toList();

    return LibrarySnapshot(
      collections: nextCollections,
      assets: nextAssets,
      audioCounts: Map<String, int>.from(data['audioCounts'] ?? {}),
      queue: data.containsKey('queue')
          ? List<String>.unmodifiable(data['queue'])
          : null,
      seriesIndexSupported: data['seriesIndexSupported'] == true,
    );
  }

  @override
  Future<void> saveCollection(VideoCollection collection) {
    CollectionSettingsSchema.validate(collection.toJson());
    return _write([collection.id], () => service.saveCollection(collection));
  }

  @override
  Future<void> saveBrowsing(String id, Map<String, dynamic> values) =>
      _write([id], () => service.saveBrowsing(id, values));
  @override
  Future<void> editTags(
    List<VideoAsset> assets, {
    required String operation,
    required List<String> tags,
    String? target,
    String? collectionId,
  }) => _write(
    [...assets.map((a) => a.collectionId), ?collectionId],
    () => service.editTags(
      assets,
      operation: operation,
      tags: tags,
      target: target,
      collectionId: collectionId,
    ),
  );
  @override
  Future<void> removeCollection(String id) =>
      _write([id], () => service.removeCollection(id));
  @override
  Future<void> saveAsset(VideoAsset asset) =>
      _write([asset.collectionId], () => service.saveAsset(asset));
  @override
  Future<void> saveGrouping(List<VideoAsset> assets) => _write(
    assets.map((a) => a.collectionId),
    () => service.saveGrouping(assets),
  );
  @override
  Future<void> updateFlags(
    List<VideoAsset> assets,
    String action,
    bool value,
  ) => _write(
    assets.map((a) => a.collectionId),
    () => service.updateFlags(assets, action, value),
  );
  @override
  Future<void> watchState(VideoAsset asset, String action) =>
      _write([asset.collectionId], () => service.watchState(asset, action));
  @override
  Future<void> saveQueue(List<String> queue) => service.saveQueue(queue);
  @override
  Future<List<String>> editQueue(
    void Function(List<String>) edit, {
    List<String> fallback = const [],
  }) => MutationCoordinator.forOwner(service.persistenceOwner)
      .run('video:queue', () async {
        final state = await service.load();
        final next = state.containsKey('queue')
            ? List<String>.from(state['queue'])
            : List<String>.of(fallback);
        edit(next);
        await service.saveQueue(next);
        return next;
      });
  @override
  Future<void> saveSeriesIndex(Map<String, dynamic> index) =>
      service.saveSeriesIndex(index);
  @override
  Future<List<String>> scan(String id, {String? requestId}) =>
      service.scan(id, requestId: requestId);
}
