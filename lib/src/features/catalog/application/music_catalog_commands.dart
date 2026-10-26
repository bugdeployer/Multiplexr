import 'dart:convert';
import 'dart:math';

import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/playlist.dart';
import '../../../library/library_models.dart';
import '../../../media/contracts.dart';
import '../../../media/audio_models.dart';
import '../../../media/music_catalog_models.dart';
import '../../../media/video_projections.dart';
import 'space_queries.dart';
import 'music_catalog_ports.dart';

class MusicAlbum {
  MusicAlbum(
    this.id,
    Iterable<MusicTrack> tracks,
    Map<String, dynamic> overrides,
  ) : tracks = List.unmodifiable(orderedMusicTracks(tracks)),
      overrides = Map.unmodifiable(overrides);
  final CatalogIdentity id;
  final List<MusicTrack> tracks;
  final Map<String, dynamic> overrides;
  String get key => jsonEncode([id.collectionId, id.entityId]);
  String get title => overrides['title'] ?? tracks.first.metadata.album;
  String get artist =>
      overrides['artist'] ??
      (tracks.first.metadata.albumArtist.isEmpty
          ? tracks.first.metadata.artist
          : tracks.first.metadata.albumArtist);
  String get cover =>
      overrides['cover'] ??
      tracks
          .map((t) => t.metadata.cover)
          .where((s) => s.isNotEmpty)
          .firstOrNull ??
      '';
  int? get year => overrides['year'] ?? tracks.first.metadata.year;
}

class MusicOverview {
  MusicOverview(this.tracks, this.extras, this.history, this.albums);
  final List<MusicTrack> tracks;
  final Map<String, dynamic> extras;
  final Map<MediaId, int> history;
  final List<MusicAlbum> albums;
}

List<MusicAlbum> orderedMusicAlbums(
  List<MusicAlbum> albums,
  Map<String, dynamic> extras,
  Map<MediaId, int> history,
  String source,
) {
  int score(MusicAlbum album) => album.tracks
      .map(
        (t) => source == 'progress'
            ? history[t.id] ?? 0
            : ((extras['titles'] as Map?)?[t.id.key]?['addedAt'] as num?)
                      ?.toInt() ??
                  0,
      )
      .fold(0, (a, b) => a > b ? a : b);
  return [...albums]..sort((a, b) => score(b).compareTo(score(a)));
}

class MusicCatalogCommands {
  MusicCatalogCommands(
    this.store, {
    required this.collections,
    required this.authorized,
  });
  final MusicCatalogStore store;
  final List<VideoCollection> Function() collections;
  final bool Function(String) authorized;
  bool access(String id) =>
      collections().any((c) => c.id == id && c.kind == MediaKind.music) &&
      authorized(id);
  Future<Map<String, dynamic>> extras() async {
    final data = await store.readExtras();
    if (data != null && data['version'] != 1) {
      throw const FormatException('Unsupported Music settings.');
    }
    return data ??
        {
          'version': 1,
          'titles': <String, dynamic>{},
          'albums': <String, dynamic>{},
          'playlists': [],
        };
  }

  Future<List<MusicTrack>> tracks(SpaceScope scope) async {
    final data = await extras();
    return (await store.readCatalog()).tracks
        .where((track) {
          final owner = collections()
              .where((c) => c.id == track.id.collectionId)
              .firstOrNull;
          return owner != null &&
              scope.includes(
                owner.catalogCollection,
                authorized: access(owner.id),
              );
        })
        .map((track) {
          final cover =
              track.overrides['cover'] ??
              (data['albums'] as Map?)?[jsonEncode([
                track.id.collectionId,
                track.albumId,
              ])]?['cover'] ??
              track.metadata.cover;
          return MusicTrack(
            id: track.id,
            source: track.source,
            rootId: track.rootId,
            folderId: track.folderId,
            albumId: track.albumId,
            available: track.available,
            overrides: track.overrides,
            metadata: MusicMetadata.fromJson({
              ...track.metadata.toJson(),
              'cover': cover,
              'album':
                  track.overrides['album'] ??
                  (data['albums'] as Map?)?[jsonEncode([
                    track.id.collectionId,
                    track.albumId,
                  ])]?['title'] ??
                  track.metadata.album,
              'albumArtist':
                  track.overrides['albumArtist'] ??
                  (data['albums'] as Map?)?[jsonEncode([
                    track.id.collectionId,
                    track.albumId,
                  ])]?['artist'] ??
                  track.metadata.albumArtist,
            }),
          );
        })
        .toList();
  }

