import 'contracts.dart';

/// Embedded file tags are source evidence, not curated book or music metadata.
class AudioFile {
  const AudioFile({
    String? id,
    required this.uri,
    required this.filename,
    this.title = '',
    this.album = '',
    this.artist = '',
    this.author = '',
    this.genre = '',
    this.durationMs = 0,
    this.disc = 0,
    this.track = 0,
  }) : id = id ?? uri;
  final String id, uri, filename, title, album, artist, author, genre;
  final int durationMs, disc, track;
  factory AudioFile.fromJson(Map<String, dynamic> v) => AudioFile(
    id: v['id'],
    uri: v['uri'],
    filename: v['filename'],
    title: v['title'] ?? '',
    album: v['album'] ?? '',
    artist: v['artist'] ?? '',
    author: v['author'] ?? '',
    genre: v['genre'] ?? '',
    durationMs: v['durationMs'] ?? 0,
    disc: v['disc'] ?? 0,
    track: v['track'] ?? 0,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'uri': uri,
    'filename': filename,
    'title': title,
    'album': album,
    'artist': artist,
    'author': author,
    'genre': genre,
    'durationMs': durationMs,
    'disc': disc,
    'track': track,
  };
  String get displayTitle => title.trim().isNotEmpty
      ? title
      : filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
}

class AudiobookMetadata {
  const AudiobookMetadata({
    required this.title,
    this.author = '',
    this.narrator = '',
    this.series = '',
    this.description = '',
    this.language = '',
    this.seriesId = '',
    this.seriesOrder = 0,
    this.cover = '',
    this.coverSource = '',
    this.providerId = '',
    this.metadataSource = '',
    this.publisher = '',
    this.publicationDate = '',
    this.tags = const [],
  });
  final String title,
      author,
      narrator,
      series,
      description,
      language,
      seriesId,
      cover,
      coverSource,
      providerId,
      metadataSource,
      publisher,
      publicationDate;
  final double seriesOrder;
  final List<String> tags;
  factory AudiobookMetadata.fromJson(Map<String, dynamic> v) =>
      AudiobookMetadata(
        title: v['title'],
        author: v['author'] ?? '',
        narrator: v['narrator'] ?? '',
        series: v['series'] ?? '',
        description: v['description'] ?? '',
        language: v['language'] ?? '',
        seriesId: v['seriesId'] ?? '',
        seriesOrder: (v['seriesOrder'] as num? ?? 0).toDouble(),
        cover: v['cover'] ?? '',
        coverSource: v['coverSource'] ?? '',
        providerId: v['providerId'] ?? '',
        metadataSource: v['metadataSource'] ?? '',
        publisher: v['publisher'] ?? '',
        publicationDate: v['publicationDate'] ?? '',
        tags: List<String>.from(v['tags'] ?? []),
      );
  Map<String, dynamic> toJson() => {
    'title': title,
    'author': author,
    'narrator': narrator,
    'series': series,
    'description': description,
    'language': language,
    'seriesId': seriesId,
    'seriesOrder': seriesOrder,
    'cover': cover,
    'coverSource': coverSource,
    'providerId': providerId,
    'metadataSource': metadataSource,
    'publisher': publisher,
    'publicationDate': publicationDate,
    'tags': tags,
  };
}

