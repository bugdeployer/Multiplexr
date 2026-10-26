import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/library/legacy_video_playback_host.dart';
import 'package:multiplexr/src/bootstrap/app_composition.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/shell.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/library/video_space.dart';
import 'package:multiplexr/src/library/video_art.dart';

import 'global_videos_test.dart' show videosLibrary, VideosStorage;
import 'global_videos_player_test.dart' show mockSurface;

import 'package:multiplexr/src/library/player.dart';
import 'package:multiplexr/src/library/video_scope.dart';

import 'widget_test.dart' show TestDevice;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test(
    'Pixel and violet are defaults and switching style preserves colors',
    () async {
      final device = TestDevice();
      final settings = createSettingsController(device);
      await settings.load();
      expect(settings.pixel, true);
      expect(settings.darkBase, 1);
      expect(settings.darkAccent, 1);
      expect(settings.lightAccent, 7);
      expect(settings.theme.cardTheme.shape, isA<PixelBorder>());
      await settings.appearance(baseChoice: 5, accentChoice: 3);
      await settings.interfaceStyle(false);
      expect(settings.theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(settings.darkBase, 5);
      expect(settings.darkAccent, 3);
      final restored = createSettingsController(device);
      await restored.load();
      expect(restored.pixel, false);
      expect(restored.darkAccent, 3);
      device.failSave = true;
      await expectLater(restored.interfaceStyle(true), throwsException);
      expect(restored.pixel, false);
    },
  );
  test(
    'existing palette preferences are preserved when Pixel becomes default',
    () async {
      final device = TestDevice()
        ..values.addAll({'darkBase': 7, 'darkAccent': 4, 'lightAccent': 2});
      final settings = createSettingsController(device);
      await settings.load();
      expect(settings.pixel, true);
      expect(settings.darkBase, 7);
      expect(settings.darkAccent, 4);
      expect(settings.lightAccent, 2);
    },
  );
  test('pixel outlines retain a usable interior at small and large sizes', () {
    for (final size in [
      const Size(8, 8),
      const Size(48, 48),
      const Size(400, 180),
    ]) {
      final rect = Offset.zero & size;
      final path = const PixelBorder(side: BorderSide(width: 2))
          .getOuterPath(rect);
      expect(path.contains(rect.center), true);
      expect(path.contains(const Offset(.1, .1)), false);
      expect(path.getBounds(), rect);
    }
  });
  testWidgets(
    'Pixel shell contains no promotional headers and style selector works',
    (tester) async {
      final library = await videosLibrary();
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settings,
          builder: (_, _) => MaterialApp(
            theme: settings.theme,
            home: AppShell(
              settings: settings,
              library: library,
              sessions: AppComposition.createSessions(
                settings: settings,
                library: library,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppIcon), findsWidgets);
      expect(find.text('YOUR MEDIA COLLECTION'), findsNothing);
      await tester.tap(find.text('SPACES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('together'), findsNothing);
      expect(find.textContaining('in one place'), findsNothing);
      await tester.tap(find.text('SETTINGS'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('MAKE IT YOURS'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modern').last);
      await tester.pumpAndSettle();
      expect(settings.pixel, false);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Retro').last);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(settings.pixel, true);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Cinema and Videos inherit Pixel in light and dark with large text',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = await videosLibrary();
      final settings = createSettingsController(TestDevice());
      await settings.load();
      for (final dark in [true, false]) {
        settings.dark = dark;
        for (final pixel in [true, false]) {
          await tester.runAsync(
            () => settings.selectTheme(pixel ? 'retro' : 'modern'),
          );
          for (final cinema in [true, false]) {
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey('$dark-$pixel-$cinema'),
                theme: settings.theme,
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(400, 900),
                    textScaler: TextScaler.linear(1.5),
                  ),
                  child: cinema
                      ? MultiplexrCinema(
                          library: library,
                          play: (_, _) async {},
                        )
                      : MultiplexrVideoSpace(library: library),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final context = tester.element(find.byType(Scaffold).first);
            expect(isPixel(context), pixel);
            if (!cinema) expect(find.byType(VideoFeedCard), findsWidgets);
          }
        }
      }
    },
  );
  testWidgets(
    'Pixel player keeps fullscreen and cross-collection queue playback working',
    (tester) async {
      tester.view.physicalSize = const Size(800, 450);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = VideosStorage();
      final library = await videosLibrary(storage: storage);
      final all = videoSpaceItems(library);
      final first = all.firstWhere((a) => a.collectionId == 'a');
      final next = all.firstWhere((a) => a.collectionId == 'b');
      await library.enqueue(next);
      final surfaces = mockSurface();
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: settings.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
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
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      await tester.tap(find.byTooltip('Play next'));
      await tester.pumpAndSettle();
      expect(surfaces.map((s) => s['collectionId']), ['a', 'b']);
      expect(library.queuedVideos, isEmpty);
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      expect(isPixel(tester.element(find.byType(MultiplexrPlayer))), true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
