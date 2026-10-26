import '../features/reading/application/reader_keys.dart';
import 'comic_reader_controller.dart';
import 'text_reader_controller.dart';
import 'reading_annotations_repository.dart';
import '../features/reading/application/reading_session.dart';
import '../features/catalog/application/reading_catalog_commands.dart';
import 'domain/reading_catalog.dart';

/// Host composition boundary used by reader entry points. Widgets receive an
/// engine/session bundle without depending on channels or storage services.
abstract interface class ReaderHost {
  Object get persistenceOwner;
  ({
    TextReaderController controller,
    ReadingSession session,
    ReadingAnnotationsRepository annotations,
  })
  text();
  ({
    ComicReaderController controller,
    ReadingSession session,
    ReadingCatalogCommands workflows,
    ComicVolumeKeys keys,
  })
  pages(ReadingFormat format);
}
