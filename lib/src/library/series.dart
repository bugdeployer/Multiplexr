import '../catalog/domain/media_group.dart';
import 'library_models.dart';

int? seasonNumber(VideoAsset a) => int.tryParse(a.metadata['season'] ?? '');
int? episodeNumber(VideoAsset a) => int.tryParse(a.metadata['episode'] ?? '');
bool identifiedEpisode(VideoAsset a) =>
    seasonNumber(a) != null &&
    seasonNumber(a)! >= 0 &&
    episodeNumber(a) != null &&
    episodeNumber(a)! > 0;

String? seriesIdentity(VideoAsset a) {
  if (a.contentSubtype != VideoSubtype.tv &&
      a.mediaSubtype != VideoSubtype.tv) {
    return null;
  }
  final corrected = a.metadata['groupId'];
  if (corrected != null && corrected.isNotEmpty) return 'manual:$corrected';
  final structural = a.metadata['structuralSeriesId'];
  if (structural != null && structural.isNotEmpty) return structural;
  if (a.seriesId != null ||
      (a.providerId != null && a.metadataSource == 'tmdb')) {
    return 'tmdb:${a.seriesId ?? a.providerId}';
  }
  final name = (a.metadata['series'] ?? '').trim().toLowerCase();
  if (name.isEmpty || a.rootUri.isEmpty || !identifiedEpisode(a)) return null;
  final parts = a.relativePath.split('/')..removeLast();
  final seasonFolder = parts.indexWhere(
    (p) => RegExp(
      r'^(season[ ._-]*\d+|s\d+|specials)$',
      caseSensitive: false,
    ).hasMatch(p),
  );
  final parent = (seasonFolder < 0 ? parts : parts.take(seasonFolder))
      .join('/')
      .toLowerCase();
  return 'local:${a.rootUri}:$parent:$name';
}

class EpisodeRecord {
  EpisodeRecord(this.seriesKey, this.season, this.number, this.versions);
  final String seriesKey;
  final int? season, number;
  final List<VideoAsset> versions;
  String get id => '$seriesKey:${season ?? "?"}:${number ?? versions.first.id}';
  VideoAsset get asset =>
      versions.where((a) => a.available).firstOrNull ?? versions.first;
  bool get watched => versions.any((a) => a.watched);
  bool get available => versions.any((a) => a.available);
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': asset.collectionId,
    'seriesId': seriesKey,
    'season': season,
    'episode': number,
    'assetIds': versions.map((a) => a.id).toList(),
    'providerId': asset.episodeId,
  };
}

class SeasonRecord {
  SeasonRecord(this.seriesKey, this.number, this.episodes);
  final String seriesKey;
  final int number;
  final List<EpisodeRecord> episodes;
  String get id => '$seriesKey:$number';
  String get label => number == 0 ? 'Specials' : 'Season $number';
  Map<String, dynamic> toJson() => {
    'id': '$seriesKey:$number',
    'collectionId': episodes.first.asset.collectionId,
    'seriesId': seriesKey,
    'number': number,
    'episodeIds': episodes.map((e) => e.id).toList(),
  };
}

class SeriesRecord {
  SeriesRecord(this.id, this.assets, {this.needsIdentification = false});
  final String id;
  final List<VideoAsset> assets;
  final bool needsIdentification;
  VideoAsset get artwork {
    final source =
        assets
            .where(
              (a) =>
                  a.seriesBackdrop != null ||
                  a.localSeriesBackdrop != null ||
                  a.metadata['seriesPoster']?.isNotEmpty == true,
            )
            .firstOrNull ??
        assets
            .where((a) => a.poster != null || a.thumbnail != null)
            .firstOrNull ??
        assets.first;
    if (source.seriesBackdrop == null &&
        source.localSeriesBackdrop == null &&
        source.metadata['seriesPoster']?.isNotEmpty != true) {
      return source;
    }
    return VideoAsset.fromJson({
      ...source.toJson(),
      if (source.metadata['seriesPoster']?.isNotEmpty == true) ...{
        'poster': source.metadata['seriesPoster'],
        'localPoster': null,
      },
      'backdrop': source.seriesBackdrop,
      'localBackdrop': source.localSeriesBackdrop,
    }, VideoSubtype.tv);
  }

