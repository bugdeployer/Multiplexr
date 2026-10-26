import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../catalog/domain/catalog_models.dart';
import 'audio_models.dart';
import 'contracts.dart';

/// Source evidence supplied by discovery; identity does not depend on tags.
class MusicSource {
  MusicSource({
    required this.id,
    required this.rootId,
    required this.folderId,
    required this.folderName,
    required this.file,
    this.albumArtist = '',
    this.releaseId = '',
    this.year,
    this.cover = '',
  }) {
    if ([id, rootId, folderId].any((s) => s.trim().isEmpty)) {
      throw ArgumentError(
        'Music discovery needs stable source/root/folder IDs.',
      );
    }
  }
  final String id, rootId, folderId, folderName, albumArtist, releaseId, cover;
  final int? year;
  final AudioFile file;
}

class MusicTrack {
  MusicTrack({
    required this.id,
    required this.source,
    required this.rootId,
    required this.folderId,
    required this.metadata,
    this.albumId,
    this.available = true,
    Map<String, Object?> overrides = const {},
  }) : overrides = Map.unmodifiable(overrides) {
    if (id.kind != MediaKind.music ||
        id.collectionId.isEmpty ||
        id.itemId.isEmpty ||
        rootId.isEmpty ||
        folderId.isEmpty ||
        source.id.isEmpty ||
        source.uri.isEmpty ||
        metadata.title.trim().isEmpty ||
        metadata.disc < 0 ||
        metadata.track < 0 ||
        metadata.durationMs < 0 ||
        (metadata.year != null && metadata.year! < 0) ||
        source.disc < 0 ||
        source.track < 0 ||
        source.durationMs < 0 ||
        !this.overrides.keys.every(correctableFields.contains)) {
      throw ArgumentError('Invalid Music track.');
    }
  }
  static const correctableFields = {
    'title',
    'artist',
    'album',
    'albumArtist',
    'genre',
    'year',
    'disc',
    'track',
    'cover',
    'coverSource',
    'albumId',
  };
  final MediaId id;
  final AudioFile source;
  final String rootId, folderId;
  final String? albumId;
  final MusicMetadata metadata;
  final bool available;
  final Map<String, Object?> overrides;

  CatalogTitle<MusicMetadata> get catalogTitle => CatalogTitle(
    id: CatalogIdentity(id.collectionId, id.itemId, CatalogEntityKind.title),
    subtype: MediaSubtype.music,
    title: metadata.title,
    metadata: metadata,
    sources: [
      CatalogSource(
        id: source.id,
        uri: source.uri,
        name: source.filename,
        rootUri: rootId,
        available: available,
      ),
    ],
  );

  MusicTrack corrected(Map<String, Object?> values) {
    final next = {...overrides, ...values};
    if (!next.keys.every(correctableFields.contains)) {
      throw ArgumentError('Unsupported Music correction.');
    }
    final data = {...metadata.toJson(), ...next}..remove('albumId');
    return MusicTrack(
      id: id,
      source: source,
      rootId: rootId,
      folderId: folderId,
      metadata: MusicMetadata.fromJson(data),
      albumId: next.containsKey('albumId')
          ? next['albumId'] as String?
          : albumId,
      overrides: next,
      available: available,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'source': source.toJson(),
    'rootId': rootId,
    'folderId': folderId,
    'albumId': albumId,
    'metadata': metadata.toJson(),
    'available': available,
    'overrides': overrides,
  };
  factory MusicTrack.fromJson(Map<String, dynamic> v) => MusicTrack(
    id: MediaId.fromJson(Map<String, dynamic>.from(v['id'])),
    source: AudioFile.fromJson(Map<String, dynamic>.from(v['source'])),
    rootId: v['rootId'],
    folderId: v['folderId'],
    albumId: v['albumId'],
    metadata: MusicMetadata.fromJson(Map<String, dynamic>.from(v['metadata'])),
    available: v['available'] == true,
    overrides: Map<String, Object?>.from(v['overrides'] ?? {}),
  );
}

class MusicCatalog {
  MusicCatalog(Iterable<MusicTrack> tracks)
    : tracks = List.unmodifiable(tracks) {
    if (this.tracks.map((t) => t.id).toSet().length != this.tracks.length ||
        this.tracks
                .map((t) => (t.id.collectionId, t.source.id))
                .toSet()
                .length !=
            this.tracks.length) {
      throw ArgumentError('Duplicate Music identity or source.');
    }
  }
  final List<MusicTrack> tracks;
  Map<String, dynamic> toJson() {
    final artwork = <String, String>{};
    String reference(String cover) {
      if (!cover.startsWith('data:image/')) return cover;
      final key = sha256.convert(utf8.encode(cover)).toString();
      artwork[key] = cover;
      return 'artwork:$key';
    }

    final values = [for (final track in tracks) track.toJson()];
    for (final value in values) {
      for (final field in ['metadata', 'overrides']) {
        final data = Map<String, dynamic>.from(value[field]);
        if (data['cover'] is String) data['cover'] = reference(data['cover']);
        value[field] = data;
      }
    }
    return {
      'version': 1,
      'tracks': values,
      if (artwork.isNotEmpty) 'artwork': artwork,
    };
  }

