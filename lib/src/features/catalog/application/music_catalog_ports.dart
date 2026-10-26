import '../../../media/music_catalog_models.dart';
import '../../../media/contracts.dart';

abstract interface class MusicCatalogStore {
  Future<MusicCatalog> readCatalog();
  Future<void> updateCatalog({
    required String collectionId,
    required bool Function(String) authorized,
    required MusicCatalog Function(MusicCatalog) change,
  });
  Future<Map<String, dynamic>?> readExtras();
  Future<void> updateExtras(
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>?) change,
  );
  Future<Map<MediaId, int>> history(List<MediaId> ids);
  Future<void> reconnect(
    MusicTrack missing,
    MusicTrack replacement, {
    required void Function() checkAccess,
  });
}