  Future<MusicOverview> overview(SpaceScope scope) async {
    final values = await tracks(scope);
    final data = await extras();
    final times = await store.history(values.map((t) => t.id).toList());
    // Authorization may change while the state reads are in flight.
    final eligible = values.where((t) {
      final owner = collections()
          .where((c) => c.id == t.id.collectionId)
          .firstOrNull;
      return owner != null &&
          scope.includes(owner.catalogCollection, authorized: access(owner.id));
    }).toList();
    return MusicOverview(eligible, data, times, albums(eligible, data));
  }

  List<MusicAlbum> albums(
    List<MusicTrack> tracks,
    Map<String, dynamic> extras,
  ) {
    final groups = <String, List<MusicTrack>>{};
    for (final track in tracks.where((t) => t.albumId != null)) {
      groups
          .putIfAbsent(
            jsonEncode([track.id.collectionId, track.albumId]),
            () => [],
          )
          .add(track);
    }
    return [
      for (final group in groups.entries)
        MusicAlbum(
          CatalogIdentity(
            group.value.first.id.collectionId,
            group.value.first.albumId!,
            CatalogEntityKind.group,
          ),
          group.value,
          Map<String, dynamic>.from(
            (extras['albums'] as Map?)?[group.key] ?? {},
          ),
        ),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Map<String, dynamic> flags(Map<String, dynamic> extras, MediaId id) =>
      Map<String, dynamic>.from((extras['titles'] as Map?)?[id.key] ?? {});
  Future<void> reconnect(MusicTrack missing, MusicTrack replacement) async {
    if (missing.available ||
        !replacement.available ||
        missing.id.collectionId != replacement.id.collectionId ||
        !access(missing.id.collectionId)) {
      throw StateError('Choose an available track from this collection.');
    }
    await store.reconnect(
      missing,
      replacement,
      checkAccess: () {
        if (!access(missing.id.collectionId)) {
          throw StateError('Collection access required.');
        }
      },
    );
  }

  Future<void> patchTrack(MediaId id, MusicTrack Function(MusicTrack) change) =>
      store.updateCatalog(
        collectionId: id.collectionId,
        authorized: access,
        change: (current) {
          if (!current.tracks.any((t) => t.id == id)) {
            throw StateError('Track no longer exists.');
          }
          return MusicCatalog([
            for (final track in current.tracks)
              track.id == id ? change(track) : track,
          ]);
        },
      );
  Future<void> _extrasChange(
    String? collectionId,
    void Function(Map<String, dynamic>) change,
  ) => store.updateExtras((value) async {
    if (collectionId != null && !access(collectionId)) {
      throw StateError('Collection access required.');
    }
    final data =
        value ??
        {
          'version': 1,
          'titles': <String, dynamic>{},
          'albums': <String, dynamic>{},
          'playlists': [],
        };
    if (data['version'] != 1) {
      throw const FormatException('Unsupported Music settings.');
    }
    change(data);
    if (collectionId != null && !access(collectionId)) {
      throw StateError('Collection access required.');
    }
    return data;
  });
  Future<void> setFlags(MediaId id, Map<String, dynamic> patch) =>
      _extrasChange(id.collectionId, (data) {
        final titles = Map<String, dynamic>.from(data['titles'] ?? {});
        titles[id.key] = {...?titles[id.key] as Map?, ...patch};
        data['titles'] = titles;
      });
  Future<Map<MediaId, List<String>>> changeTags(
    List<MediaId> ids,
    String operation,
    List<String> tags,
  ) async {
    final before = <MediaId, List<String>>{};
    await _extrasChange(null, (data) {
      final titles = Map<String, dynamic>.from(data['titles'] ?? {});
      for (final id in ids) {
        if (!access(id.collectionId)) {
          throw StateError('Collection access required.');
        }
        final flags = Map<String, dynamic>.from(titles[id.key] ?? {});
        final current = List<String>.from(flags['tags'] ?? []);
        before[id] = current;
        final removed = tags.map((t) => t.toLowerCase()).toSet();
        final next = operation == 'replace'
            ? tags
            : operation == 'remove'
            ? current.where((t) => !removed.contains(t.toLowerCase())).toList()
            : [...current, ...tags];
        final seen = <String>{};
        flags['tags'] = next.where((t) => seen.add(t.toLowerCase())).toList();
        titles[id.key] = flags;
      }
      data['titles'] = titles;
    });
    return before;
  }

  Future<Map<MediaId, List<String>>> renameTag(
    List<MediaId> ids,
    String oldTag,
    String newTag,
  ) async {
    final before = <MediaId, List<String>>{};
    await _extrasChange(null, (data) {
      final titles = Map<String, dynamic>.from(data['titles'] ?? {});
      for (final id in ids) {
        if (!access(id.collectionId)) {
          throw StateError('Collection access required.');
        }
        final flags = Map<String, dynamic>.from(titles[id.key] ?? {});
        final tags = List<String>.from(flags['tags'] ?? []);
        before[id] = tags;
        final seen = <String>{};
        flags['tags'] = [
          for (final t in tags)
            t.toLowerCase() == oldTag.toLowerCase() ? newTag : t,
        ].where((t) => seen.add(t.toLowerCase())).toList();
        titles[id.key] = flags;
      }
      data['titles'] = titles;
    });
    return before;
  }

  Future<void> restoreTags(Map<MediaId, List<String>> before) =>
      _extrasChange(null, (data) {
        final titles = Map<String, dynamic>.from(data['titles'] ?? {});
        for (final e in before.entries) {
          if (!access(e.key.collectionId)) {
            throw StateError('Collection access required.');
          }
          titles[e.key.key] = {...?titles[e.key.key] as Map?, 'tags': e.value};
        }
        data['titles'] = titles;
      });
  Future<void> setAlbum(MusicAlbum album, Map<String, dynamic> patch) =>
      _extrasChange(album.id.collectionId, (data) {
        final albums = Map<String, dynamic>.from(data['albums'] ?? {});
        final previous = Map<String, dynamic>.from(albums[album.key] ?? {});
        final manual = Set<String>.from(
          previous['manualFields'] ??
              (previous['metadataSource'] == 'manual'
                  ? previous.keys.where(
                      (k) => {'title', 'artist', 'year'}.contains(k),
                    )
                  : <String>[]),
        );
        if (patch['metadataSource'] == 'manual') {
          manual.addAll(
            patch.keys.where((k) => {'title', 'artist', 'year'}.contains(k)),
          );
        } else if (patch.containsKey('metadataSource')) {
          manual.removeAll(patch.keys);
        }
        albums[album.key] = {
          ...previous,
          ...patch,
          'manualFields': manual.toList(),
        };
        data['albums'] = albums;
      });
  Future<List<MusicPlaylist>> playlists(String? collectionId) async =>
      ((await extras())['playlists'] as List)
          .map((v) => MusicPlaylist.fromJson(Map<String, dynamic>.from(v)))
          .where((p) => p.scope.collectionId == collectionId)
          .toList();
  Future<void> savePlaylist(MusicPlaylist playlist) async {
    final known = (await store.readCatalog()).tracks;
    final previous = (await playlists(playlist.scope.collectionId))
        .where((p) => p.id == playlist.id)
        .firstOrNull;
    final oldEntries = {
      for (final e in previous?.entries ?? <PlaylistEntry>[]) e.id: e.track,
    };
    final scope = SpaceScope(
      MediaSubtype.music,
      collectionId: playlist.scope.collectionId,
    );
    final eligible = (await tracks(scope))
        .where((t) => t.available)
        .map((t) => t.catalogTitle.id)
        .toSet();
    for (final entry in playlist.entries) {
      if (oldEntries[entry.id] != entry.track &&
          !eligible.contains(entry.track)) {
        throw StateError('A playlist entry is not eligible.');
      }
      if (!known.any((t) => t.catalogTitle.id == entry.track)) {
        throw StateError('Track no longer exists.');
      }
    }
    await _extrasChange(playlist.scope.collectionId, (data) {
      // Authorization can change while waiting for the state mutation lock.
      for (final entry in playlist.entries) {
        if (oldEntries[entry.id] == entry.track) continue;
        final owner = collections()
            .where((c) => c.id == entry.track.collectionId)
            .firstOrNull;
        if (owner == null ||
            !scope.includes(
              owner.catalogCollection,
              authorized: access(owner.id),
            )) {
          throw StateError('A playlist entry is no longer eligible.');
        }
      }
      final values = List<dynamic>.from(data['playlists'] ?? []);
      if (values.any(
        (v) =>
            v['id'] == playlist.id &&
            v['collectionId'] != playlist.scope.collectionId,
      )) {
        throw StateError('Playlist scope cannot change.');
      }
      values.removeWhere((v) => v['id'] == playlist.id);
      values.add(playlist.toJson());
      data['playlists'] = values;
    });
  }

  Future<void> deletePlaylist(MusicPlaylist playlist) =>
      _extrasChange(playlist.scope.collectionId, (data) {
        data['playlists'] = (data['playlists'] as List)
            .where((p) => p['id'] != playlist.id)
            .toList();
      });
  String newIdentity() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  List<MusicTrack> playlistTracks(
    MusicPlaylist playlist,
    List<MusicTrack> tracks,
  ) {
    final byId = {
      for (final track in tracks.where((t) => t.available))
        track.catalogTitle.id: track,
    };
    final entries = playlist.eligibleEntries(
      collections: {for (final c in collections()) c.id: c.catalogCollection},
      authorizedCollections: {
        for (final c in collections())
          if (access(c.id)) c.id,
      },
      availableTracks: byId.keys.toSet(),
    );
    return [for (final entry in entries) byId[entry.track]!];
  }
}