  factory MusicCatalog.fromJson(Map<String, dynamic> v) {
    if (v['version'] != 1) {
      throw const FormatException('Unsupported Music catalog version.');
    }
    final artwork = Map<String, dynamic>.from(v['artwork'] ?? {});
    return MusicCatalog(
      (v['tracks'] as List).map((raw) {
        final value = Map<String, dynamic>.from(raw);
        for (final field in ['metadata', 'overrides']) {
          final data = Map<String, dynamic>.from(value[field] ?? {});
          final cover = data['cover'];
          if (cover is String && cover.startsWith('artwork:')) {
            final image = artwork[cover.substring(8)];
            if (image is! String) {
              throw const FormatException('Missing catalog artwork.');
            }
            data['cover'] = image;
          }
          value[field] = data;
        }
        return MusicTrack.fromJson(value);
      }),
    );
  }
}

String _stableMusicId(List<String> parts) =>
    sha256.convert(utf8.encode(jsonEncode(parts))).toString();

String _tagAlbumKey(MusicSource source) => jsonEncode([
  source.rootId,
  source.file.album.trim().toLowerCase(),
  (source.albumArtist.trim().isNotEmpty
          ? source.albumArtist
          : source.file.artist)
      .trim()
      .toLowerCase(),
  source.releaseId,
  source.year,
]);

Set<String> _ambiguousAlbums(Iterable<MusicSource> sources) {
  final groups = <String, List<MusicSource>>{};
  for (final source in sources) {
    if (source.file.album.trim().isEmpty || source.releaseId.isNotEmpty) {
      continue;
    }
    groups.putIfAbsent(_tagAlbumKey(source), () => []).add(source);
  }
  return {
    for (final group in groups.entries)
      if (group.value.map((e) => e.folderId).toSet().length > 1 &&
          (group.value.any((e) => e.file.disc == 0) ||
              group.value.any(
                (e) => group.value.any(
                  (other) =>
                      e.folderId != other.folderId &&
                      e.file.disc == other.file.disc,
                ),
              )))
        group.key,
  };
}

List<String> musicGroupingWarnings(Iterable<MusicSource> sources) {
  final ambiguous = _ambiguousAlbums(sources);
  final names = {
    for (final source in sources)
      if (ambiguous.contains(_tagAlbumKey(source))) source.file.album.trim(),
  };
  return [
    for (final name in names)
      '$name: kept separate folders because disc or edition tags are ambiguous. Review album grouping.',
  ];
}

/// Reconcile only after discovery succeeds for all roots. A failed scan must
/// never call this with a partial result. Missing sources remain repairable.
MusicCatalog reconcileMusic({
  required MusicCatalog previous,
  required String collectionId,
  required Iterable<MusicSource> discovered,
}) {
  if (collectionId.trim().isEmpty) throw ArgumentError('Missing collection.');
  final old = {
    for (final t in previous.tracks.where(
      (t) => t.id.collectionId == collectionId,
    ))
      t.source.id: t,
  };
  final found = <String, MusicSource>{};
  for (final source in discovered) {
    if (found.containsKey(source.id) &&
        found[source.id]!.file.uri != source.file.uri) {
      throw ArgumentError('Conflicting Music source identity.');
    }
    found[source.id] = source;
  }
  // Only reconnect a unique, strong source match across replaced roots.
  // Existing roots never auto-merge copies; ambiguous candidates stay separate.
  String evidenceKey(
    String filename,
    int duration,
    String album,
    String artist,
    int disc,
    int track,
  ) => duration <= 0 || album.trim().isEmpty || artist.trim().isEmpty
      ? ''
      : jsonEncode([
          filename.toLowerCase(),
          duration,
          album.trim().toLowerCase(),
          artist.trim().toLowerCase(),
          disc,
          track,
        ]);
  final roots = found.values.map((s) => s.rootId).toSet();
  final oldRoots = old.values.map((t) => t.rootId).toSet();
  final aliases = <String, MusicTrack>{};
  final missing = old.values.where(
    (t) => !found.containsKey(t.source.id) && !roots.contains(t.rootId),
  );
  final newSources = found.values.where(
    (s) => !old.containsKey(s.id) && !oldRoots.contains(s.rootId),
  );
  for (final source in newSources) {
    final key = evidenceKey(
      source.file.filename,
      source.file.durationMs,
      source.file.album,
      source.file.artist,
      source.file.disc,
      source.file.track,
    );
    if (key.isEmpty) continue;
    final matches = missing
        .where(
          (t) =>
              evidenceKey(
                t.source.filename,
                t.source.durationMs,
                t.source.album,
                t.source.artist,
                t.source.disc,
                t.source.track,
              ) ==
              key,
        )
        .toList();
    final fresh = newSources
        .where(
          (s) =>
              evidenceKey(
                s.file.filename,
                s.file.durationMs,
                s.file.album,
                s.file.artist,
                s.file.disc,
                s.file.track,
              ) ==
              key,
        )
        .length;
    if (matches.length == 1 && fresh == 1) aliases[source.id] = matches.single;
  }
  final reconnected = aliases.values.map((t) => t.source.id).toSet();
  final next = <MusicTrack>[];
  final ambiguous = _ambiguousAlbums(found.values);
  for (final evidence in found.values) {
    final file = evidence.file;
    final before = old[evidence.id] ?? aliases[evidence.id];
    final album = file.album.trim();
    final artist = evidence.albumArtist.trim().isNotEmpty
        ? evidence.albumArtist.trim()
        : file.artist.trim();
    // Folder fallback must not invent an album for files directly in a root.
    final fallback = evidence.folderId != evidence.rootId;
    final albumName = album.isNotEmpty
        ? album
        : fallback
        ? evidence.folderName
        : '';
    final albumId = albumName.isEmpty
        ? null
        : _stableMusicId([
            collectionId,
            evidence.rootId,
            if (album.isEmpty ||
                artist.isEmpty ||
                ambiguous.contains(_tagAlbumKey(evidence)))
              evidence.folderId,
            artist.toLowerCase(),
            albumName.toLowerCase(),
            evidence.releaseId,
            '${evidence.year ?? ''}',
          ]);
    final metadata = MusicMetadata(
      title: file.displayTitle,
      artist: file.artist,
      album: albumName,
      albumArtist: evidence.albumArtist,
      genre: file.genre,
      year: evidence.year,
      disc: file.disc,
      track: file.track,
      durationMs: file.durationMs,
      cover: evidence.cover,
      coverSource: evidence.cover.isEmpty ? '' : 'embedded-or-folder',
      releaseId: evidence.releaseId,
    );
    // Online enrichment remains until explicitly edited/refreshed; discovery
    // refreshes source evidence without replacing reviewed metadata.
    final chosen = before?.metadata.metadataSource.isNotEmpty == true
        ? before!.metadata
        : metadata;
    final value = MusicTrack(
      id:
          before?.id ??
          MediaId(
            MediaKind.music,
            collectionId,
            _stableMusicId([collectionId, evidence.id]),
          ),
      source: file,
      rootId: evidence.rootId,
      folderId: evidence.folderId,
      metadata: chosen,
      albumId: before?.albumId ?? albumId,
    );
    next.add(before == null ? value : value.corrected(before.overrides));
  }
  for (final missing in old.values.where(
    (t) =>
        !found.containsKey(t.source.id) && !reconnected.contains(t.source.id),
  )) {
    next.add(
      MusicTrack(
        id: missing.id,
        source: missing.source,
        rootId: missing.rootId,
        folderId: missing.folderId,
        metadata: missing.metadata,
        albumId: missing.albumId,
        overrides: missing.overrides,
        available: false,
      ),
    );
  }
  return MusicCatalog([
    ...previous.tracks.where((t) => t.id.collectionId != collectionId),
    ...next,
  ]);
}

List<MusicTrack> orderedMusicTracks(Iterable<MusicTrack> tracks) =>
    [...tracks]..sort((a, b) {
      final disc = (a.metadata.disc == 0 ? 1 : a.metadata.disc).compareTo(
        b.metadata.disc == 0 ? 1 : b.metadata.disc,
      );
      if (disc != 0) return disc;
      final track = (a.metadata.track == 0 ? 1 << 30 : a.metadata.track)
          .compareTo(b.metadata.track == 0 ? 1 << 30 : b.metadata.track);
      if (track != 0) return track;
      final name = naturalAudioOrder(a.source.filename, b.source.filename);
      return name != 0 ? name : a.id.itemId.compareTo(b.id.itemId);
    });
