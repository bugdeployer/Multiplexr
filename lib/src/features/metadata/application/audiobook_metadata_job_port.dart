import '../../../core/application/maintenance.dart';
import '../../../media/audio_models.dart';

abstract interface class AudiobookMetadataJobPort {
  Object get owner;
  Maintenance get maintenance;
  bool canAccess(String collectionId);
  Future<List<Audiobook>> books();
  Future<Map<String, dynamic>?> readJournal(String? collectionId);
  Future<void> updateJournal(
    String? collectionId,
    Map<String, dynamic> Function(Map<String, dynamic>?) change,
  );
}
