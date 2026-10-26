import '../settings/domain/media_settings.dart';
import '../experience/navigation/opening_policy.dart';
import '../media/contracts.dart';

enum VideoSubtype {
  videos('Videos'),
  cinema('Movies & TV'),
  movies('Movies'),
  tv('TV shows');

  const VideoSubtype(this.label);
  final String label;
}

enum CatalogView {
  grid('Grid'),
  list('List'),
  netflix('Netflix'),
  posterWall('Poster wall'),
  compact('Compact list');

  const CatalogView(this.label);
  final String label;
}

enum PlaybackTarget { internal, external }

class LibraryRoot {
  const LibraryRoot(this.uri, this.name, {this.contentSubtype});
  final String uri, name;
  final VideoSubtype? contentSubtype;
  Map<String, dynamic> toJson() => {
    'uri': uri,
    'name': name,
    if (contentSubtype != null) 'contentSubtype': contentSubtype!.name,
  };
  factory LibraryRoot.fromJson(Map<String, dynamic> data) => LibraryRoot(
    data['uri'] as String,
    data['name'] as String,
    contentSubtype: data['contentSubtype'] == 'tv'
        ? VideoSubtype.tv
        : data['contentSubtype'] == 'movies'
        ? VideoSubtype.movies
        : null,
  );
}

class VideoCollection {
  const VideoCollection({
    required this.id,
    required this.name,
    required this.subtype,
    this.kind = MediaKind.video,
    this.includeInGlobalAudio = true,
    this.view = CatalogView.grid,
    this.player = PlaybackTarget.internal,
    this.roots = const [],
    this.openAction = 'automatic',
    this.audioRate = 1,
    this.autoplayNext = false,
    this.locked = false,
    this.includeInGlobalCinema = true,
    this.includeInGlobalVideos = true,
    this.allowFolders = false,
    this.sort = 'title',
    this.filter = 'all',
    this.cardSize = 180,
    this.scrollOffset = 0,
    this.folder = '',
    this.lastScanAt = 0,
    this.rootHealth = const {},
    this.extensions = const ['mp4', 'mkv', 'mov', 'webm', 'm4v'],
  });
  final String id, name;
  final VideoSubtype subtype;
  final MediaKind kind;
  final bool includeInGlobalAudio;
  bool get isAudio => kind == MediaKind.audiobook || kind == MediaKind.music;
  MediaSubtype get mediaSubtype => switch (kind) {
    MediaKind.audiobook => MediaSubtype.audiobooks,
    MediaKind.music => MediaSubtype.music,
    MediaKind.video =>
      subtype == VideoSubtype.videos
          ? MediaSubtype.videos
          : MediaSubtype.moviesTv,
  };
  MediaType get mediaType => mediaSubtype.type;
  AudioSubtype get audioSubtype =>
      kind == MediaKind.music ? AudioSubtype.music : AudioSubtype.audiobooks;
  String get mediaLabel => isAudio
      ? (kind == MediaKind.music ? 'Music' : 'Audiobooks')
      : subtype.label;
  final String openAction;
  final double audioRate;
  bool opensDetails({required bool legacy}) =>
      OpeningPolicy.legacyAction(openAction, legacyDetails: legacy) ==
      TitleOpenAction.details;
  final CatalogView view;
  final PlaybackTarget player;
  final List<LibraryRoot> roots;
  final List<String> extensions;
  final bool autoplayNext,
      allowFolders,
      locked,
      includeInGlobalCinema,
      includeInGlobalVideos;
  final String sort, filter, folder;
  final double cardSize, scrollOffset;
  final int lastScanAt;
  final Map<String, String> rootHealth;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': mediaType.name,
    if (isAudio) 'includeInGlobalAudio': includeInGlobalAudio,
    'subtype': isAudio ? audioSubtype.name : subtype.name,
    'view': view.name,
    'player': player.name,
    'roots': roots.map((r) => r.toJson()).toList(),
    'locked': locked,
    'includeInGlobalCinema': includeInGlobalCinema,
    'includeInGlobalVideos': includeInGlobalVideos,
    'openAction': openAction,
    'audioRate': audioRate,
    'autoplayNext': autoplayNext,
    'allowFolders': allowFolders,
    'sort': sort,
    'filter': filter,
    'cardSize': cardSize,
    'scrollOffset': scrollOffset,
    'folder': folder,
    'lastScanAt': lastScanAt,
    'rootHealth': rootHealth,
    'extensions': extensions,
  };
  factory VideoCollection.fromJson(Map<String, dynamic> d) => VideoCollection(
    kind: d['type'] == 'audio'
        ? (d['subtype'] == 'music' ? MediaKind.music : MediaKind.audiobook)
        : d['type'] == 'audiobook'
        ? MediaKind.audiobook
        : MediaKind.video,
    includeInGlobalAudio: d['includeInGlobalAudio'] != false,
    locked: d['locked'] == true,
    includeInGlobalCinema: d['includeInGlobalCinema'] != false,
    includeInGlobalVideos: d['includeInGlobalVideos'] != false,
    openAction: ['details', 'play'].contains(d['openAction'])
        ? d['openAction']
        : 'automatic',
    audioRate: (d['audioRate'] as num? ?? 1).toDouble().clamp(.5, 3),
    autoplayNext: d['autoplayNext'] == true,
    allowFolders: d['allowFolders'] == true,
    sort: d['sort'] ?? 'title',
    filter: d['filter'] ?? 'all',
    cardSize: (d['cardSize'] as num? ?? 180).toDouble(),
    scrollOffset: (d['scrollOffset'] as num? ?? 0).toDouble(),
    folder: d['folder'] ?? '',
    lastScanAt: d['lastScanAt'] ?? 0,
    rootHealth: Map<String, String>.from(d['rootHealth'] ?? {}),
    id: d['id'],
    name: d['name'],
    subtype: d['subtype'] == 'videos'
        ? VideoSubtype.videos
        : VideoSubtype.cinema,
    view: CatalogView.values.byName(d['view']),
    player: PlaybackTarget.values.byName(d['player']),
    roots: (d['roots'] as List)
        .map(
          (r) => LibraryRoot.fromJson({
            if (d['type'] == 'video' && d['subtype'] != 'videos')
              'contentSubtype': d['subtype'] == 'tv' ? 'tv' : 'movies',
            ...Map<String, dynamic>.from(r),
          }),
        )
        .toList(),
    extensions: List<String>.from(d['extensions']),
  );
}

