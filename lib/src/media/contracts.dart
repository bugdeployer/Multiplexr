import 'dart:convert';

import '../catalog/domain/classification.dart';
export '../catalog/domain/classification.dart';

/// Legacy wire kinds: retain names and order for existing IDs and state keys.
enum MediaKind { video, audiobook, music }

/// Legacy audio wire subtype; neutral classification lives in catalog/domain.

enum AudioSubtype { audiobooks, music }

class MediaId {
  const MediaId(this.kind, this.collectionId, this.itemId);
  final MediaKind kind;
  final String collectionId, itemId;
  String get key => jsonEncode([kind.name, collectionId, itemId]);
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'collectionId': collectionId,
    'itemId': itemId,
  };
  factory MediaId.fromJson(Map<String, dynamic> json) => MediaId(
    MediaKind.values.byName(json['kind']),
    json['collectionId'],
    json['itemId'],
  );
  @override
  bool operator ==(Object other) => other is MediaId && key == other.key;
  @override
  int get hashCode => Object.hash(kind, collectionId, itemId);
}

class MediaSource {
  const MediaSource(this.uri, this.name);
  final String uri, name;
}

class CollectionAccess {
  const CollectionAccess({required this.locked, required this.includeInGlobal});
  final bool locked, includeInGlobal;
  bool get eligibleGlobally => includeInGlobal && !locked;
}

class MediaCollection {
  const MediaCollection({
    required this.id,
    required this.name,
    required this.kind,
    required this.access,
    required this.sources,
  });
  final String id, name;
  final MediaKind kind;
  MediaType get mediaType => switch (kind) {
    MediaKind.video => MediaType.video,
    MediaKind.audiobook || MediaKind.music => MediaType.audio,
  };
  AudioSubtype? get audioSubtype => switch (kind) {
    MediaKind.video => null,
    MediaKind.audiobook => AudioSubtype.audiobooks,
    MediaKind.music => AudioSubtype.music,
  };
  final CollectionAccess access;
  final List<MediaSource> sources;
}

sealed class MediaRecord {
  const MediaRecord(this.id, this.title);
  final MediaId id;
  final String title;
}

class VideoRecord extends MediaRecord {
  const VideoRecord(
    super.id,
    super.title, {
    required this.uri,
    required this.available,
  });
  final String uri;
  final bool available;
}

/// A book is the progress owner; chapters never become independent books.
class AudiobookRecord extends MediaRecord {
  const AudiobookRecord(
    super.id,
    super.title, {
    required this.author,
    required this.chapters,
  });
  final String author;
  final List<AudiobookChapter> chapters;
}

class AudiobookChapter {
  const AudiobookChapter({
    required this.id,
    required this.title,
    required this.order,
    required this.uri,
    required this.durationMs,
    this.startMs = 0,
    this.endMs,
  });
  final String id, title, uri;
  final int order, durationMs;
  final int startMs;
  final int? endMs;
}

class MusicRecord extends MediaRecord {
  const MusicRecord(
    super.id,
    super.title, {
    required this.albumId,
    required this.artistId,
    required this.disc,
    required this.track,
    required this.uri,
  });
  final String albumId, artistId, uri;
  final int disc, track;
}

sealed class MediaProgress {
  const MediaProgress(this.id);
  final MediaId id;
  Map<String, dynamic> toJson();
  factory MediaProgress.fromJson(Map<String, dynamic> json) {
    final id = MediaId.fromJson(Map<String, dynamic>.from(json['id']));
    return switch (id.kind) {
      MediaKind.video => VideoProgress(
        id,
        positionMs: json['positionMs'] ?? 0,
        durationMs: json['durationMs'] ?? 0,
        watched: json['watched'] == true,
      ),
      MediaKind.audiobook => AudiobookProgress(
        id,
        chapterId: json['chapterId'] ?? '',
        positionMs: json['positionMs'] ?? 0,
        finished: json['finished'] == true,
        bookmarks: (json['bookmarks'] as List? ?? [])
            .map(
              (v) => AudiobookBookmark.fromJson(Map<String, dynamic>.from(v)),
            )
            .toList(),
        sleep: json['sleep'] == null
            ? null
            : SleepTimer.fromJson(Map<String, dynamic>.from(json['sleep'])),
      ),
      MediaKind.music => MusicProgress(
        id,
        positionMs: json['positionMs'] ?? 0,
        playCount: json['playCount'] ?? 0,
        lastPlayedAt: json['lastPlayedAt'] ?? 0,
      ),
    };
  }
}

