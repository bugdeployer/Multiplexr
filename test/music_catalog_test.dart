import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/music_catalog.dart';

import 'media_foundation_test.dart' show SharedStore;

MusicSource source(
  String id, {
  String root = 'root',
  String folder = 'folder',
  String album = 'Album',
  String artist = 'Artist',
  String albumArtist = '',
  int disc = 0,
  int track = 0,
  String? uri,
  String release = '',
}) => MusicSource(
  id: id,
  rootId: root,
  folderId: folder,
  folderName: 'Folder album',
  albumArtist: albumArtist,
  releaseId: release,
  file: AudioFile(
    id: id,
    uri: uri ?? 'content://audio/$id',
    filename: 'Track $id.mp3',
    album: album,
    artist: artist,
    disc: disc,
    track: track,
  ),
);
MusicCatalog scan(
  List<MusicSource> sources, {
  MusicCatalog? before,
  String collection = 'c',
}) => reconcileMusic(
  previous: before ?? MusicCatalog([]),
  collectionId: collection,
  discovered: sources,
);

void main() {
  test('ambiguous editions in separate folders are isolated and reported', () {
    final sources = [
      source('1', folder: 'standard'),
      source('2', folder: 'deluxe'),
    ];
    expect(scan(sources).tracks.map((t) => t.albumId).toSet(), hasLength(2));
    expect(musicGroupingWarnings(sources), hasLength(1));
    final multidisc = [
      source('1', folder: 'disc1', disc: 1),
      source('2', folder: 'disc2', disc: 2),
    ];
    expect(scan(multidisc).tracks.map((t) => t.albumId).toSet(), hasLength(1));
    expect(musicGroupingWarnings(multidisc), isEmpty);
  });
  test('repository serializes updates and refuses unauthorized or cross-owner writes', () async {
    final store = SharedStore();
    final repository = MusicCatalogRepository(store);
    await repository.update(
      collectionId: 'c',
      authorized: (_) => true,
      change: (_) => scan([source('1')]),
    );
    await expectLater(
      repository.update(
        collectionId: 'c',
        authorized: (_) => false,
        change: (_) => MusicCatalog([]),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.update(
        collectionId: 'other',
        authorized: (_) => true,
        change: (_) => MusicCatalog([]),
      ),
      throwsStateError,
    );
    await Future.wait([
      repository.update(
        collectionId: 'c',
        authorized: (_) => true,
        change: (before) => scan([source('1'), source('2')], before: before),
      ),
      repository.update(
        collectionId: 'other',
        authorized: (_) => true,
        change: (before) =>
            scan([source('3')], before: before, collection: 'other'),
      ),
    ]);
    expect((await repository.read()).tracks, hasLength(3));
    store.states[MusicCatalogRepository.key] = {'version': 99, 'tracks': []};
    await expectLater(
      repository.update(
        collectionId: 'c',
        authorized: (_) => true,
        change: (_) => MusicCatalog([]),
      ),
      throwsFormatException,
    );
    expect(store.states[MusicCatalogRepository.key]!['version'], 99);
  });
  test('tag album artist groups compilations and multiple discs', () {
    final catalog = scan([
      source('1', artist: 'A', albumArtist: 'Various Artists', disc: 1),
      source('2', artist: 'B', albumArtist: 'Various Artists', disc: 2),
    ]);
    expect(catalog.tracks.map((t) => t.albumId).toSet(), hasLength(1));
    expect(catalog.tracks.first.metadata.artist, 'A');
    expect(catalog.tracks.last.metadata.artist, 'B');
  });
  test('album identity separates roots, artists and editions', () {
    final catalog = scan([
      source('1'),
      source('2', root: 'other'),
      source('3', artist: 'Other'),
      source('4', release: 'edition'),
    ]);
    expect(catalog.tracks.map((t) => t.albumId).toSet(), hasLength(4));
  });
  test('folder fallback keeps loose root tracks ungrouped', () {
    final catalog = scan([
      source('1', album: '', artist: ''),
      source('2', album: '', artist: '', folder: 'other'),
      source('3', album: '', folder: 'root'),
    ]);
    expect(catalog.tracks[0].metadata.album, 'Folder album');
    expect(catalog.tracks[0].albumId, isNot(catalog.tracks[1].albumId));
    expect(catalog.tracks[2].albumId, isNull);
    expect(catalog.tracks[2].metadata.album, isEmpty);
  });
  test(
    'rescan preserves identity and corrections while refreshing source URI',
    () {
      final first = scan([source('1')]);
      final corrected = first.tracks.single.corrected({
        'title': 'My title',
        'albumArtist': 'Correct artist',
        'cover': 'content://cover',
        'coverSource': 'manual',
        'albumId': 'manual-group',
      });
      final next = scan([
        source('1', uri: 'content://new/1'),
      ], before: MusicCatalog([corrected]));
      expect(next.tracks.single.id, corrected.id);
      expect(next.tracks.single.metadata.title, 'My title');
      expect(next.tracks.single.metadata.cover, 'content://cover');
      expect(next.tracks.single.albumId, 'manual-group');
      expect(next.tracks.single.source.uri, 'content://new/1');
      expect(
        scan([source('1', uri: 'content://new/1')], before: next).toJson(),
        next.toJson(),
      );
    },
  );
  test(
    'missing files remain unavailable and recover without losing corrections',
    () {
      final first = scan([source('1'), source('2')]);
      final missing = scan([source('1')], before: first);
      expect(missing.tracks.last.available, false);
      expect(missing.tracks.last.catalogTitle.sources.single.available, false);
      final restored = scan([source('1'), source('2')], before: missing);
      expect(restored.tracks.last.id, first.tracks.last.id);
      expect(restored.tracks.last.available, true);
    },
  );
  test('one collection rescan does not change another and overlapping roots dedupe', () {
    final first = scan([source('1')]);
    final next = scan(
      [source('1'), source('1')],
      before: first,
      collection: 'other',
    );
    expect(next.tracks, hasLength(2));
    expect(next.tracks.first.toJson(), first.tracks.first.toJson());
    expect(
      () => scan([source('1'), source('1', uri: 'content://conflict')]),
      throwsArgumentError,
    );
  });
  test('ordering respects disc/track then natural names, independent of scan order', () {
    final tracks = scan([
      source('10'),
      source('2'),
      source('9', disc: 2),
      source('5', track: 1),
      source('6', track: 2),
    ]).tracks;
    expect(orderedMusicTracks(tracks).map((t) => t.source.id), [
      '5',
      '6',
      '2',
      '10',
      '9',
    ]);
    expect(
      orderedMusicTracks(tracks.reversed).map((t) => t.id),
      orderedMusicTracks(tracks).map((t) => t.id),
    );
  });
  test(
    'catalog roundtrip and corruption checks preserve explicit ungrouping',
    () {
      final track = scan([source('1')]).tracks.single
          .corrected({'albumId': null});
      final catalog = MusicCatalog([track]);
      final restored = MusicCatalog.fromJson(catalog.toJson());
      expect(restored.toJson(), catalog.toJson());
      expect(
        scan([source('1')], before: restored).tracks.single.albumId,
        isNull,
      );
      expect(() => MusicCatalog([track, track]), throwsArgumentError);
      expect(
        () => MusicCatalog.fromJson({...catalog.toJson(), 'version': 7}),
        throwsFormatException,
      );
      expect(
        () => track.corrected({'author': 'wrong type'}),
        throwsArgumentError,
      );
    },
  );
}
