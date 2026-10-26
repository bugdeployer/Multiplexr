import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/playlist.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/audio_session.dart';
import 'package:multiplexr/src/media/contracts.dart';

CatalogIdentity track(String collection, String id) =>
    CatalogIdentity(collection, id, CatalogEntityKind.title);
CatalogCollection collection(
  String id, {
  bool locked = false,
  bool included = true,
  MediaSubtype subtype = MediaSubtype.music,
}) => CatalogCollection(
  id: id,
  name: id,
  subtype: subtype,
  access: CatalogAccess(locked: locked, includeInGlobal: included),
  roots: [],
);
AudioSessionEntry entry(
  String entryId,
  String collection,
  String title, {
  MediaKind kind = MediaKind.music,
}) => AudioSessionEntry(
  entryId: entryId,
  owner: MediaId(kind, collection, title),
  sourceId: title,
  uri: 'content://$collection/$title',
  title: title,
);

void main() {
  test('Music bridge carries real owners and shuffled occurrence order', () {
    final entries = [
      entry('1', 'a', 'song'),
      entry('2', 'b', 'other'),
      entry('3', 'a', 'song'),
    ];
    final session = AudioSession(
      mode: AudioSessionMode.music,
      entries: entries,
      currentEntryId: '3',
      traversal: ['1', '3', '2'],
    );
    final request = AudioPlaybackRequest.music(session).toJson();
    expect(request['index'], 1);
    expect(request['scopeCollectionId'], '');
    final files = request['files'] as List;
    expect(files.map((e) => e['id']), ['1', '3', '2']);
    expect(files[1]['owner'], entries[2].owner.toJson());
    expect(files[2]['owner'], entries[1].owner.toJson());
    expect(
      () => AudioPlaybackRequest.music(session, collectionId: 'a'),
      throwsArgumentError,
    );
  });
  test('Music declares optional albums and curated playlists with a production binding', () {
    final definition = appSubtypes.definition(MediaSubtype.music);
    expect(definition.enabled, true);
    expect(definition.hierarchy.titleRequiresGroup, false);
    expect(definition.hierarchy.structuralTitleParents, {
      CatalogGroupKind.album,
    });
    expect(definition.hierarchy.curatedParents, {CatalogGroupKind.playlist});
    expect(
      appSubtypes.requireEnabled(MediaSubtype.music).id,
      MediaSubtype.music,
    );
    expect(
      () => GroupMembership(
        parent: CatalogIdentity('a', 'album', CatalogEntityKind.group),
        child: track('b', 'song'),
        kind: MembershipKind.structural,
        order: 0,
      ),
      throwsArgumentError,
    );
  });
  test(
    'global playlist round trip retains repeated tracks with distinct entries',
    () {
      final playlist = MusicPlaylist(
        id: 'p',
        name: 'Mix',
        scope: const PlaylistScope.global(),
        entries: [
          PlaylistEntry(id: '1', track: track('a', 'song')),
          PlaylistEntry(id: '2', track: track('b', 'song')),
          PlaylistEntry(id: '3', track: track('a', 'song')),
        ],
      );
      final restored = MusicPlaylist.fromJson(playlist.toJson());
      expect(
        restored.entries.map((e) => e.track),
        playlist.entries.map((e) => e.track),
      );
      expect(restored.reordered(['3', '2', '1']).entries.first.id, '3');
      expect(() => restored.reordered(['1', '1', '3']), throwsArgumentError);
      expect(() => restored.entries.clear(), throwsUnsupportedError);
      expect(
        () => MusicPlaylist.fromJson({...playlist.toJson(), 'version': 2}),
        throwsFormatException,
      );
    },
  );
  test(
    'local playlists reject cross-collection and duplicate occurrence IDs',
    () {
      final e = PlaylistEntry(id: 'e', track: track('a', 'song'));
      expect(
        () => MusicPlaylist(
          id: 'p',
          name: 'Mix',
          scope: PlaylistScope.collection('b'),
          entries: [e],
        ),
        throwsArgumentError,
      );
      expect(
        () => MusicPlaylist(
          id: 'p',
          name: 'Mix',
          scope: const PlaylistScope.global(),
          entries: [e, e],
        ),
        throwsArgumentError,
      );
    },
  );
  test('global access is re-evaluated without deleting saved membership', () {
    final playlist = MusicPlaylist(
      id: 'p',
      name: 'Mix',
      scope: const PlaylistScope.global(),
      entries: [
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          PlaylistEntry(id: id, track: track(id, 'song')),
      ],
    );
    final collections = {
      'a': collection('a'),
      'b': collection('b', locked: true),
      'c': collection('c', included: false),
      'd': collection('d', subtype: MediaSubtype.audiobooks),
      'e': collection('e'),
    };
    final available = {
      for (final id in ['a', 'b', 'c', 'd']) track(id, 'song'),
    };
    expect(
      playlist
          .eligibleEntries(
            collections: collections,
            authorizedCollections: {'b'},
            availableTracks: available,
          )
          .map((e) => e.id),
      ['a'],
    );
    collections['b'] = collection('b');
    expect(
      playlist
          .eligibleEntries(
            collections: collections,
            authorizedCollections: {},
            availableTracks: available,
          )
          .map((e) => e.id),
      ['a', 'b'],
    );
    expect(playlist.entries, hasLength(5));
    final local = MusicPlaylist(
      id: 'local',
      name: 'Private',
      scope: PlaylistScope.collection('c'),
      entries: [PlaylistEntry(id: 'c', track: track('c', 'song'))],
    );
    expect(
      local.eligibleEntries(
        collections: collections,
        authorizedCollections: {},
        availableTracks: available,
      ),
      hasLength(1),
    );
  });
  test('Music session carries per-track progress owners and separate shuffle order', () {
    final entries = [
      entry('1', 'a', 'song'),
      entry('2', 'b', 'other'),
      entry('3', 'a', 'song'),
    ];
    final session = AudioSession(
      mode: AudioSessionMode.music,
      entries: entries,
      currentEntryId: '1',
      traversal: ['1', '3', '2'],
    );
    expect(session.next()!.entryId, '3');
    expect(session.next()!.owner, session.current.owner);
    expect(session.entries.map((e) => e.entryId), ['1', '2', '3']);
    final repeat = AudioSession(
      mode: AudioSessionMode.music,
      entries: entries,
      currentEntryId: '1',
      repeat: AudioRepeatMode.one,
    );
    expect(repeat.next(naturalCompletion: true)!.entryId, '1');
    expect(repeat.next()!.entryId, '2');
    expect(
      AudioSession(
        mode: AudioSessionMode.music,
        entries: entries,
        currentEntryId: '3',
      ).next(),
      isNull,
    );
    expect(
      AudioSession(
        mode: AudioSessionMode.music,
        entries: entries,
        currentEntryId: '3',
        repeat: AudioRepeatMode.all,
      ).next()!.entryId,
      '1',
    );
  });
  test('audiobook session cannot mix books or Music ownership', () {
    final chapters = [
      entry('1', 'a', 'book', kind: MediaKind.audiobook),
      entry('2', 'a', 'book', kind: MediaKind.audiobook),
    ];
    expect(
      AudioSession(
        mode: AudioSessionMode.audiobook,
        entries: chapters,
        currentEntryId: '1',
      ).next()!.owner,
      chapters.first.owner,
    );
    expect(
      () => AudioSession(
        mode: AudioSessionMode.audiobook,
        entries: [
          ...chapters,
          entry('3', 'a', 'other', kind: MediaKind.audiobook),
        ],
        currentEntryId: '1',
      ),
      throwsArgumentError,
    );
    expect(
      () => AudioSession(
        mode: AudioSessionMode.music,
        entries: chapters,
        currentEntryId: '1',
      ),
      throwsArgumentError,
    );
    expect(
      () => AudioSession(
        mode: AudioSessionMode.audiobook,
        entries: chapters,
        traversal: ['1', '1'],
        currentEntryId: '1',
      ),
      throwsArgumentError,
    );
  });
  test(
    'rich Music metadata retains legacy fields and online cover provenance',
    () {
      final legacy = MusicMetadata.fromJson({
        'title': 'Song',
        'artist': 'Artist',
        'album': 'Album',
      });
      expect(legacy.disc, 0);
      final metadata = MusicMetadata.fromJson({
        ...legacy.toJson(),
        'albumArtist': 'Various Artists',
        'disc': 2,
        'track': 3,
        'durationMs': 123000,
        'cover': 'https://cover.example/front',
        'coverSource': 'cover-art-archive',
        'recordingId': 'recording',
        'releaseId': 'edition',
        'releaseGroupId': 'release-group',
        'metadataSource': 'musicbrainz',
      });
      expect(
        MusicMetadata.fromJson(metadata.toJson()).toJson(),
        metadata.toJson(),
      );
      expect(metadata.artist, 'Artist');
      expect(metadata.albumArtist, 'Various Artists');
    },
  );
}
