import '../features/catalog/application/music_catalog_ports.dart';
import '../core/persistence/state_repository.dart';
import '../library/library_service.dart';
import 'contracts.dart';
import 'music_catalog.dart';

class LegacyMusicCatalogStore implements MusicCatalogStore {
  LegacyMusicCatalogStore(this.service)
    : catalog = MusicCatalogRepository(service),
      state = JsonStateRepository(service);
  final LibraryService service;
  final MusicCatalogRepository catalog;
  final JsonStateRepository state;
  static const extrasKey = 'music:extras';
  @override
  Future<MusicCatalog> readCatalog() => catalog.read();
  @override
  Future<void> updateCatalog({
    required String collectionId,
    required bool Function(String) authorized,
    required MusicCatalog Function(MusicCatalog) change,
  }) => catalog.update(
    collectionId: collectionId,
    authorized: authorized,
    change: change,
  );
  @override
  Future<Map<String, dynamic>?> readExtras() => state.read(extrasKey);
  @override
  Future<void> updateExtras(
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>?) change,
  ) => state.update(extrasKey, change);
  @override
  Future<Map<MediaId, int>> history(List<MediaId> ids) async {
    final values = await service.readStates([
      for (final id in ids) 'progress:${id.key}',
    ]);
    return {
      for (final id in ids)
        id:
            (values['progress:${id.key}']?['lastPlayedAt'] as num?)?.toInt() ??
            0,
    };
  }

  @override
  Future<void> reconnect(
    MusicTrack missing,
    MusicTrack replacement, {
    required void Function() checkAccess,
  }) => MutationCoordinator.forOwner(service.persistenceOwner)
      .run('music:library', () async {
        checkAccess();
        await service.transport.invokeMethod('relinkMusic', {
          'collectionId': missing.id.collectionId,
          'missingId': missing.id.itemId,
          'replacementId': replacement.id.itemId,
        });
      });
}
