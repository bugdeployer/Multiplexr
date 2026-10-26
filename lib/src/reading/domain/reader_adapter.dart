import '../../catalog/domain/classification.dart';
import 'reading_catalog.dart';
import 'reading_location.dart';

enum ReaderCapability {
  contents,
  search,
  selection,
  annotations,
  reflow,
  rtl,
  webtoon,
  zoom,
}

/// Host owns source grants, cache limits and authorization; adapters own rendering.
/// Text and comics share lifecycle, never playback engines or millisecond positions.
abstract interface class ReaderAdapter {
  String get id;
  MediaSubtype get subtype;
  Set<ReadingFormat> get formats;
  Set<ReaderCapability> get capabilities;
  Future<void> open(
    ReadingTitle title,
    ReadingLocation? restore,
    Map<String, Object> settings,
  );
  Future<ReadingLocation> location();
  Future<void> close();
}

abstract interface class TextReaderAdapter implements ReaderAdapter {}

abstract interface class ComicReaderAdapter implements ReaderAdapter {}

enum ReaderSessionState { closed, opening, open, recoveryRequired }

class ReadingRecoveryRequired implements Exception {
  const ReadingRecoveryRequired(this.saved);
  final ReadingProgress saved;
  @override
  String toString() =>
      'The publication changed. Choose a recovered position or start again.';
}
