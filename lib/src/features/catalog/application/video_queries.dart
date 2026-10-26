import 'collection_presenter.dart';
import '../../../library/library_models.dart';

const catalogSorts = {
  'title': 'Title',
  'added': 'Recently added',
  'played': 'Last played',
  'year': 'Release year',
  'duration': 'Duration',
};
const catalogFilters = {
  'all': 'All videos',
  'favorite': 'Favorites',
  'watchLater': 'Watch later',
  'unwatched': 'Unwatched',
  'progress': 'In progress',
  'watched': 'Watched',
  'missing': 'Missing metadata',
  'review': 'Needs review',
  'failed': 'Metadata failed',
  'unavailable': 'Unavailable',
  'movies': 'Movies',
  'tv': 'TV episodes',
};

List<VideoAsset> browseVideos(
  List<VideoAsset> source, {
  String query = '',
  String filter = 'all',
  String sort = 'title',
  CollectionController<VideoAsset, String>? controller,
}) {
  final state =
      (controller ??
            CollectionController<VideoAsset, String>(identity: (a) => a.id))
        ..replace(source)
        ..query = query
        ..filter = filter
        ..sort = sort;
  final result = state.browse(
    matches: (a) {
      final matches = '${a.title} ${a.filename} ${a.metadata['series'] ?? ''}'
          .toLowerCase()
          .contains(query.toLowerCase());
      return matches &&
          switch (filter) {
            'favorite' => a.favorite,
            'watchLater' => a.watchLater,
            'unwatched' => !a.watched,
            'progress' => a.inProgress,
            'watched' => a.watched,
            'missing' => a.metadataSource == 'filename',
            'review' => a.metadataStatus == 'review',
            'failed' => a.metadataStatus == 'failed',
            'unavailable' => !a.available,
            'movies' => a.mediaSubtype == VideoSubtype.movies,
            'tv' => a.mediaSubtype == VideoSubtype.tv,
            _ => true,
          };
    },
  );
  result.sort((a, b) {
    final order = switch (sort) {
      'added' => b.addedAt.compareTo(a.addedAt),
      'played' => b.lastPlayedAt.compareTo(a.lastPlayedAt),
      'year' => (int.tryParse(b.metadata['year'] ?? '') ?? 0).compareTo(
        int.tryParse(a.metadata['year'] ?? '') ?? 0,
      ),
      'duration' => b.durationMs.compareTo(a.durationMs),
      _ => 0,
    };
    if (order != 0) return order;
    final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return title != 0 ? title : a.filename.compareTo(b.filename);
  });
  return result;
}

String folderToken(String root, String path) => '$root\n$path';
List<String> splitFolder(String token) => token.split('\n');
