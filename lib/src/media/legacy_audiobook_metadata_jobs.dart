import '../core/application/maintenance.dart';
import '../core/persistence/state_repository.dart';
import '../features/metadata/application/audiobook_metadata_job_port.dart';
import 'audio_library.dart';
import 'audio_models.dart';

class LegacyAudiobookMetadataJobs implements AudiobookMetadataJobPort {
  const LegacyAudiobookMetadataJobs(this.library);
  final AudioLibrary library;
  @override
  Object get owner => library.service.persistenceOwner;
  @override
  Maintenance get maintenance => library.service.maintenance;
  @override
  bool canAccess(String id) => library.canAccess(id);
  @override
  Future<List<Audiobook>> books() => library.books();
  @override
  Future<Map<String, dynamic>?> readJournal(String? collectionId) =>
      library.service.readState('metadata:audiobooks:$collectionId');
  @override
  Future<void> updateJournal(
    String? collectionId,
    Map<String, dynamic> Function(Map<String, dynamic>?) change,
  ) => JsonStateRepository(library.service).update(
    'metadata:audiobooks:$collectionId',
    (previous) async => change(previous),
  );
}