/// Music identity never reuses author/narrator or book-series fields.
class MusicMetadata {
  const MusicMetadata({
    required this.title,
    required this.artist,
    required this.album,
    this.albumArtist = '',
    this.genre = '',
    this.year,
    this.disc = 0,
    this.track = 0,
    this.durationMs = 0,
    this.cover = '',
    this.coverSource = '',
    this.recordingId = '',
    this.releaseId = '',
    this.releaseGroupId = '',
    this.metadataSource = '',
  });
  final String title, artist, album, albumArtist, genre;
  final int? year;
  final int disc, track, durationMs;
  final String cover,
      coverSource,
      recordingId,
      releaseId,
      releaseGroupId,
      metadataSource;
  factory MusicMetadata.fromJson(Map<String, dynamic> v) => MusicMetadata(
    title: v['title'],
    artist: v['artist'],
    album: v['album'],
    albumArtist: v['albumArtist'] ?? '',
    genre: v['genre'] ?? '',
    year: v['year'],
    disc: v['disc'] ?? 0,
    track: v['track'] ?? 0,
    durationMs: v['durationMs'] ?? 0,
    cover: v['cover'] ?? '',
    coverSource: v['coverSource'] ?? '',
    recordingId: v['recordingId'] ?? '',
    releaseId: v['releaseId'] ?? '',
    releaseGroupId: v['releaseGroupId'] ?? '',
    metadataSource: v['metadataSource'] ?? '',
  );
  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'album': album,
    'albumArtist': albumArtist,
    'genre': genre,
    if (year != null) 'year': year,
    'disc': disc,
    'track': track,
    'durationMs': durationMs,
    'cover': cover,
    'coverSource': coverSource,
    'recordingId': recordingId,
    'releaseId': releaseId,
    'releaseGroupId': releaseGroupId,
    'metadataSource': metadataSource,
  };
}

class AudiobookSeriesMetadata {
  const AudiobookSeriesMetadata({
    required this.id,
    required this.collectionId,
    required this.title,
    this.author = '',
    this.description = '',
    this.cover = '',
  });
  final String id, collectionId, title, author, description, cover;
  factory AudiobookSeriesMetadata.fromJson(Map<String, dynamic> value) =>
      AudiobookSeriesMetadata(
        id: value['id'],
        collectionId: value['collectionId'],
        title: value['title'],
        author: value['author'] ?? '',
        description: value['description'] ?? '',
        cover: value['cover'] ?? '',
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'title': title,
    'author': author,
    'description': description,
    'cover': cover,
  };
}

int naturalAudioOrder(String left, String right) {
  final tokens = RegExp(r'\d+|\D+');
  final a = tokens.allMatches(left.toLowerCase()).map((m) => m[0]!).toList();
  final b = tokens.allMatches(right.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final x = int.tryParse(a[i]), y = int.tryParse(b[i]);
    final compared = x != null && y != null
        ? x.compareTo(y)
        : a[i].compareTo(b[i]);
    if (compared != 0) return compared;
  }
  return a.length.compareTo(b.length);
}

List<AudioFile> orderedAudioFiles(Iterable<AudioFile> files) {
  final values = {for (final f in files) f.uri: f}.values.toList();
  values.sort((a, b) {
    final disc = (a.disc == 0 ? 1 : a.disc).compareTo(b.disc == 0 ? 1 : b.disc);
    if (disc != 0) return disc;
    final knownTrack = (a.track == 0 ? 1 : 0).compareTo(b.track == 0 ? 1 : 0);
    if (knownTrack != 0) return knownTrack;
    if (a.track > 0 && b.track > 0) {
      final track = a.track.compareTo(b.track);
      if (track != 0) return track;
    }
    return naturalAudioOrder(a.filename, b.filename);
  });
  return values;
}

/// A logical chapter is a range within a source file, not necessarily a file.
class AudiobookChapterMarker {
  const AudiobookChapterMarker({
    required this.id,
    required this.fileId,
    required this.title,
    this.startMs = 0,
    this.endMs,
  });
  final String id, fileId, title;
  final int startMs;
  final int? endMs;
  factory AudiobookChapterMarker.fromJson(Map<String, dynamic> v) =>
      AudiobookChapterMarker(
        id: v['id'],
        fileId: v['fileId'],
        title: v['title'],
        startMs: v['startMs'] ?? 0,
        endMs: v['endMs'],
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'fileId': fileId,
    'title': title,
    'startMs': startMs,
    if (endMs != null) 'endMs': endMs,
  };
}

