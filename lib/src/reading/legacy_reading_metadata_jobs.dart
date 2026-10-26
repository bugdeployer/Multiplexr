import '../core/application/maintenance.dart';
import '../features/metadata/application/reading_metadata_job_port.dart';
import '../features/metadata/application/metadata_batch_journal.dart';
import 'domain/reading_catalog.dart';
import 'reading_metadata_host.dart';

class LegacyReadingMetadataJobs implements ReadingMetadataJobPort {
  const LegacyReadingMetadataJobs(this.library);
  final ReadingMetadataHost library;
  @override
  Object get owner => library.owner;
  @override
  Maintenance get maintenance => library.maintenance;
  @override
  void access(String collectionId) => library.commands.access(collectionId);
  @override
  Future<List<ReadingTitle>> titles(String collectionId) async =>
      (await library.commands.readCollection(collectionId)).catalog.titles
          .where((title) => title.catalog.id.collectionId == collectionId)
          .toList();
  @override
  Future<MetadataBatchJournal?> readJournal(
    String collectionId,
    String provider,
  ) async {
    final bundle = await library.commands.readCollection(collectionId);
    return bundle.management.jobs
        .where((j) => j.collectionId == collectionId && j.provider == provider)
        .firstOrNull
        ?.journal;
  }

  @override
  Future<void> updateJournal(
    String collectionId,
    String provider,
    MetadataBatchJournal Function(MetadataBatchJournal?) change,
  ) => library.commands.update(
    collectionId,
    (transaction) => transaction.journal(collectionId, provider, change),
  );
}
