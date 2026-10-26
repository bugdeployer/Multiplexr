import 'package:multiplexr/src/core/application/mutations.dart';

import 'fixtures/legacy_music_provider.dart';

import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/media/session_mini_player.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/library/backup_page.dart';
import 'package:multiplexr/src/media/audio_library.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/music_catalog.dart';
import 'package:multiplexr/src/media/music_repository.dart';
import 'package:multiplexr/src/media/music_page.dart';
import 'package:multiplexr/src/media/music_metadata_ui.dart';
import 'package:multiplexr/src/media/music_track_picker.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/features/catalog/application/space_queries.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'music_catalog_test.dart' show source, scan;
import 'music_playback_test.dart' show FakeAudio;
import 'audio_foundation_test.dart' show book;

class DelayedStore extends SharedStore {
  Completer<void>? gate;
  bool failExtras = false;
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    if (gate != null) await gate!.future;
    return super.readState(key);
  }

  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    if (failExtras && key == 'music:extras') throw StateError('Disk full');
    await super.writeState(key, value);
  }
}

MusicSource moved(String id, String root, {String album = 'Album'}) =>
    MusicSource(
      id: id,
      rootId: root,
      folderId: '$root/Album',
      folderName: 'Album',
      file: AudioFile(
        id: id,
        uri: 'content://$id',
        filename: 'Song.mp3',
        title: 'Song',
        album: album,
        artist: 'Artist',
        durationMs: 60000,
        disc: 1,
        track: 1,
      ),
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DelayedStore store;
  late LibraryController library;
  late MusicRepository repository;
  setUp(() {
    store = DelayedStore();
    library = createLibraryController(store);
    const collection = VideoCollection(
      id: 'c',
      name: 'Music QA',
      kind: MediaKind.music,
      subtype: VideoSubtype.videos,
    );
    library.collections = [collection];
    store.collections.add(collection.toJson());
    repository = MusicRepository(library);
    store.states[MusicCatalogRepository.key] = scan([source('1'), source('2')])
        .toJson();
  });
  tearDown(() => library.dispose());
  test('unique strong source evidence reconnects moved roots without changing IDs or corrections', () {
    final before = scan([moved('old', 'root-old')]);
    final original = before.tracks.single.corrected({'title': 'My title'});
    final after = scan([
      moved('new', 'root-new'),
    ], before: MusicCatalog([original]));
    expect(after.tracks, hasLength(1));
    expect(after.tracks.single.id, original.id);
    expect(after.tracks.single.metadata.title, 'My title');
    expect(after.tracks.single.source.uri, 'content://new');
  });
  test('ambiguous replacement sources never auto-merge', () {
    final before = scan([moved('old', 'root-old')]);
    final after = scan([
      moved('new', 'root-new'),
      moved('copy', 'root-new'),
    ], before: before);
    expect(after.tracks, hasLength(3));
    expect(after.tracks.where((t) => !t.available), hasLength(1));
  });
  test('catalog artwork is deduplicated and legacy inline artwork remains readable', () {
    final image = 'data:image/png;base64,${List.filled(20000, 'A').join()}';
    final tracks = scan([for (var i = 0; i < 100; i++) source('$i')]).tracks
        .map((t) => t.corrected({'cover': image}))
        .toList();
    final catalog = MusicCatalog(tracks);
    final value = catalog.toJson();
    expect(value['artwork'], hasLength(1));
    expect(jsonEncode(value).length, lessThan(250000));
    expect(MusicCatalog.fromJson(value).tracks.first.metadata.cover, image);
    expect(
      MusicCatalog.fromJson({
        'version': 1,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      }).tracks.first.metadata.cover,
      image,
    );
  });
  test(
    'bulk Add and Remove tags preserve existing sets and support Undo',
    () async {
      final tracks = (await repository.catalog.read()).tracks;
      await repository.setFlags(tracks.first.id, {
        'tags': ['Keep A'],
      });
      await repository.setFlags(tracks.last.id, {
        'tags': ['Keep B'],
      });
      final before = await repository.changeTags(
        tracks.map((t) => t.id).toList(),
        'add',
        ['New'],
      );
      expect(
        repository.flags(await repository.extras(), tracks.first.id)['tags'],
        ['Keep A', 'New'],
      );
      await repository.changeTags([tracks.first.id], 'remove', ['new']);
      expect(
        repository.flags(await repository.extras(), tracks.first.id)['tags'],
        ['Keep A'],
      );
      await repository.restoreTags(before);
      expect(
        repository.flags(await repository.extras(), tracks.last.id)['tags'],
        ['Keep B'],
      );
    },
  );
  test(
    'album artwork inheritance reaches playback and track overrides win',
    () async {
      final tracks = (await repository.catalog.read()).tracks;
      final album = repository.albums(tracks, await repository.extras()).single;
      await repository.setAlbum(album, {'cover': 'album-cover'});
      expect(
        (await repository.tracks(
          const SpaceScope(MediaSubtype.music, collectionId: 'c'),
        )).first.metadata.cover,
        'album-cover',
      );
      final audio = FakeAudio(),
          playback = createMusicPlayback(library: library, audio: FakeAudio());
      await playback.play(tracks, start: tracks.first.id, collectionId: 'c');
      expect(playback.current!.metadata.cover, 'album-cover');
      await repository.patchTrack(
        tracks.first.id,
        (t) => t.corrected({'cover': 'track-cover'}),
      );
      expect(
        (await repository.tracks(
          const SpaceScope(MediaSubtype.music, collectionId: 'c'),
        )).first.metadata.cover,
        'track-cover',
      );
      playback.dispose();
      audio.dispose();
    },
  );
  test(
    'partial online album apply preserves untouched manual fields',
    () async {
      final tracks = (await repository.catalog.read()).tracks;
      final album = repository.albums(tracks, await repository.extras()).single;
      await repository.setAlbum(album, {
        'title': 'My title',
        'artist': 'My artist',
        'year': 2000,
        'metadataSource': 'manual',
      });
      final target = MusicMetadataTarget(repository, album: album),
          coordinator = MetadataWorkflow(
            [],
            mutations: const OwnerApplicationMutations(),
          );
      final review = await coordinator.review(
        target,
        MetadataCandidate(
          provider: 'musicbrainz',
          id: 'release',
          entity: MetadataEntityType.musicAlbum,
          values: {'title': 'Online title', 'year': 2026},
          attribution: 'MusicBrainz',
        ),
        MetadataCancellation(),
      );
      await coordinator.apply(target, review, {'year'}, MetadataCancellation());
      final after = await target.read();
      expect(after.fields['title'], 'My title');
      expect(after.manualFields, containsAll(['title', 'artist']));
      expect(after.manualFields, isNot(contains('year')));
    },
  );
  test('rate limit pauses at the first item and Resume preserves the remaining queue', () async {
    var requests = 0, fail = true;
    final provider = MusicBrainzProvider(
      rateLimit: false,
      get: (_) async {
        requests++;
        return fail
            ? const MusicResponse(429, [])
            : MusicResponse(200, utf8.encode('{"count":0,"recordings":[]}'));
      },
    );
    final job = createMusicMetadataJob(repository, 'c', provider);
    final tracks = (await repository.catalog.read()).tracks;
    await expectLater(job.start(tracks), throwsA(isA<MetadataFailure>()));
    expect(requests, 1);
    expect(job.remaining, hasLength(2));
    expect(job.pausedReason, isNotNull);
    fail = false;
    await job.start(tracks, resume: true);
    expect(job.remaining, isEmpty);
    expect(job.done, 2);
    job.dispose();
  });
  test('queue edits preserve occurrence IDs and can be undone', () async {
    final playback = createMusicPlayback(library: library, audio: FakeAudio()),
        tracks = (await repository.catalog.read()).tracks;
    await playback.play(
      [tracks.first, tracks.last, tracks.first],
      start: tracks.first.id,
      collectionId: 'c',
    );
    final before = playback.captureQueue();
    await playback.removeEntry(before.entries.last.entryId);
    expect(playback.queue, hasLength(2));
    await playback.restoreQueue(before);
    expect(
      playback.visibleEntries.map((e) => e.entryId),
      before.entries.map((e) => e.entryId),
    );
    await playback.reorderEntry(2, 1);
    expect(playback.visibleEntries[1].entryId, before.entries.last.entryId);
    await playback.clearQueue();
    expect(playback.queue, isEmpty);
    await playback.restoreQueue(before);
    expect(playback.queue, hasLength(3));
    playback.dispose();
  });
  test('scoped resume excludes hidden global collections without losing the active queue', () async {
    final audio = FakeAudio();
    final playback = createMusicPlayback(library: library, audio: audio);
    final tracks = await repository.tracks(
      const SpaceScope(MediaSubtype.music, collectionId: 'c'),
    );
    await playback.play(tracks, start: tracks.first.id, collectionId: 'c');
    final previous = playback.captureQueue();
    store.states['music:session'] = {
      'version': 1,
      'scopeCollectionId': 'c',
      'entries': [
        for (final e in previous.entries)
          {'entryId': e.entryId, 'owner': e.owner.toJson()},
      ],
      'traversal': previous.order,
      'currentEntryId': previous.entries.first.entryId,
      'positionMs': 18000,
      'repeat': 'off',
      'shuffled': false,
    };
    library.collections = [
      VideoCollection.fromJson({
        ...library.collections.single.toJson(),
        'includeInGlobalAudio': false,
      }),
    ];
    expect(
      await playback.restore(scope: const SpaceScope(MediaSubtype.music)),
      isFalse,
    );
    expect(
      playback.visibleEntries.map((e) => e.entryId),
      previous.entries.map((e) => e.entryId),
    );
    expect(
      await playback.restore(
        scope: const SpaceScope(MediaSubtype.music, collectionId: 'c'),
      ),
      isTrue,
    );
    expect(audio.scope, 'c');
    expect(audio.state.positionMs, 18000);
    playback.dispose();
  });
  test('backup summary counts audio titles and actual chapter sources', () {
    final b = book(collection: 'c');
    final summary = backupSummary({
      'collections': [{}],
      'assets': [],
      'state': {
        'audio:library': {
          'books': [b.toJson()],
        },
        'music:library': {
          'tracks': [{}, {}],
        },
      },
    });
    expect(summary, contains('1 audiobooks (2 audio files)'));
    expect(summary, contains('2 music tracks'));
  });
  testWidgets('rapid Play taps open a single player while storage is pending', (
    tester,
  ) async {
    final playback = createMusicPlayback(library: library, audio: FakeAudio());
    await tester.pumpWidget(
      MaterialApp(
        home: MusicPage(
          library: library,
          playback: playback,
          collectionId: 'c',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Album'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Play album'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    store.gate = Completer<void>();
    await tester.tap(find.text('Play album'));
    await tester.tap(find.text('Play album'));
    store.gate!.complete();
    store.gate = null;
    await tester.pumpAndSettle();
    expect(find.text('Now playing'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Now playing'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    playback.dispose();
  });
  testWidgets('metadata finder scrolls with keyboard and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            viewInsets: EdgeInsets.only(bottom: 300),
            textScaler: TextScaler.linear(1.8),
          ),
          child: MusicMetadataFinder(
            provider: MusicBrainzProvider(),
            entity: MetadataEntityType.musicAlbum,
            title: 'Album',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('No plugin platform is available.'), findsOneWidget);
  });
  for (final local in [true, false]) {
    testWidgets(
      '${local ? 'local' : 'global'} Music space exposes custom playlist creation through collection actions',
      (tester) async {
        final playback = createMusicPlayback(
          library: library,
          audio: FakeAudio(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MusicPage(
              library: library,
              playback: playback,
              collectionId: local ? 'c' : null,
              space: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your music'), local ? findsNothing : findsOneWidget);
        await tester.tap(find.byTooltip('Collection actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manage collection'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Create playlist'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.byType(TextField).last, 'My mix');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.byType(MusicTrackPicker), findsOneWidget);
        await tester.tap(find.text('Select all visible'));
        await tester.pump();
        await tester.tap(find.text('Add (2)'));
        await tester.pumpAndSettle();
        final lists = await repository.playlists(local ? 'c' : null);
        expect(lists.single.name, 'My mix');
        expect(lists.single.entries, hasLength(2));
        expect(find.text('Play playlist'), findsOneWidget);
        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename playlist'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'Unsaved name');
        store.failExtras = true;
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('My mix'), findsOneWidget);
        expect(find.text('Unsaved name'), findsNothing);
        expect(
          (await repository.playlists(local ? 'c' : null)).single.name,
          'My mix',
        );
        store.failExtras = false;
        await tester.pumpWidget(const SizedBox.shrink());
        playback.dispose();
      },
    );
  }
  testWidgets(
    'shared mini-player shows audiobook sessions and hides revoked titles',
    (tester) async {
      library.collections = [
        const VideoCollection(
          id: 'c',
          name: 'Books',
          kind: MediaKind.audiobook,
          subtype: VideoSubtype.videos,
        ),
      ];
      final b = book(collection: 'c');
      store.states[AudioLibrary.key] = {
        'version': 1,
        'books': [b.toJson()],
      };
      final audio = FakeAudio();
      audio.state = AudioState({
        'id': b.id.toJson(),
        'playing': true,
        'positionMs': 1000,
        'durationMs': 60000,
      });
      final playback = createMusicPlayback(library: library, audio: audio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: SessionMiniPlayer(playback: playback),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A book'), findsOneWidget);
      library.collections = [
        VideoCollection.fromJson({
          ...library.collections.single.toJson(),
          'locked': true,
        }),
      ];
      library.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('A book'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      playback.dispose();
    },
  );
}