class Audiobook {
  Audiobook({
    required this.id,
    required this.metadata,
    required List<AudioFile> files,
    List<AudiobookChapterMarker>? chapters,
  }) : files = List.unmodifiable(files),
       chapterMarkers = List.unmodifiable(
         chapters ??
             [
               for (final file in files)
                 AudiobookChapterMarker(
                   id: file.id,
                   fileId: file.id,
                   title: file.displayTitle,
                   endMs: file.durationMs > 0 ? file.durationMs : null,
                 ),
             ],
       ) {
    if (id.kind != MediaKind.audiobook ||
        id.collectionId.isEmpty ||
        id.itemId.isEmpty ||
        metadata.title.trim().isEmpty ||
        files.isEmpty ||
        files.length > 1000 ||
        files.any(
          (f) =>
              f.id.isEmpty ||
              !f.uri.startsWith('content://') ||
              f.durationMs < 0 ||
              f.disc < 0 ||
              f.track < 0,
        ) ||
        files.map((f) => f.id).toSet().length != files.length ||
        files.map((f) => f.uri).toSet().length != files.length) {
      throw ArgumentError('Invalid audiobook');
    }
    if (chapterMarkers.isEmpty ||
        chapterMarkers.length > 1000 ||
        chapterMarkers.map((c) => c.id).toSet().length !=
            chapterMarkers.length) {
      throw ArgumentError('A book needs unique chapter identities');
    }
    final previousEnds = <String, int?>{};
    final chronological = [...chapterMarkers]
      ..sort((a, b) {
        final file = a.fileId.compareTo(b.fileId);
        return file != 0 ? file : a.startMs.compareTo(b.startMs);
      });
    for (final c in chronological) {
      final file = files.where((f) => f.id == c.fileId).firstOrNull;
      if (file == null ||
          c.id.isEmpty ||
          c.title.trim().isEmpty ||
          c.startMs < 0 ||
          (c.endMs != null && c.endMs! <= c.startMs) ||
          (file.durationMs > 0 &&
              (c.startMs >= file.durationMs ||
                  (c.endMs ?? file.durationMs) > file.durationMs)) ||
          (previousEnds.containsKey(c.fileId) &&
              (previousEnds[c.fileId] == null ||
                  c.startMs < previousEnds[c.fileId]!))) {
        throw ArgumentError('Invalid or overlapping chapter range');
      }
      previousEnds[c.fileId] = c.endMs;
    }
  }
  Audiobook withMetadata(Map<String, dynamic> changes) => Audiobook(
    id: id,
    metadata: AudiobookMetadata.fromJson({...metadata.toJson(), ...changes}),
    files: files,
    chapters: chapterMarkers,
  );
  final MediaId id;
  final AudiobookMetadata metadata;
  final List<AudioFile> files;
  final List<AudiobookChapterMarker> chapterMarkers;
  int get durationMs => record.chapters.fold(0, (sum, c) => sum + c.durationMs);
  AudiobookRecord get record => AudiobookRecord(
    id,
    metadata.title,
    author: metadata.author,
    chapters: [
      for (var i = 0; i < chapterMarkers.length; i++)
        AudiobookChapter(
          id: chapterMarkers[i].id,
          title: chapterMarkers[i].title,
          order: i,
          uri: files.firstWhere((f) => f.id == chapterMarkers[i].fileId).uri,
          startMs: chapterMarkers[i].startMs,
          endMs: chapterMarkers[i].endMs,
          durationMs:
              ((chapterMarkers[i].endMs ??
                          files
                              .firstWhere(
                                (f) => f.id == chapterMarkers[i].fileId,
                              )
                              .durationMs) -
                      chapterMarkers[i].startMs)
                  .clamp(0, 1 << 53),
        ),
    ],
  );
  factory Audiobook.fromJson(Map<String, dynamic> v) => Audiobook(
    id: MediaId.fromJson(Map<String, dynamic>.from(v['id'])),
    metadata: AudiobookMetadata.fromJson(
      Map<String, dynamic>.from(v['metadata']),
    ),
    files: (v['files'] as List)
        .map((f) => AudioFile.fromJson(Map<String, dynamic>.from(f)))
        .toList(),
    chapters: (v['chapters'] as List?)
        ?.map(
          (c) => AudiobookChapterMarker.fromJson(Map<String, dynamic>.from(c)),
        )
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'metadata': metadata.toJson(),
    'files': files.map((f) => f.toJson()).toList(),
    'chapters': chapterMarkers.map((c) => c.toJson()).toList(),
  };
}