  String get name => needsIdentification
      ? 'Needs identification'
      : assets.first.metadata['series'] ?? assets.first.title;
  String get summary {
    if (needsIdentification) {
      return '${assets.length} ${assets.length == 1 ? 'file' : 'files'} to identify';
    }
    final regular = seasons.where((s) => s.number != 0).length;
    return '$regular season${regular == 1 ? '' : 's'}${seasons.any((s) => s.number == 0) ? ' + Specials' : ''} · ${episodes.length} episode${episodes.length == 1 ? '' : 's'}';
  }

  String get overview =>
      assets
          .map((a) => a.metadata['seriesOverview'] ?? '')
          .where((s) => s.isNotEmpty)
          .firstOrNull ??
      '';
  late final List<EpisodeRecord> episodes = _buildEpisodes();
  List<EpisodeRecord> _buildEpisodes() {
    final groups = <String, List<VideoAsset>>{};
    for (final a in assets) {
      final key = identifiedEpisode(a)
          ? '${seasonNumber(a)}:${episodeNumber(a)}'
          : a.id;
      groups.putIfAbsent(key, () => []).add(a);
    }
    return groups.values
        .map(
          (v) => EpisodeRecord(
            id,
            identifiedEpisode(v.first) ? seasonNumber(v.first) : null,
            identifiedEpisode(v.first) ? episodeNumber(v.first) : null,
            v,
          ),
        )
        .toList()
      ..sort((a, b) {
        final left = int.tryParse(a.asset.metadata['groupOrder'] ?? '');
        final right = int.tryParse(b.asset.metadata['groupOrder'] ?? '');
        if (left != null || right != null) {
          return (left ?? 999999).compareTo(right ?? 999999);
        }
        final season = (a.season ?? 99999).compareTo(b.season ?? 99999);
        return season != 0
            ? season
            : (a.number ?? 99999).compareTo(b.number ?? 99999);
      });
  }

  late final List<SeasonRecord> seasons =
      (episodes
              .where((e) => e.season != null && e.number != null)
              .map((e) => e.season!)
              .toSet()
              .toList()
            ..sort())
          .map(
            (n) => SeasonRecord(
              id,
              n,
              episodes.where((e) => e.season == n).toList(),
            ),
          )
          .toList();
  VideoAsset? get resume {
    final started =
        assets.where((a) => a.inProgress && identifiedEpisode(a)).toList()
          ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    if (started.isNotEmpty) return started.first;
    final regular = episodes
        .where(
          (e) =>
              e.season != null &&
              e.number != null &&
              e.season != 0 &&
              e.available,
        )
        .toList();
    return regular.where((e) => !e.watched).firstOrNull?.asset ??
        regular.firstOrNull?.asset ??
        episodes
            .where((e) => e.number != null && e.available)
            .firstOrNull
            ?.asset;
  }

  late final VideoAsset card = VideoAsset.fromJson({
    ...artwork.toJson(),
    'metadata': {...artwork.metadata, 'title': name, 'description': overview},
    'favorite': assets.any((a) => a.favorite),
    'watchLater': assets.any((a) => a.watchLater),
    'watched': episodes.every((e) => e.watched),
    'addedAt': assets.map((a) => a.addedAt).reduce((a, b) => a > b ? a : b),
    'lastPlayedAt': assets
        .map((a) => a.lastPlayedAt)
        .reduce((a, b) => a > b ? a : b),
  }, VideoSubtype.tv);
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': assets.first.collectionId,
    'name': name,
    'providerId': assets.first.seriesId ?? assets.first.providerId,
    'needsIdentification': needsIdentification,
    'assetIds': assets.map((a) => a.id).toList(),
  };
}

