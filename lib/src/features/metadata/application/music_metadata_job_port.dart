import '../../../core/application/maintenance.dart';

abstract interface class MusicMetadataJobPort {
  Object get owner;
  Maintenance get maintenance;
  bool access(String collectionId);
  Future<Map<String, dynamic>?> readJournal(String collectionId);
  Future<void> updateJournal(
    String collectionId,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>?) change,
  );
}
