import '../library/library_service.dart';
import 'comic_reader_controller.dart';
import 'reading_comic_source.dart';
import '../features/reading/application/reading_progress_store.dart';

/// PDF shares fixed-page geometry and lifecycle, but has its own native renderer
/// and ebook settings. It never enters the text normalization pipeline.
class PdfReaderController extends ComicReaderController {
  PdfReaderController(
    LibraryService service,
    ReadingProgressStore repository, {
    required super.authorized,
  }) : super(NativeReadingPdfSource(service), repository, pdf: true);
}

class NativeReadingPdfSource extends NativeReadingComicSource {
  NativeReadingPdfSource(super.service) : super(pdf: true);
}
