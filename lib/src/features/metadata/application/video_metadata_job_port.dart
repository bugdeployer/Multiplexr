import '../../../core/application/maintenance.dart';
import '../../../library/library_models.dart';
import 'metadata_contracts.dart';

abstract interface class VideoMetadataJobPort {
  Object get owner;
  Maintenance get maintenance;
  bool get checkpointSupported;
  bool canAccessCollection(String collectionId);
  List<VideoAsset> items(String collectionId);
  List<VideoAsset> indexedItems(String collectionId);
  Future<void> load();
  Future<Map<String, dynamic>?> readJournal(String collectionId);
  Future<bool> writeJournal(String collectionId, Map<String, dynamic> value);
  MetadataTarget target(
    VideoAsset lookup,
    VideoAsset original,
    String collectionId,
  );
  Future<void> applyStatus(VideoAsset before, VideoAsset after);
}
