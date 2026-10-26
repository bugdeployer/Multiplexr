import '../../../media/audio_models.dart';
import '../../../media/audio_session.dart';
import '../../../media/contracts.dart';

class AudioImport {
  const AudioImport(this.files, this.errors);
  final List<AudioFile> files;
  final List<String> errors;
}

class AudioQueueItem {
  const AudioQueueItem({
    required this.id,
    required this.uri,
    required this.title,
    this.startMs = 0,
    this.endMs,
    this.owner,
    this.creator = '',
    this.artwork = '',
    this.album = '',
  });
  final String id, uri, title;
  final int startMs;
  final int? endMs;
  final MediaId? owner;
  final String creator, artwork, album;
  Map<String, dynamic> toJson() => {
    'id': id,
    'uri': uri,
    'title': title,
    'startMs': startMs,
    if (endMs != null) 'endMs': endMs,
    if (owner != null) 'owner': owner!.toJson(),
    if (owner != null) 'creator': creator,
    if (owner != null) 'artwork': artwork,
    if (owner != null) 'album': album,
  };
}

class AudioPlaybackRequest {
  const AudioPlaybackRequest({
    required this.id,
    required this.title,
    required this.creator,
    required this.files,
    this.index = 0,
    this.positionMs = 0,
    this.scopeCollectionId,
    this.repeat = AudioRepeatMode.off,
    this.canonicalEntryIds = const [],
    this.shuffled = false,
  });
  final MediaId id;
  final String title, creator;
  final List<AudioQueueItem> files;
  final int index, positionMs;
  final String? scopeCollectionId;
  final AudioRepeatMode repeat;
  final List<String> canonicalEntryIds;
  final bool shuffled;
  Map<String, dynamic> toJson() {
    if (id.kind == MediaKind.video ||
        files.isEmpty ||
        index < 0 ||
        index >= files.length ||
        positionMs < 0) {
      throw ArgumentError('Invalid audio playback request');
    }
    return {
      'id': id.toJson(),
      'title': title,
      'creator': creator,
      'index': index,
      'positionMs': positionMs,
      'files': files.map((f) => f.toJson()).toList(),
      if (id.kind == MediaKind.music)
        'scopeCollectionId': scopeCollectionId ?? '',
      if (id.kind == MediaKind.music) 'repeat': repeat.name,
      if (id.kind == MediaKind.music) 'canonicalEntryIds': canonicalEntryIds,
      if (id.kind == MediaKind.music) 'shuffled': shuffled,
    };
  }

  factory AudioPlaybackRequest.music(
    AudioSession session, {
    String? collectionId,
  }) {
    if (session.mode != AudioSessionMode.music ||
        (collectionId != null &&
            session.entries.any((e) => e.owner.collectionId != collectionId))) {
      throw ArgumentError('Music session scope mismatch.');
    }
    final byId = {for (final e in session.entries) e.entryId: e};
    final entries = session.traversal.map((id) => byId[id]!).toList();
    return AudioPlaybackRequest(
      id: session.current.owner,
      title: session.current.title,
      creator: session.current.creator,
      files: entries
          .map(
            (e) => AudioQueueItem(
              id: e.entryId,
              uri: e.uri,
              title: e.title,
              owner: e.owner,
              creator: e.creator,
              artwork: e.artwork,
              album: e.album,
            ),
          )
          .toList(),
      index: entries.indexWhere((e) => e.entryId == session.currentEntryId),
      positionMs: session.positionMs,
      scopeCollectionId: collectionId,
      repeat: session.repeat,
      canonicalEntryIds: session.entries.map((e) => e.entryId).toList(),
      shuffled: session.shuffled,
    );
  }

  factory AudioPlaybackRequest.audiobook(
    Audiobook book,
    AudiobookProgress? progress,
  ) {
    if (progress != null && progress.id != book.id) {
      throw ArgumentError('Progress belongs to another book');
    }
    final chapters = book.record.chapters;
    final found = chapters.indexWhere((c) => c.id == progress?.chapterId);
    final resume = progress != null && !progress.finished && found >= 0;
    return AudioPlaybackRequest(
      id: book.id,
      title: book.metadata.title,
      creator: book.metadata.author,
      files: [
        for (final c in chapters)
          AudioQueueItem(
            id: c.id,
            uri: c.uri,
            title: c.title,
            startMs: c.startMs,
            endMs: c.endMs,
          ),
      ],
      index: resume ? found : 0,
      positionMs: resume ? progress.positionMs : 0,
    );
  }
}

class AudioState {
  const AudioState([this.data = const {}]);
  final Map<String, dynamic> data;
  MediaId? get id => data['id'] == null
      ? null
      : MediaId.fromJson(Map<String, dynamic>.from(data['id']));
  int get index => data['index'] ?? 0;
  int get positionMs => data['positionMs'] ?? 0;
  int get durationMs => data['durationMs'] ?? 0;
  bool get playing => data['playing'] == true;
  bool get buffering => data['buffering'] == true;
  bool get finished => data['finished'] == true;
  double get rate => (data['rate'] as num? ?? 1).toDouble();
  int get deadline => data['deadline'] ?? 0;
  bool get endOfChapter => data['endOfChapter'] == true;
  String? get error => data['error'];
}
