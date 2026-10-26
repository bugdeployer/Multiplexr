import 'package:multiplexr/src/library/library_models.dart';

Future<VideoAsset> matchedAsset(
  dynamic service,
  VideoAsset asset,
  VideoSubtype subtype,
  Map<String, dynamic> match,
) async {
  final id = match['id'] as int;
  final data = await service.details(
    subtype == VideoSubtype.movies ? 'movie' : 'tv',
    id,
    season: subtype == VideoSubtype.tv
        ? int.tryParse(asset.metadata['season'] ?? '')
        : null,
    episode: subtype == VideoSubtype.tv
        ? int.tryParse(asset.metadata['episode'] ?? '')
        : null,
  );
  final metadata = {...asset.metadata};
  if (subtype == VideoSubtype.movies) {
    metadata['title'] = data['title'] ?? asset.title;
    metadata['year'] = (data['release_date'] as String? ?? '').split('-').first;
    metadata['genres'] = (data['genres'] as List? ?? [])
        .map((g) => g['name'])
        .join(', ');
    final crew = (data['credits']?['crew'] as List? ?? []).where(
      (p) => p['job'] == 'Director',
    );
    metadata['director'] = crew.map((p) => p['name']).join(', ');
  } else {
    metadata['series'] =
        data['series']?['name'] ?? match['name'] ?? metadata['series'] ?? '';
    final seasonDetails = (data['series']?['seasons'] as List? ?? [])
        .where(
          (s) =>
              s['season_number'] ==
              int.tryParse(asset.metadata['season'] ?? ''),
        )
        .firstOrNull;
    if (seasonDetails?['episode_count'] != null) {
      metadata['seasonEpisodeCount'] = '${seasonDetails['episode_count']}';
    }
    metadata['seriesOverview'] =
        data['series']?['overview'] ?? metadata['seriesOverview'] ?? '';
    metadata['genres'] = (data['series']?['genres'] as List? ?? [])
        .map((g) => g['name'])
        .join(', ');
    metadata.addAll(
      cinemaMetadata(Map<String, dynamic>.from(data['series'] ?? {})),
    );
    if (data['episode_number'] != null) {
      metadata['title'] = data['name'] ?? asset.title;
      metadata['airDate'] = data['air_date'] ?? '';
    }
  }
  metadata['description'] = data['overview'] ?? match['overview'] ?? '';
  metadata.addAll(cinemaMetadata(data));
  final poster =
      data['poster_path'] ??
      data['series']?['poster_path'] ??
      match['poster_path'];
  final backdrop =
      data['backdrop_path'] ?? data['still_path'] ?? match['backdrop_path'];
  return VideoAsset.fromJson({
    ...asset.toJson(),
    'metadata': metadata,
    'providerId': id,
    if (subtype == VideoSubtype.tv) 'seriesId': id,
    if (subtype == VideoSubtype.tv && data['series']?['backdrop_path'] != null)
      'seriesBackdrop':
          'https://image.tmdb.org/t/p/w1280${data['series']['backdrop_path']}',
    if (subtype == VideoSubtype.tv) 'episodeId': data['id'],
    'metadataSource': 'tmdb',
    'metadataStatus': '',
    'poster': poster == null ? null : 'https://image.tmdb.org/t/p/w342$poster',
    'backdrop': backdrop == null
        ? null
        : 'https://image.tmdb.org/t/p/w1280$backdrop',
  }, subtype);
}

Map<String, String> cinemaMetadata(Map<String, dynamic> data) => {
  if ((data['tagline'] as String? ?? '').isNotEmpty) 'tagline': data['tagline'],
  if (data['runtime'] is num && data['runtime'] > 0)
    'runtimeMinutes': '${data['runtime']}',
  if ((data['credits']?['cast'] as List? ?? []).isNotEmpty)
    'cast': (data['credits']['cast'] as List)
        .take(6)
        .map((p) => p['name'])
        .join(', '),
};