/// Technical fields are shared; each subtype has its own descriptive schema.
const metadataFields = <VideoSubtype, Map<String, String>>{
  VideoSubtype.cinema: {
    'title': 'Title',
    'year': 'Release year',
    'description': 'Overview',
    'director': 'Director',
    'genres': 'Genres',
    'series': 'Series',
    'season': 'Season',
    'episode': 'Episode',
    'airDate': 'Air date',
  },
  VideoSubtype.videos: {
    'title': 'Title',
    'description': 'Description',
    'recordedDate': 'Recorded date',
    'tags': 'Tags',
  },
  VideoSubtype.movies: {
    'title': 'Title',
    'year': 'Release year',
    'description': 'Overview',
    'director': 'Director',
    'genres': 'Genres',
  },
  VideoSubtype.tv: {
    'title': 'Episode title',
    'series': 'Series',
    'season': 'Season',
    'episode': 'Episode',
    'airDate': 'Air date',
    'description': 'Overview',
  },
};
Map<String, String> inferMetadata(
  String filename,
  VideoSubtype subtype, {
  String relativePath = '',
  String rootUri = '',
}) {
  if (subtype == VideoSubtype.cinema) {
    subtype = RegExp(r'[sS]\d{1,2}[eE]\d{1,3}').hasMatch(filename)
        ? VideoSubtype.tv
        : VideoSubtype.movies;
  }
  final stem = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
  if (subtype == VideoSubtype.tv &&
      RegExp(r'[sS]\d{1,2}[eE]\d{1,3}(?:[eE]\d{1,3}\b|-[eE]?\d{1,3}\b)')
          .hasMatch(stem)) {
    return {'title': stem.replaceAll('.', ' ')};
  }
  final episode = RegExp(
    r'^(.*?)[ ._-]+[sS](\d{1,2})[eE](\d{1,3})(?:[ ._-]+(.*))?$',
  ).firstMatch(stem);
  final year = RegExp(r'(?:^|[ ._(\[-])((?:19|20)\d{2})(?:$|[ ._)\]-])')
      .firstMatch(stem);
  String clean(String value) => value
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (subtype == VideoSubtype.tv && episode != null) {
    return {
      'title': clean(episode.group(4) ?? stem),
      'series': clean(episode.group(1)!),
      'season': '${int.parse(episode.group(2)!)}',
      'episode': '${int.parse(episode.group(3)!)}',
    };
  }
  if (subtype == VideoSubtype.tv) {
    final alternate = RegExp(
      r'^(.*?)[ ._-]+(\d{1,2})x(\d{1,3})(?:[ ._-]+(.*))?$',
      caseSensitive: false,
    ).firstMatch(stem);
    if (alternate != null) {
      return {
        'series': clean(alternate[1]!),
        'season': '${int.parse(alternate[2]!)}',
        'episode': '${int.parse(alternate[3]!)}',
        'title': clean(alternate[4] ?? stem),
      };
    }
    final dirs = relativePath.split('/')..removeLast();
    final seasonDir = dirs.indexWhere(
      (p) => RegExp(
        r'^(season[ ._-]*\d+|s\d+|specials)$',
        caseSensitive: false,
      ).hasMatch(p),
    );
    final number = RegExp(
      r'^(?:e(?:pisode)?[ ._-]*)?(\d{1,3})(?:[ ._-]+(.*))?$',
      caseSensitive: false,
    ).firstMatch(stem);
    if (seasonDir >= 0 && number != null) {
      final folder = dirs[seasonDir];
      final rootName =
          Uri.tryParse(rootUri)?.pathSegments.lastOrNull
              ?.split('/')
              .last
              .split(':')
              .last ??
          '';
      return {
        'series': clean(seasonDir > 0 ? dirs[seasonDir - 1] : rootName),
        'season': folder.toLowerCase() == 'specials'
            ? '0'
            : RegExp(r'\d+').firstMatch(folder)!.group(0)!,
        'episode': '${int.parse(number[1]!)}',
        'title': clean(number[2] ?? stem),
      };
    }
  }
  return {
    'title': clean(
      subtype == VideoSubtype.movies && year != null
          ? stem.substring(0, year.start)
          : stem,
    ),
    if (subtype == VideoSubtype.movies && year != null) 'year': year.group(1)!,
  };
}

