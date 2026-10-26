import '../features/reading/application/reader_choices.dart';
import '../features/reading/application/reader_handoff.dart';
import 'reader_host.dart';
import 'domain/reading_catalog.dart';

abstract interface class EbookOpeningHost implements ReaderHost, ReaderChoices {
  Future<ReadingCatalog> readingPreferences();
  ExternalReaderPort externalReader();
}
