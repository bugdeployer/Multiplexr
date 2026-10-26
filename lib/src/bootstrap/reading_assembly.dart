import '../features/metadata/application/publication_provider.dart';
import 'metadata_assembly.dart';
import '../reading/reading_metadata.dart';
import '../reading/reading_library.dart';
import '../reading/reading_app_controller.dart';
import 'reader_assembly.dart';
import '../reading/reading_repository.dart';
import '../reading/reading_annotations_repository.dart';
import '../reading/reading_metadata_jobs.dart';
import '../reading/legacy_reading_sources.dart';
import '../reading/legacy_reading_catalog_store.dart';
import '../features/settings/application/reader_preference_commands.dart';
import '../features/sources/application/reading_source_ports.dart';
import '../library/library_controller.dart';
import '../library/library_service.dart';
import '../core/application/clock.dart';
import '../core/platform/system_clock.dart';
import 'library_assembly.dart';

ReadingLibrary createReadingLibrary(
  LibraryService service, {
  required bool Function(String) authorized,
  ReadingSources? sources,
  ReadingCatalogStore? store,
  LibraryController? collectionForms,
  Clock clock = const SystemClock(),
  PublicationProvider? metadataProvider,
}) {
  late ReadingLibrary reading;
  LibraryController? ownedForms;
  reading = ReadingLibrary(
    service,
    authorized: authorized,
    sources: sources ?? LegacyReadingSources(service),
    store: store ?? LegacyReadingCatalogStore(service),
    collectionForms: () =>
        collectionForms ?? (ownedForms ??= createLibraryController(service)),
    releaseCollectionForms: () {
      ownedForms?.dispose();
      ownedForms = null;
    },
    readerHost: ReaderSessionFactory(service, authorized: authorized),
    readerPreferences: ReaderPreferenceCommands(
      ReadingRepository(service),
      authorized: authorized,
    ),
    annotations: ReadingAnnotationsRepository(service, authorized: authorized),
    metadataJobsFactory: () => ReadingMetadataJobs(
      reading,
      provider: metadataProvider ?? NoInstalledPublicationProvider(),
      createJob: (id, provider) =>
          createReadingMetadataJob(reading, id, provider),
    ),
    clock: clock,
  );
  return reading;
}

ReadingAppController createReadingAppController(
  LibraryService service, {
  required Future<bool> Function() authenticate,
  required bool Function() appBlocked,
  ReadingLibrary Function(bool Function(String))? libraryFactory,
}) => ReadingAppController(
  service,
  authenticate: authenticate,
  appBlocked: appBlocked,
  libraryFactory:
      libraryFactory ??
      (authorized) => createReadingLibrary(service, authorized: authorized),
);