class VideoAsset {
  const VideoAsset({
    required this.id,
    required this.collectionId,
    required this.uri,
    required this.filename,
    required this.metadata,
    this.durationMs = 0,
    this.width = 0,
    this.height = 0,
    this.positionMs = 0,
    this.poster,
    this.backdrop,
    this.thumbnail,
    this.providerId,
    this.metadataSource = 'filename',
    this.addedAt = 0,
    this.contentSubtype,
    this.favorite = false,
    this.watchLater = false,
    this.seriesId,
    this.seriesBackdrop,
    this.localSeriesBackdrop,
    this.episodeId,
    this.watched = false,
    this.hiddenFromContinue = false,
    this.lastPlayedAt = 0,
    this.completedAt = 0,
    this.rootUri = '',
    this.relativePath = '',
    this.available = true,
    this.metadataStatus = '',
    this.localPoster,
    this.localBackdrop,
  });
  final bool favorite, watchLater;
  final int? seriesId, episodeId;
  final String? seriesBackdrop, localSeriesBackdrop;
  final bool watched, hiddenFromContinue, available;
  final int lastPlayedAt, completedAt;
  final String rootUri, relativePath, metadataStatus;
  final String? localPoster, localBackdrop;
  bool get inProgress =>
      !watched &&
      !hiddenFromContinue &&
      available &&
      positionMs > 0 &&
      (durationMs <= 0 || positionMs < durationMs);
  final String id, collectionId, uri, filename;
  final Map<String, String> metadata;
  final int durationMs, width, height, positionMs;
  final int addedAt;
  final VideoSubtype? contentSubtype;
  VideoSubtype get mediaSubtype =>
      contentSubtype == VideoSubtype.tv ||
          (contentSubtype == null && metadata.containsKey('season'))
      ? VideoSubtype.tv
      : VideoSubtype.movies;
  final String? poster, backdrop, thumbnail;
  final String metadataSource;
  final int? providerId;
  String get title =>
      metadata['title']?.isNotEmpty == true ? metadata['title']! : filename;
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'uri': uri,
    'filename': filename,
    'metadata': metadata,
    'durationMs': durationMs,
    'width': width,
    'height': height,
    'positionMs': positionMs,
    'favorite': favorite,
    'watchLater': watchLater,
    'seriesId': seriesId,
    'seriesBackdrop': seriesBackdrop,
    'localSeriesBackdrop': localSeriesBackdrop,
    'episodeId': episodeId,
    'watched': watched,
    'hiddenFromContinue': hiddenFromContinue,
    'lastPlayedAt': lastPlayedAt,
    'completedAt': completedAt,
    'rootUri': rootUri,
    'relativePath': relativePath,
    'available': available,
    'metadataStatus': metadataStatus,
    'localPoster': localPoster,
    'localBackdrop': localBackdrop,
    'poster': poster,
    'backdrop': backdrop,
    'thumbnail': thumbnail,
    'providerId': providerId,
    'metadataSource': metadataSource,
    'addedAt': addedAt,
    'contentSubtype': contentSubtype?.name,
  };
  factory VideoAsset.fromJson(Map<String, dynamic> d, VideoSubtype subtype) =>
      VideoAsset(
        id: d['id'],
        collectionId: d['collectionId'],
        uri: d['uri'],
        filename: d['filename'],
        metadata: assetMetadata(d, assetSubtype(d, subtype)),
        durationMs: d['durationMs'] ?? 0,
        width: d['width'] ?? 0,
        height: d['height'] ?? 0,
        positionMs: d['positionMs'] ?? 0,
        favorite: d['favorite'] == true,
        watchLater: d['watchLater'] == true,
        seriesId:
            d['seriesId'] ??
            (assetSubtype(d, subtype) == VideoSubtype.tv &&
                    d['metadataSource'] == 'tmdb'
                ? d['providerId']
                : null),
        episodeId: d['episodeId'],
        seriesBackdrop: d['seriesBackdrop'],
        localSeriesBackdrop: d['localSeriesBackdrop'],
        watched: d['watched'] == true,
        hiddenFromContinue: d['hiddenFromContinue'] == true,
        lastPlayedAt: d['lastPlayedAt'] ?? 0,
        completedAt: d['completedAt'] ?? 0,
        rootUri: d['rootUri'] ?? '',
        relativePath: d['relativePath'] ?? '',
        available: d['available'] != false,
        metadataStatus: d['metadataStatus'] ?? '',
        localPoster: d['localPoster'],
        localBackdrop: d['localBackdrop'],
        poster: d['poster'],
        backdrop: d['backdrop'],
        thumbnail: d['thumbnail'],
        providerId: d['providerId'],
        metadataSource: d['metadataSource'] ?? 'filename',
        addedAt: d['addedAt'] ?? 0,
        contentSubtype: assetSubtype(d, subtype),
      );
}

Map<String, String> assetMetadata(
  Map<String, dynamic> data,
  VideoSubtype type,
) {
  final inferred = inferMetadata(
    data['filename'],
    type,
    relativePath: data['relativePath'] ?? '',
    rootUri: data['rootUri'] ?? '',
  );
  if (data['metadata'] == null) return inferred;
  final stored = Map<String, String>.from(data['metadata']);
  return (data['metadataSource'] ?? 'filename') == 'filename'
      ? {
          ...inferred,
          ...Map.fromEntries(
            stored.entries.where(
              (e) => e.value.isNotEmpty || !inferred.containsKey(e.key),
            ),
          ),
        }
      : stored;
}

VideoSubtype assetSubtype(Map<String, dynamic> d, VideoSubtype collection) {
  if (d['contentSubtype'] == 'tv') return VideoSubtype.tv;
  if (d['contentSubtype'] == 'movies') return VideoSubtype.movies;
  if (collection != VideoSubtype.cinema) return collection;
  return (d['metadata'] as Map?)?.containsKey('season') == true ||
          RegExp(r'[sS]\d{1,2}[eE]\d{1,3}').hasMatch(d['filename'] as String)
      ? VideoSubtype.tv
      : VideoSubtype.movies;
}
