import '../reading/comic_volume_keys.dart';
import '../reading/ebook_opening_host.dart';
import '../reading/legacy_reader_handoff.dart';
import '../features/reading/application/reader_choices.dart';
import '../features/reading/application/reader_handoff.dart';
import '../reading/legacy_reading_catalog_store.dart';
import '../library/library_service.dart';
import '../reading/domain/reading_catalog.dart';
import '../reading/comic_reader_controller.dart';
import '../reading/pdf_reader_adapter.dart';
import '../reading/reading_annotations_repository.dart';
import '../reading/reading_comic_source.dart';
import '../features/catalog/application/reading_catalog_commands.dart';
import '../reading/reading_repository.dart';
import '../features/reading/application/reading_session.dart';
import '../reading/native_reading_text_source.dart';
import '../reading/text_reader_controller.dart';

/// Engine composition stays outside reader widgets. Each route receives one
/// application session; PDF, text and comic renderers remain independent.
class ReaderSessionFactory implements EbookOpeningHost {
  const ReaderSessionFactory(this.service, {required this.authorized});
  @override
  Future<ReadingCatalog> readingPreferences() =>
      ReadingRepository(service).read();
  @override
  Future<List<InstalledReader>> installedReaders(String format) =>
      service.installedReaders(format);
  @override
  ExternalReaderPort externalReader() =>
      LegacyReaderHandoff(service, authorized: authorized);
  final LibraryService service;
  final bool Function(String) authorized;
  @override
  Object get persistenceOwner => service.persistenceOwner;
  @override
  ({
    TextReaderController controller,
    ReadingSession session,
    ReadingAnnotationsRepository annotations,
  })
  text() {
    final generation = service.maintenance.generation;
    bool access(String id) =>
        service.maintenance.isCurrent(generation) && authorized(id);
    final repository = ReadingRepository(service);
    final controller = TextReaderController(
      NativeReadingTextSource(service),
      repository,
      authorized: access,
    );
    return (
      controller: controller,
      session: ReadingSession(repository, controller, authorized: access),
      annotations: ReadingAnnotationsRepository(service, authorized: access),
    );
  }

  @override
  ({
    ComicReaderController controller,
    ReadingSession session,
    ReadingCatalogCommands workflows,
    ComicVolumeKeys keys,
  })
  pages(ReadingFormat format) {
    final generation = service.maintenance.generation;
    bool access(String id) =>
        service.maintenance.isCurrent(generation) && authorized(id);
    final repository = ReadingRepository(service);
    final controller = format == ReadingFormat.pdf
        ? PdfReaderController(service, repository, authorized: access)
        : ComicReaderController(
            NativeReadingComicSource(service),
            repository,
            authorized: access,
          );
    return (
      controller: controller,
      session: ReadingSession(repository, controller, authorized: access),
      keys: NativeComicVolumeKeys(),
      workflows: ReadingCatalogCommands(
        LegacyReadingCatalogStore(service),
        authorized: access,
      ),
    );
  }
}
