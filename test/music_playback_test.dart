import 'package:multiplexr/src/features/playback/application/audio_session_controller.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/audio_session.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/music_player.dart';
import 'package:multiplexr/src/media/media_cover.dart';
import 'package:multiplexr/src/media/music_catalog.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'music_catalog_test.dart' show scan, source;

class UnusedAudioEngine implements AudioEnginePort {
  @override
  Future<void> open(
    AudioPlaybackRequest request, {
    required bool autoplay,
  }) async => throw StateError('Unexpected engine open');
  @override
  Future<AudioSnapshot?> read() async => null;
  @override
  Future<void> execute(AudioCommand command) async =>
      throw StateError('Unexpected engine command');
}

class FakeAudio extends AudioController {
  FakeAudio()
    : super(
        engine: UnusedAudioEngine(),
        pickFiles: () async => null,
        releaseUnusedFiles: (_) async {},
      );
  AudioSession? opened;
  String? scope;
  final commands = <String>[];
  bool failOpen = false;
  @override
  Future<void> openMusic(
    AudioSession session, {
    String? collectionId,
    bool autoplay = true,
  }) async {
    if (failOpen) throw StateError('Player unavailable.');
    opened = session;
    scope = collectionId;
    state = AudioState({
      'id': session.current.owner.toJson(),
      'index': session.traversal.indexOf(session.currentEntryId),
      'positionMs': session.positionMs,
      'playing': autoplay,
    });
    notifyListeners();
  }

