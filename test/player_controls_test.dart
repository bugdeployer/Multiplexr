import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/native_player.dart';
import 'package:multiplexr/src/library/player.dart';

class ControlsPlayer extends Player {
  final calls = <String>[];
  ControlsPlayer() {
    state = PlaybackState({
      'playing': true,
      'positionMs': 30000,
      'durationMs': 120000,
      'rate': 1.0,
      'selectedSubtitle': 'no',
      'subtitles': [
        {'id': 'no'},
        {'id': 'auto'},
        {'id': '1:0', 'language': 'en'},
      ],
    });
  }
  @override
  Future<void> addSubtitle() async {
    calls.add('addSubtitle');
    state = PlaybackState({...state.data, 'externalSubtitle': 'captions.srt'});
    notifyListeners();
  }

  @override
  Future<void> removeSubtitle() async {
    calls.add('removeSubtitle');
    state = PlaybackState({...state.data, 'externalSubtitle': null});
    notifyListeners();
  }

  @override
  Future<void> resetPreferences() async {
    calls.add('resetPreferences');
    state = PlaybackState({...state.data, 'fit': 'fit', 'rate': 1.0});
    notifyListeners();
  }

  @override
  Future<void> controlsVisible(bool value) async {
    calls.add('visible:$value');
  }

  @override
  Future<void> seek(Duration value) async {
    calls.add('seek:${value.inSeconds}');
  }

  @override
  Future<void> playOrPause() async {
    calls.add('playPause');
  }

  @override
  Future<void> setRate(double value) async {
    calls.add('rate:$value');
    state = PlaybackState({...state.data, 'rate': value});
    notifyListeners();
  }

  @override
  Future<void> setSubtitleTrack(PlaybackTrack value) async {
    calls.add('subtitle:${value.id}');
    state = PlaybackState({...state.data, 'selectedSubtitle': value.id});
    notifyListeners();
  }

  @override
  Future<void> setSubtitleStyle(double scale, bool background) async {
    calls.add('subtitleStyle:$background');
  }

  @override
  Future<void> setBackground(bool value) async {
    calls.add('background:$value');
    state = PlaybackState({...state.data, 'background': value});
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'embedded playback errors fit and keep recovery actions accessible',
    (tester) async {
      final player = ControlsPlayer();
      player.state = PlaybackState({
        ...player.state.data,
        'playing': false,
        'error': 'Access to this file was lost. Select its root folder again in collection settings.',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 360,
                height: 202.5,
                child: MultiplexrControls(
                  compact: true,
                  player: player,
                  fullscreen: () async {},
                  external: () async {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('External player'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
    },
  );

  testWidgets('completion uses replay and next controls without a prompt', (
    tester,
  ) async {
    final player = ControlsPlayer();
    player.state = PlaybackState({
      ...player.state.data,
      'playing': false,
      'completed': true,
    });
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiplexrControls(
            player: player,
            fullscreen: () async {},
            external: () async {},
            next: () async {
              next++;
            },
          ),
        ),
      ),
    );
    expect(find.text('Playback complete'), findsNothing);
    expect(find.byTooltip('Replay'), findsOneWidget);
    await tester.tap(find.byTooltip('Play next'));
    await tester.pump();
    expect(next, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });

  testWidgets('subtitle import and removal are reachable through the player', (
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
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Subtitles'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add subtitle file'));
    await tester.tap(find.text('Add subtitle file'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('addSubtitle'));
    expect(find.text('captions.srt'), findsOneWidget);
    await tester.ensureVisible(find.text('Remove external subtitles'));
    await tester.tap(find.text('Remove external subtitles'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('removeSubtitle'));
    expect(find.text('Add subtitle file'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
  testWidgets('playback options reflect saved fit and can reset preferences', (
    tester,
  ) async {
    final player = ControlsPlayer();
    player.state = PlaybackState({...player.state.data, 'fit': 'fill'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiplexrControls(
            player: player,
            fullscreen: () async {},
            external: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Playback options'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fill / crop'))
          .selected,
      true,
    );
    await tester.ensureVisible(find.text('Reset playback preferences'));
    await tester.tap(find.text('Reset playback preferences'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('resetPreferences'));
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fit'))
          .selected,
      true,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
  testWidgets(
    'compact controls tolerate large text without horizontal overflow',
    (tester) async {
      final player = ControlsPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 360,
                  height: 202.5,
                  child: MultiplexrControls(
                    compact: true,
                    player: player,
                    fullscreen: () async {},
                    external: () async {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
    },
  );

  testWidgets(
    'embedded player fits a portrait watch page and exposes fullscreen',
    (tester) async {
      final player = ControlsPlayer();
      var fullscreen = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 360,
                height: 202.5,
                child: MultiplexrControls(
                  compact: true,
                  title: 'A long personal video title',
                  player: player,
                  fullscreen: () async {
                    fullscreen++;
                  },
                  external: () async {},
                  back: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Fullscreen'));
      await tester.pump();
      expect(fullscreen, 1);
      expect(find.byTooltip('Subtitles'), findsNothing);
      expect(find.byTooltip('Audio tracks'), findsNothing);
      expect(find.byTooltip('Touch lock'), findsNothing);
      await tester.tap(find.byTooltip('Playback options'));
      await tester.pumpAndSettle();
      expect(find.text('Audio tracks'), findsOneWidget);
      expect(find.text('Subtitles'), findsOneWidget);
      await tester.tap(find.text('Playback speed'));
      await tester.pumpAndSettle();
      expect(find.text('Playback speed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      player.dispose();
    },
  );
  testWidgets('touch lock blocks playback controls and double tap seeking', (
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
            title: 'Film',
            landscapeOnly: true,
          ),
        ),
      ),
    );
    expect(find.byTooltip('Fullscreen'), findsNothing);
    await tester.tap(find.byTooltip('Touch lock'));
    await tester.pump();
    expect(find.byTooltip('Pause'), findsNothing);
    await tester.tapAt(const Offset(500, 250));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(500, 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.calls.where((c) => c.startsWith('seek:')), isEmpty);
    expect(find.text('Unlock controls'), findsOneWidget);
    await tester.tap(find.text('Unlock controls'));
    await tester.pump();
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pump();
    expect(player.calls, contains('seek:40'));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byTooltip('Pause'), findsNothing);
    await tester.tapAt(const Offset(500, 250));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
  testWidgets('background playback switch calls the native playback setting', (
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
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Playback options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Background playback'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('background:true'));
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });

  testWidgets('speed and subtitle sheets apply real playback settings', (
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
          ),
        ),
      ),
    );
    await tester.tap(find.text('1.0×'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('rate:1.5'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Subtitles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('en'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('subtitle:1:0'));
    await tester.ensureVisible(find.text('Subtitle background'));
    await tester.tap(find.text('Subtitle background'));
    await tester.pumpAndSettle();
    expect(player.calls, contains('subtitleStyle:true'));
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
  });
}