List<SeriesRecord> buildSeries(List<VideoAsset> assets) {
  final groups = groupMedia(
    assets.where((a) => a.mediaSubtype == VideoSubtype.tv),
    (VideoAsset a) =>
        '${a.collectionId}:${seriesIdentity(a) ?? "unidentified"}',
  );
  return groups.entries
      .map(
        (e) => SeriesRecord(
          e.key,
          e.value,
          needsIdentification: e.key.endsWith(':unidentified'),
        ),
      )
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

SeriesRecord? seriesFor(VideoAsset asset, List<VideoAsset> all) =>
    buildSeries(all)
        .where(
          (s) => s.assets.any(
            (a) => a.id == asset.id && a.collectionId == asset.collectionId,
          ),
        )
        .firstOrNull;
List<VideoAsset> groupedTitles(List<VideoAsset> all) => [
  ...all.where((a) => a.mediaSubtype != VideoSubtype.tv),
  ...buildSeries(all).map((s) => s.card),
];
EpisodeRecord? nextEpisodeRecord(VideoAsset current, List<VideoAsset> all) {
  if (!identifiedEpisode(current) || seasonNumber(current) == 0) return null;
  return seriesFor(current, all)?.episodes
      .where(
        (e) =>
            e.season != null &&
            e.number != null &&
            e.season != 0 &&
            e.available &&
            (e.season! > seasonNumber(current)! ||
                (e.season == seasonNumber(current) &&
                    e.number! > episodeNumber(current)!)),
      )
      .firstOrNull;
}

VideoAsset? nextEpisode(VideoAsset current, List<VideoAsset> all) {
  final next = nextEpisodeRecord(current, all);
  return next?.versions.where((a) => a.available).length == 1
      ? next!.asset
      : null;
}

List<VideoAsset> seriesContinuation(List<VideoAsset> all) {
  final result = all
      .where((a) => a.mediaSubtype != VideoSubtype.tv && a.inProgress)
      .toList();
  for (final s in buildSeries(all)) {
    if (s.needsIdentification) continue;
    final inProgress =
        s.assets.where((a) => a.inProgress && identifiedEpisode(a)).toList()
          ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    if (inProgress.isNotEmpty) {
      result.add(inProgress.first);
      continue;
    }
    final played = s.assets.where((a) => a.lastPlayedAt > 0).toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
    if (played.isNotEmpty &&
        played.first.watched &&
        !played.first.hiddenFromContinue) {
      final next = nextEpisodeRecord(played.first, s.assets);
      if (next != null && !next.watched) {
        result.add(
          VideoAsset.fromJson({
            ...next.asset.toJson(),
            'lastPlayedAt': played.first.lastPlayedAt,
          }, VideoSubtype.tv),
        );
      }
    }
  }
  return result..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));
}

VideoAsset withSelectedArtwork(
  VideoAsset asset,
  String kind,
  String url, {
  bool series = false,
}) {
  final poster = kind == 'posters';
  if (series && poster) {
    return VideoAsset.fromJson({
      ...asset.toJson(),
      'metadata': {
        ...asset.metadata,
        'seriesPoster': url,
        'seriesPosterSource': 'manual',
      },
    }, asset.mediaSubtype);
  }
  final remoteKey = poster
      ? 'poster'
      : series
      ? 'seriesBackdrop'
      : 'backdrop';
  final localKey = poster
      ? 'localPoster'
      : series
      ? 'localSeriesBackdrop'
      : 'localBackdrop';
  return VideoAsset.fromJson({
    ...asset.toJson(),
    remoteKey: url,
    localKey: null,
    'metadata': {...asset.metadata, '${remoteKey}Source': 'manual'},
  }, asset.mediaSubtype);
}
