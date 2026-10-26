import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/bootstrap/app_composition.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/shell.dart';

import 'global_videos_test.dart' show videosLibrary;
import 'widget_test.dart' show TestDevice;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test(
    'home layout preferences persist independently and survive failed writes',
    () async {
      final device = TestDevice();
      final settings = createSettingsController(device);
      await settings.load();
      await settings.setHomeView(spaces: false, value: 1);
      await settings.setHomeView(spaces: true, value: 2);
      final restored = createSettingsController(device);
      await restored.load();
      expect(restored.libraryView, 1);
      expect(restored.spacesView, 2);
      device.failSave = true;
      await expectLater(
        restored.setHomeView(spaces: true, value: 0),
        throwsException,
      );
      expect(restored.spacesView, 2);
    },
  );
  testWidgets(
    'all home layouts fit a narrow phone and keep private counts hidden',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = await videosLibrary();
      library.collections.add(
        const VideoCollection(
          id: 'audio',
          name: 'Books',
          kind: MediaKind.audiobook,
          subtype: VideoSubtype.videos,
          roots: [],
          extensions: ['m4b'],
          view: CatalogView.list,
        ),
      );
      final settings = createSettingsController(TestDevice());
      await settings.load();
      for (final mode in [0, 1, 2]) {
        settings.libraryView = mode;
        settings.spacesView = mode;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(mode),
            home: AppShell(
              settings: settings,
              library: library,
              sessions: AppComposition.createSessions(
                settings: settings,
                library: library,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Locked'), findsWidgets);
        await tester.tap(find.text('SPACES'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('PRIVATE'), findsNothing);
      }
    },
  );
  testWidgets(
    'home and settings remain usable with 200 percent text and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = await videosLibrary();
      library.collections.add(
        const VideoCollection(
          id: 'audio',
          name: 'Books',
          kind: MediaKind.audiobook,
          subtype: VideoSubtype.videos,
          roots: [],
          extensions: ['m4b'],
          view: CatalogView.list,
        ),
      );
      final settings = createSettingsController(TestDevice())
        ..reduceMotion = true;
      await settings.load();
      settings.reduceMotion = true;
      for (final mode in [0, 1, 2]) {
        settings.libraryView = mode;
        settings.spacesView = mode;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('large-$mode'),
            theme: settings.theme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: AppShell(
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
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('SPACES'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('SETTINGS'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