class VideoProgress extends MediaProgress {
  VideoProgress(
    super.id, {
    required this.positionMs,
    required this.durationMs,
    required this.watched,
  }) {
    if (id.kind != MediaKind.video || positionMs < 0 || durationMs < 0) {
      throw ArgumentError('Invalid video progress');
    }
  }
  final int positionMs, durationMs;
  final bool watched;
  @override
  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'positionMs': positionMs,
    'durationMs': durationMs,
    'watched': watched,
  };
}

class AudiobookBookmark {
  const AudiobookBookmark(this.chapterId, this.positionMs, this.label);
  final String chapterId, label;
  final int positionMs;
  Map<String, dynamic> toJson() => {
    'chapterId': chapterId,
    'positionMs': positionMs,
    'label': label,
  };
  factory AudiobookBookmark.fromJson(Map<String, dynamic> v) =>
      AudiobookBookmark(v['chapterId'], v['positionMs'], v['label']);
}

enum SleepTimerMode { deadline, endOfChapter }

class SleepTimer {
  SleepTimer(this.mode, {this.deadlineUtcMs}) {
    if (mode == SleepTimerMode.deadline && deadlineUtcMs == null) {
      throw ArgumentError('A deadline is required');
    }
  }
  final SleepTimerMode mode;
  final int? deadlineUtcMs;
  bool expiredAt(DateTime now) =>
      mode == SleepTimerMode.deadline &&
      now.millisecondsSinceEpoch >= deadlineUtcMs!;
  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'deadlineUtcMs': deadlineUtcMs,
  };
  factory SleepTimer.fromJson(Map<String, dynamic> v) => SleepTimer(
    SleepTimerMode.values.byName(v['mode']),
    deadlineUtcMs: v['deadlineUtcMs'],
  );
}

class AudiobookProgress extends MediaProgress {
  AudiobookProgress(
    super.id, {
    required this.chapterId,
    required this.positionMs,
    required this.finished,
    this.bookmarks = const [],
    this.sleep,
  }) {
    if (id.kind != MediaKind.audiobook || positionMs < 0) {
      throw ArgumentError('Invalid book progress');
    }
  }
  final String chapterId;
  final int positionMs;
  final bool finished;
  final List<AudiobookBookmark> bookmarks;
  final SleepTimer? sleep;
  @override
  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'chapterId': chapterId,
    'positionMs': positionMs,
    'finished': finished,
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    if (sleep != null) 'sleep': sleep!.toJson(),
  };
}

class MusicProgress extends MediaProgress {
  MusicProgress(
    super.id, {
    required this.positionMs,
    this.playCount = 0,
    this.lastPlayedAt = 0,
  }) {
    if (id.kind != MediaKind.music ||
        positionMs < 0 ||
        playCount < 0 ||
        lastPlayedAt < 0) {
      throw ArgumentError('Invalid music progress');
    }
  }
  final int positionMs, playCount, lastPlayedAt;
  @override
  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'positionMs': positionMs,
    'playCount': playCount,
    if (lastPlayedAt > 0) 'lastPlayedAt': lastPlayedAt,
  };
}

/// Providers declare support explicitly; unsupported media never falls back to video.
abstract interface class MediaMetadataProvider {
  String get providerId;
  Set<MediaKind> get supportedKinds;
  Future<List<Map<String, dynamic>>> search(MediaKind kind, String query);
}

abstract interface class MediaProgressStore {
  Future<MediaProgress?> read(MediaId id);
  Future<void> write(MediaProgress progress);
}

abstract interface class MediaQueueStore {
  Future<List<MediaId>> readQueue(MediaKind kind);
  Future<void> writeQueue(MediaKind kind, List<MediaId> items);
}

abstract interface class MediaPlaybackRouter {
  Set<MediaKind> get supportedKinds;
  Future<void> open(MediaRecord record);
}

/// Registration is explicit; an unsupported record cannot accidentally open the video player.
class PlaybackRegistry implements MediaPlaybackRouter {
  final Map<MediaKind, Future<void> Function(MediaRecord)> _routes = {};
  void register(MediaKind kind, Future<void> Function(MediaRecord) route) {
    if (_routes.containsKey(kind)) {
      throw StateError('Playback route already registered');
    }
    _routes[kind] = route;
  }

  @override
  Set<MediaKind> get supportedKinds => Set.unmodifiable(_routes.keys);
  @override
  Future<void> open(MediaRecord record) {
    final actual = switch (record) {
      VideoRecord() => MediaKind.video,
      AudiobookRecord() => MediaKind.audiobook,
      MusicRecord() => MediaKind.music,
    };
    if (record.id.kind != actual ||
        record.id.collectionId.isEmpty ||
        record.id.itemId.isEmpty) {
      throw ArgumentError('Invalid record identity');
    }
    final route = _routes[actual];
    if (route == null) {
      throw UnsupportedError('Playback for ${actual.name} is not enabled');
    }
    return route(record);
  }
}
