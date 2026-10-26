import 'contracts.dart';
import 'audio_models.dart';
import '../catalog/domain/media_group.dart';

String audiobookSeriesIdentity(Audiobook book) =>
    '${book.id.collectionId}:${book.metadata.seriesId.isNotEmpty
        ? book.metadata.seriesId
        : book.metadata.series.trim().isNotEmpty
        ? book.metadata.series.trim().toLowerCase()
        : 'standalone:${book.id.itemId}'}';
String audiobookSeriesTitle(Audiobook book) =>
    book.metadata.series.trim().isNotEmpty
    ? book.metadata.series
    : book.metadata.title;
List<MediaGroup<Audiobook>> audiobookSeries(
  List<Audiobook> books,
) => groupMedia(books, audiobookSeriesIdentity).entries.map((entry) {
  final children = entry.value
    ..sort((a, b) {
      final n =
          (a.metadata.seriesOrder == 0
                  ? double.infinity
                  : a.metadata.seriesOrder)
              .compareTo(
                b.metadata.seriesOrder == 0
                    ? double.infinity
                    : b.metadata.seriesOrder,
              );
      return n != 0 ? n : naturalAudioOrder(a.metadata.title, b.metadata.title);
    });
  return MediaGroup(entry.key, audiobookSeriesTitle(children.first), children);
}).toList()..sort((a, b) => naturalAudioOrder(a.title, b.title));

Audiobook? audiobookResumeTarget(
  List<Audiobook> ordered,
  Map<MediaId, AudiobookProgress> progress,
) {
  if (ordered.isEmpty) return null;
  for (final book in ordered) {
    final saved = progress[book.id];
    if (saved != null &&
        !saved.finished &&
        (saved.positionMs > 0 ||
            saved.chapterId != book.chapterMarkers.first.id)) {
      return book;
    }
  }
  return ordered.where((b) => progress[b.id]?.finished != true).firstOrNull ??
      ordered.first;
}

String audiobookSearchText(Audiobook book, {AudiobookSeriesMetadata? series}) =>
    [
      book.metadata.title,
      book.metadata.author,
      book.metadata.narrator,
      audiobookSeriesTitle(book),
      series?.title ?? '',
      series?.author ?? '',
    ].join(' ').toLowerCase();
