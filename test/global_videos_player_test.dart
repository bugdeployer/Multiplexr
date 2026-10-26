import 'package:multiplexr/src/library/legacy_video_playback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/player.dart';
import 'package:multiplexr/src/library/video_art.dart';
import 'package:multiplexr/src/library/video_space.dart';
import 'package:multiplexr/src/library/video_scope.dart';

import 'global_videos_test.dart' show videosLibrary, VideosStorage;

List<Map<String, dynamic>> mockSurface({
  bool firstCompletes = false,
  bool Function()? firstCompleted,
  bool background = false,
}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final creations = <Map<String, dynamic>>[];
  final channels = <MethodChannel>[];
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
    call,
  ) async {
    final data = call.arguments as Map;
    if (call.method == 'create') {
      final params = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(data['params'] as Uint8List),
      );
      creations.add(Map<String, dynamic>.from(params as Map));
      final first = creations.length == 1;
      final channel = MethodChannel('multiplexr/player/${data['id']}');
      channels.add(channel);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'state'
            ? {
                'positionMs':
                    first && (firstCompleted?.call() ?? firstCompletes)
                    ? 10000
                    : 4200,
                'durationMs': 10000,
                'completed':
                    first && (firstCompleted?.call() ?? firstCompletes),
                'background': background,
                'playing': false,
              }
            : null,
      );
      return data['id'];
    }
    if (call.method == 'resize') {
      return {'width': data['width'], 'height': data['height']};
    }
    return null;
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  return creations;
}

void main() {
  testWidgets(
    'global queue crosses collections with duplicate IDs and keeps fullscreen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = VideosStorage();
      final library = await videosLibrary(storage: storage);
      final all = videoSpaceItems(library);
      final a = all.firstWhere((a) => a.collectionId == 'a');
      final b = all.firstWhere((a) => a.collectionId == 'b');
      await library.enqueue(b);
      final creations = mockSurface(firstCompletes: true);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrPlayer(
            asset: a,
            host: LegacyVideoPlaybackHost(storage),
            library: library,
            watchPage: true,
            globalVideos: true,
            startFullscreen: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final current = tester.widget<MultiplexrPlayer>(
        find.byType(MultiplexrPlayer),
      );
      expect(current.asset.collectionId, 'b');
      expect(current.globalVideos, true);
      expect(current.startFullscreen, true);
      expect(current.landscapeOnly, false);
      expect(creations.map((c) => c['collectionId']), ['a', 'b']);
      expect(storage.positions['a'], everyElement(10000));
      expect(library.queuedVideos, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'playing and returning preserves search, scroll and resume position',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = VideosStorage();
      final library = await videosLibrary(storage: storage, extra: 30);
      final creations = mockSurface();
      await tester.pumpWidget(
        MaterialApp(home: MultiplexrVideoSpace(library: library)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search videos'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Clip');
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      final card = tester.widget<VideoFeedCard>(
        find.byType(VideoFeedCard).hitTestable().first,
      );
      await tester.ensureVisible(find.text(card.asset.title));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<ListView>(find.byType(ListView).first)
          .controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      await tester.tap(find.text(card.asset.title));
      await tester.pumpAndSettle();
      expect(creations.single['positionMs'], 4200);
      expect(
        tester
            .widget<MultiplexrPlayer>(find.byType(MultiplexrPlayer))
            .asset
            .collectionId,
        card.asset.collectionId,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(MultiplexrVideoSpace), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Clip',
      );
      expect(scroll.offset, closeTo(offset, .1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