  @override
  Future<void> execute(AudioCommand command) async {
    commands.add(
      command is AudioActionCommand
          ? command.action.name
          : command.runtimeType.toString(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Music player keeps square artwork and scrollable controls with large text',
    (tester) async {
      tester.view.reset();
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = createLibraryController(SharedStore());
      library.collections = [
        const VideoCollection(
          id: 'c',
          name: 'Music',
          subtype: VideoSubtype.videos,
          kind: MediaKind.music,
        ),
      ];
      final audio = FakeAudio();
      final playback = createMusicPlayback(library: library, audio: audio);
      final tracks = scan([source('1'), source('2')]).tracks;
      await playback.play(tracks, start: tracks.first.id, collectionId: 'c');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: MusicPlayer(playback: playback),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cover = tester.getSize(find.byType(MediaCover));
      expect(cover.width, closeTo(cover.height, .01));
      await tester.ensureVisible(find.byTooltip('Next track'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next track'));
      expect(audio.commands, contains('nextTrack'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      playback.dispose();
      library.dispose();
    },
  );
  test('playlist playback starts the chosen duplicate occurrence', () async {
    final library = createLibraryController(SharedStore());
    library.collections = [
      const VideoCollection(
        id: 'c',
        name: 'Music',
        subtype: VideoSubtype.videos,
        kind: MediaKind.music,
      ),
    ];
    final audio = FakeAudio();
    final playback = createMusicPlayback(library: library, audio: audio);
    final track = scan([source('1')]).tracks.single;
    await playback.play(
      [track, track],
      start: track.id,
      startIndex: 1,
      collectionId: 'c',
    );
    expect(audio.opened!.currentEntryId, audio.opened!.entries[1].entryId);
    expect(
      audio.opened!.entries[0].entryId,
      isNot(audio.opened!.entries[1].entryId),
    );
    playback.dispose();
    library.dispose();
  });
  test('failed queue dispatch restores the previous queue and scope', () async {
    final library = createLibraryController(SharedStore());
    library.collections = [
      const VideoCollection(
        id: 'c',
        name: 'Music',
        subtype: VideoSubtype.videos,
        kind: MediaKind.music,
      ),
    ];
    final audio = FakeAudio();
    final playback = createMusicPlayback(library: library, audio: audio);
    final tracks = scan([source('1'), source('2')]).tracks;
    await playback.play(
      [tracks.first],
      start: tracks.first.id,
      collectionId: 'c',
    );
    audio.failOpen = true;
    await expectLater(playback.enqueue(tracks.last), throwsStateError);
    expect(playback.queue.map((t) => t.id), [tracks.first.id]);
    expect(playback.current!.id, tracks.first.id);
    playback.dispose();
    library.dispose();
  });
  test('restoring sessions resolves current sources and filters excluded references', () async {
    final store = SharedStore();
    final library = createLibraryController(store);
    library.collections = [
      const VideoCollection(
        id: 'c',
        name: 'Music',
        subtype: VideoSubtype.videos,
        kind: MediaKind.music,
      ),
    ];
    final audio = FakeAudio();
    final playback = createMusicPlayback(library: library, audio: audio);
    final tracks = scan([source('1'), source('2')]).tracks;
    store.states[MusicCatalogRepository.key] = MusicCatalog(tracks).toJson();
    store.states['music:session'] = {
      'version': 1,
      'entries': [
        {'entryId': 'one', 'owner': tracks.first.id.toJson()},
        {'entryId': 'two', 'owner': tracks.last.id.toJson()},
      ],
      'traversal': ['two', 'one'],
      'currentEntryId': 'two',
      'positionMs': 12000,
      'repeat': 'all',
      'scopeCollectionId': '',
    };
    expect(await playback.restore(), true);
    expect(audio.opened!.traversal, ['two', 'one']);
    expect(audio.opened!.entries.map((e) => e.entryId), ['one', 'two']);
    expect(audio.opened!.positionMs, 12000);
    expect(audio.state.playing, false);
    expect(playback.shuffled, true);
    playback.dispose();
    library.dispose();
  });
  test('queue repeats tracks without duplicating progress and preserves canonical shuffle order', () async {
    final library = createLibraryController(SharedStore());
    library.collections = [
      const VideoCollection(
        id: 'c',
        name: 'Music',
        subtype: VideoSubtype.videos,
        kind: MediaKind.music,
      ),
    ];
    final audio = FakeAudio();
    final playback = createMusicPlayback(library: library, audio: audio);
    final tracks = scan([source('1'), source('2'), source('3')]).tracks;
    await playback.play(tracks, start: tracks.first.id, collectionId: 'c');
    await playback.enqueue(tracks.first, next: true);
    expect(playback.queue, hasLength(4));
    expect(audio.opened!.entries.map((e) => e.entryId).toSet(), hasLength(4));
    expect(audio.opened!.next()!.owner, tracks.first.id);
    final canonical = audio.opened!.entries.map((e) => e.entryId).toList();
    await playback.setShuffle(true);
    expect(audio.opened!.entries.map((e) => e.entryId), canonical);
    expect(audio.opened!.traversal.toSet(), canonical.toSet());
    expect(audio.opened!.traversal.first, audio.opened!.currentEntryId);
    await playback.setShuffle(false);
    expect(audio.opened!.traversal, canonical);
    playback.dispose();
    library.dispose();
  });
  test(
    'global scope hides excluded content and stops after access changes',
    () async {
      final library = createLibraryController(SharedStore());
      library.collections = [
        const VideoCollection(
          id: 'c',
          name: 'Music',
          subtype: VideoSubtype.videos,
          kind: MediaKind.music,
        ),
      ];
      final audio = FakeAudio();
      final playback = createMusicPlayback(library: library, audio: audio);
      final tracks = scan([source('1')]).tracks;
      await playback.play(tracks, start: tracks.first.id);
      expect(playback.current, isNotNull);
      library.collections = [
        const VideoCollection(
          id: 'c',
          name: 'Music',
          subtype: VideoSubtype.videos,
          kind: MediaKind.music,
          includeInGlobalAudio: false,
        ),
      ];
      library.beginCollectionSession('c');
      expect(playback.current, isNull);
      expect(playback.queue, isEmpty);
      expect(audio.commands, contains('pause'));
      await expectLater(
        playback.play(tracks, start: tracks.first.id),
        throwsStateError,
      );
      await playback.play(tracks, start: tracks.first.id, collectionId: 'c');
      expect(playback.current, isNotNull);
      playback.dispose();
      library.dispose();
    },
  );
}
