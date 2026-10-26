import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/library/legacy_video_playback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/player.dart';
import 'package:multiplexr/src/library/native_player.dart';
import 'package:multiplexr/src/library/video_scope.dart';

import 'global_videos_test.dart' show VideosStorage, videosLibrary;
import 'global_videos_player_test.dart' show mockSurface;
import 'phase_two_player_test.dart' show PlaybackLibrary;
import 'phase_two_test.dart' show episode;

import 'package:multiplexr/src/library/library_models.dart';

Future<void> pip(WidgetTester tester, bool enabled) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'multiplexr/playback',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('pipChanged', enabled),
    ),
    (_) {},
  );
}

void main() {
  for (final mode in ['pip', 'background', 'locked']) {
    testWidgets('#4 completion in $mode advances at most once on safe return', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        PlaybackWindow.instance.active = false;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      final storage = VideosStorage();
      final library = await videosLibrary(storage: storage);
      final items = videoSpaceItems(library);
      final first = items.firstWhere((a) => a.collectionId == 'a');
      final next = items.firstWhere((a) => a.collectionId == 'b');
      await library.enqueue(next);
      var complete = false;
      final creations = mockSurface(
        firstCompleted: () => complete,
        background: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrPlayer(
            asset: first,
            host: LegacyVideoPlaybackHost(storage),
            library: library,
            watchPage: true,
            globalVideos: true,
            startFullscreen: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (mode == 'pip') {
        await pip(tester, true);
      } else {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      complete = true;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(creations.length, 1);
      expect(library.queuedVideos.length, 1);
      if (mode == 'locked') {
        storage.collections.firstWhere((c) => c['id'] == 'b')['locked'] = true;
        await library.load();
      }
      if (mode == 'pip') {
        await pip(tester, false);
      } else {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      if (mode == 'locked') {
        expect(creations.length, 1);
        expect(storage.positions['b'], isNull);
      } else {
        expect(creations.map((c) => c['collectionId']), ['a', 'b']);
        expect(library.queuedVideos, isEmpty);
      }
      final history = storage.positions['a']!;
      expect(history.last, 10000);
      expect(history.skipWhile((p) => p != 10000), everyElement(10000));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final autoplay in [false, true]) {
    testWidgets(
      '#4 deferred TV completion respects episode autoplay=$autoplay',
      (tester) async {
        tester.view.physicalSize = const Size(800, 450);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = PlaybackLibrary();
        service.collections.add(
          VideoCollection(
            id: 'c',
            name: 'TV',
            subtype: VideoSubtype.cinema,
            autoplayNext: autoplay,
          ).toJson(),
        );
        final first = episode('first', 1, 1), next = episode('next', 1, 2);
        service.assets.addAll([first.toJson(), next.toJson()]);
        final library = createLibraryController(service);
        await library.load();
        PlaybackWindow.instance.active = true;
        addTearDown(() => PlaybackWindow.instance.active = false);
        final creates = mockSurface(firstCompletes: true);
        await tester.pumpWidget(
          MaterialApp(
            home: MultiplexrPlayer(
              asset: first,
              host: LegacyVideoPlaybackHost(service),
              library: library,
              landscapeOnly: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(creates.length, 1);
        await pip(tester, false);
        await tester.pumpAndSettle();
        expect(creates.length, autoplay ? 2 : 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
