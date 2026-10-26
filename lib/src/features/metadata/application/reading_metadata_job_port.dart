import '../../../core/application/maintenance.dart';
import '../../../reading/domain/reading_catalog.dart';
import 'metadata_batch_journal.dart';

abstract interface class ReadingMetadataJobPort {
  Object get owner;
  Maintenance get maintenance;
  void access(String collectionId);
  Future<List<ReadingTitle>> titles(String collectionId);
  Future<MetadataBatchJournal?> readJournal(
    String collectionId,
    String provider,
  );
  Future<void> updateJournal(
    String collectionId,
    String provider,
    MetadataBatchJournal Function(MetadataBatchJournal?) change,
  );
}
