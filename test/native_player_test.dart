import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/native_player.dart';

void main() {
  test('disposing during attachment never starts a polling timer', () async {
    const channel = MethodChannel('multiplexr/player/80');
    final gate = Completer<Map<String, dynamic>>();
    var reads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'state') return null;
      reads++;
      return gate.future;
    });
    final player = Player();
    final attach = player.attach(80);
    await Future<void>.delayed(Duration.zero);
    player.dispose();
    gate.complete({'playing': true});
    await attach;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(reads, 1);
    messenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'a command waits for a stale poll and refreshes the new state',
    () async {
      const channel = MethodChannel('multiplexr/player/81');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Completer<Map<String, dynamic>>? gate;
      double rate = 1;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'rate') rate = call.arguments as double;
        if (call.method == 'state') {
          if (gate != null) return gate.future;
          return {'rate': rate};
        }
        return null;
      });
      final player = Player();
      await player.attach(81);
      gate = Completer<Map<String, dynamic>>();
      final oldRead = player.refresh();
      await Future<void>.delayed(Duration.zero);
      final command = player.setRate(1.5);
      await Future<void>.delayed(Duration.zero);
      final pending = gate;
      gate = null;
      pending.complete({'rate': 1.0});
      await oldRead;
      await command;
      expect(player.state.rate, 1.5);
      player.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  test('playback state exposes saved styles with safe defaults', () {
    expect(PlaybackState().fit, 'fit');
    expect(PlaybackState().subtitleScale, 1);
    final state = PlaybackState({
      'subtitleScale': 9.0,
      'subtitleBackground': true,
      'externalSubtitle': 'test.srt',
    });
    expect(state.subtitleScale, 2);
    expect(state.subtitleBackground, true);
    expect(state.externalSubtitle, 'test.srt');
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test('native playback bridge updates position, selects real track IDs and disposes polling', () async {
    const channel = MethodChannel('multiplexr/player/7');
    final calls = <MethodCall>[];
    var position = 12000;
    var selected = '1:0';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'seek') position = call.arguments as int;
          if (call.method == 'audio') selected = call.arguments as String;
          if (call.method != 'state') return null;
          return {
            'positionMs': position,
            'durationMs': 90000,
            'playing': true,
            'rate': 1.25,
            'audio': [
              {'id': 'auto'},
              {'id': '1:0', 'language': 'en'},
              {'id': '2:0', 'language': 'fr'},
            ],
            'subtitles': [
              {'id': '3:0', 'language': 'en'},
            ],
            'selectedAudio': selected,
            'selectedSubtitle': '3:0',
          };
        });
    final player = Player();
    await player.attach(7);
    expect(player.state.duration.inSeconds, 90);
    expect(player.state.tracks.audio.last.language, 'fr');
    await player.seek(const Duration(seconds: 25));
    expect(player.state.position.inSeconds, 25);
    await player.setAudioTrack(player.state.tracks.audio.last);
    expect(player.state.track.audio.id, '2:0');
    await player.setSubtitleTrack(player.state.tracks.subtitle.single);
    expect(
      calls.any((c) => c.method == 'subtitle' && c.arguments == '3:0'),
      true,
    );
    await player.addSubtitle();
    await player.removeSubtitle();
    await player.resetPreferences();
    expect(
      calls.map((c) => c.method),
      containsAll(['addSubtitle', 'removeSubtitle', 'resetPreferences']),
    );
    player.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'dispose'), true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
