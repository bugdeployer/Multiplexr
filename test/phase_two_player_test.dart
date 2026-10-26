import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/library/legacy_video_playback_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/player.dart';

import 'library_test.dart' show MemoryLibrary;
import 'phase_two_test.dart' show episode;

class PlaybackLibrary extends MemoryLibrary {
  final positions = <String, List<int>>{};
  @override
  Future<void> position(VideoAsset asset, int point) async {
    positions.putIfAbsent(asset.id, () => []).add(point);
  }

  @override
  Future<void> watchState(VideoAsset asset, String action) async {}
}

void main() {
  for (final movies in [false, true]) {
    testWidgets(
      movies ? 'TV autoplay keeps landscape playback and advances one episode' : 'Videos queue advances without saving the new position on the old file',
      (tester) async {
        tester.view.physicalSize = const Size(800, 450);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = PlaybackLibrary();
        service.collections.add(
          VideoCollection(
            id: 'c',
            name: 'C',
            subtype: movies ? VideoSubtype.cinema : VideoSubtype.videos,
            autoplayNext: movies,
          ).toJson(),
        );
        final a = episode('a', 1, 1), b = episode('b', 1, 2);
        service.assets.addAll([a.toJson(), b.toJson()]);
        final library = createLibraryController(service);
        await library.load();
        if (!movies) await library.enqueue(b);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final channels = <MethodChannel>[];
        var creates = 0;
        messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (_) async => null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          final data = call.arguments as Map;
          if (call.method == 'create') {
            creates++;
            final complete = creates == 1;
            final channel = MethodChannel('multiplexr/player/${data['id']}');
            channels.add(channel);
            messenger.setMockMethodCallHandler(
              channel,
              (call) async => call.method == 'state'
                  ? {
                      'positionMs': complete ? 10000 : 4000,
                      'durationMs': 10000,
                      'completed': complete,
                      'playing': false,
                    }
                  : null,
            );
            return creates;
          }
          if (call.method == 'resize') {
            return {'width': data['width'], 'height': data['height']};
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          for (final channel in channels) {
            messenger.setMockMethodCallHandler(channel, null);
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            home: MultiplexrPlayer(
              asset: a,
              host: LegacyVideoPlaybackHost(service),
              watchPage: !movies,
              landscapeOnly: movies,
              library: library,
              related: [a, b],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final player = tester.widget<MultiplexrPlayer>(
          find.byType(MultiplexrPlayer),
        );
        expect(player.asset.id, 'b');
        expect(player.watchPage, !movies);
        expect(player.landscapeOnly, movies);
        expect(creates, 2);
        expect(service.positions['a'], everyElement(10000));
        expect(library.queuedVideos, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
