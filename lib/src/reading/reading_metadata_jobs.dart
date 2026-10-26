import '../features/metadata/application/publication_provider.dart';
import '../features/jobs/application/job_registry.dart';
import 'reading_metadata_host.dart';
import 'reading_metadata_job.dart';

class ReadingMetadataJobs {
  ReadingMetadataJobs(
    this.library, {
    required this.provider,
    required this.createJob,
  });
  final ReadingMetadataJob Function(String, PublicationProvider) createJob;
  final ReadingMetadataHost library;
  late final registry = ApplicationJobs(maintenance: library.maintenance);
  final PublicationProvider provider;
  ReadingMetadataJob job(String id, PublicationProvider source) =>
      registry.obtain(
        '${source.id}:$id',
        () => createJob(id, source),
        authorized: () => library.authorized(id),
      );
}
