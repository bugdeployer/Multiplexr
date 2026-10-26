import 'package:multiplexr/src/bootstrap/reading_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/settings/application/player_preferences.dart';
import 'package:multiplexr/src/library/legacy_player_preferences.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/player.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/audio_session.dart';
import 'package:multiplexr/src/settings/presentation/players_readers_page.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'music_playback_test.dart' show FakeAudio;
import 'music_catalog_test.dart' show scan, source;
import 'player_controls_test.dart' show ControlsPlayer;

class FailingPlayerStore extends LegacyPlayerPreferenceStore {
  FailingPlayerStore(super.service);
  @override
  Future<void> write(PlayerKind kind, Map<String, dynamic>? value) async {
    throw StateError('Storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('player defaults preserve current skip and queue behavior', () async {
    final preferences = PlayerPreferences(
      LegacyPlayerPreferenceStore(SharedStore()),
    );
    final video = await preferences.load(PlayerKind.video);
    final books = await preferences.load(PlayerKind.audiobooks);
    final music = await preferences.load(PlayerKind.music);
    expect([video.backSeconds, video.forwardSeconds], [10, 10]);
    expect([books.backSeconds, books.forwardSeconds], [15, 30]);
    expect(music.shuffle, false);
    expect(music.repeat, '');
  });

  test(
    'concurrent saves and individual resets preserve sibling player settings',
    () async {
      final service = SharedStore();
      final preferences = PlayerPreferences(
        LegacyPlayerPreferenceStore(service),
      );
      await Future.wait([
        preferences.save(
          PlayerKind.video,
          const PlayerOptions(backSeconds: 5, forwardSeconds: 20),
        ),
        preferences.save(
          PlayerKind.music,
          const PlayerOptions(
            backSeconds: 10,
            forwardSeconds: 10,
            shuffle: true,
            repeat: 'all',
          ),
        ),
      ]);
      expect((await preferences.load(PlayerKind.video)).forwardSeconds, 20);
      expect((await preferences.load(PlayerKind.music)).repeat, 'all');
      await preferences.reset(PlayerKind.video);
      expect((await preferences.load(PlayerKind.video)).forwardSeconds, 10);
      expect((await preferences.load(PlayerKind.music)).shuffle, true);
    },
  );

  test(
    'invalid values are rejected; unreadable preferences do not block playback',
    () async {
      final service = SharedStore();
      final preferences = PlayerPreferences(
        LegacyPlayerPreferenceStore(service),
      );
      await expectLater(
        preferences.save(
          PlayerKind.video,
          const PlayerOptions(backSeconds: -1, forwardSeconds: 10),
        ),
        throwsArgumentError,
      );
      service.states[LegacyPlayerPreferenceStore.key] = {'version': 99};
      await expectLater(
        preferences.load(PlayerKind.video),
        throwsFormatException,
      );
      expect(
        (await preferences.loadForPlayback(PlayerKind.video)).backSeconds,
        10,
      );
    },
  );

  test(
    'music preferences affect new queues and explicit shuffle choices win',
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
      await library.playerPreferences.save(
        PlayerKind.music,
        const PlayerOptions(
          backSeconds: 10,
          forwardSeconds: 10,
          shuffle: true,
          repeat: 'all',
        ),
      );
      final tracks = scan([source('1'), source('2')]).tracks;
      await playback.play(tracks, start: tracks.first.id, collectionId: 'c');
      expect(audio.opened!.shuffled, true);
      expect(audio.opened!.repeat, AudioRepeatMode.all);
      await playback.play(
        tracks,
        start: tracks.first.id,
        collectionId: 'c',
        shuffle: false,
      );
      expect(audio.opened!.shuffled, false);
      playback.dispose();
      library.dispose();
    },
  );

  testWidgets('video controls dispatch configured skip intervals', (
    tester,
  ) async {
    final player = ControlsPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiplexrControls(
            player: player,
            fullscreen: () async {},
            external: () async {},
            backSeconds: 5,
            forwardSeconds: 20,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Back 5 seconds'));
    await tester.pump();
    expect(player.calls, contains('seek:25'));
    await tester.tap(find.byTooltip('Forward 20 seconds'));
    await tester.pump();
    expect(player.calls, contains('seek:50'));
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });

  testWidgets('failed player setting save restores the persisted selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerOptionsPage(
          preferences: PlayerPreferences(FailingPlayerStore(SharedStore())),
          kind: PlayerKind.video,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 seconds').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save player settings. Try again.'),
      findsOneWidget,
    );
    expect(find.text('20 seconds'), findsNothing);
    expect(find.text('10 seconds'), findsNWidgets(2));
  });

  testWidgets(
    'one category contains all five player and reader destinations at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = SharedStore();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: PlayersReadersPage(
            preferences: PlayerPreferences(
              LegacyPlayerPreferenceStore(service),
            ),
            reading: createReadingLibrary(service, authorized: (_) => true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final title in [
        'Video',
        'Music',
        'Audiobooks',
        'Ebooks',
        'Comics',
      ]) {
        await tester.ensureVisible(find.text(title));
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(Card), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Music'));
      await tester.tap(find.text('Music'));
      await tester.pumpAndSettle();
      expect(find.text('Shuffle new queues'), findsOneWidget);
      expect(find.text('Music player'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
