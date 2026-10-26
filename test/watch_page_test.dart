import 'package:multiplexr/src/library/legacy_video_playback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/library/player.dart';
import 'package:multiplexr/src/library/watch_details.dart';
import 'package:multiplexr/src/library/native_player.dart';

class WatchService extends LibraryService {
  @override
  Object get persistenceOwner => this;
  @override
  Future<void> position(VideoAsset asset, int positionMs) async {}
}

void main() {
  testWidgets(
    'portrait watch page keeps the native player across fullscreen transitions',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var creates = 0;
      var autoPip = false;
      final channels = <MethodChannel>[];
      messenger.setMockMethodCallHandler(
        PlaybackWindow.channel,
        (call) async => call.method == 'enterPip' ? true : null,
      );
      final orientations = <List<dynamic>>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(List.of(call.arguments));
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        final args = call.arguments as Map;
        if (call.method == 'create') {
          creates++;
          final channel = MethodChannel('multiplexr/player/${args['id']}');
          channels.add(channel);
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'autoPip') autoPip = call.arguments == true;
            return call.method == 'state'
                ? {
                    'positionMs': 37000,
                    'durationMs': 120000,
                    'playing': false,
                    'autoPip': autoPip,
                  }
                : null;
          });
          return creates;
        }
        if (call.method == 'resize') {
          return {'width': args['width'], 'height': args['height']};
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        messenger.setMockMethodCallHandler(PlaybackWindow.channel, null);
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrPlayer(
            asset: const VideoAsset(
              id: 'a',
              collectionId: 'c',
              uri: 'content://a',
              filename: 'Video.mp4',
              metadata: {'title': 'My video', 'description': 'My description'},
            ),
            host: LegacyVideoPlaybackHost(WatchService()),
            watchPage: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WatchDetails), findsOneWidget);
      expect(tester.getSize(find.byType(AndroidView)).height, 225);
      expect(creates, 1);
      expect(orientations.last, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
      await tester.tap(find.byTooltip('Playback options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Floating window'));
      await tester.pumpAndSettle();
      expect(autoPip, true);
      expect(PlaybackWindow.instance.active, false);
      Navigator.of(tester.element(find.text('Floating window'))).pop();
      await tester.pumpAndSettle();
      await messenger.handlePlatformMessage(
        PlaybackWindow.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pipChanged', true),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(PlaybackWindow.instance.active, true);
      expect(find.byType(WatchDetails), findsNothing);
      expect(find.byType(MultiplexrControls), findsNothing);
      expect(creates, 1);
      await messenger.handlePlatformMessage(
        PlaybackWindow.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pipChanged', false),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(WatchDetails), findsOneWidget);
      await tester.tap(find.byTooltip('Fullscreen'));
      tester.view.physicalSize = const Size(800, 400);
      await tester.pumpAndSettle();
      expect(find.byType(WatchDetails), findsNothing);
      expect(creates, 1);
      expect(orientations.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();
      expect(find.byType(WatchDetails), findsOneWidget);
      expect(creates, 1);
      expect(find.text('00:37'), findsOneWidget);
      expect(orientations.last, [
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
