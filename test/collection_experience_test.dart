import 'package:multiplexr/src/bootstrap/settings_assembly.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/collection/collection_experience.dart';
import 'package:app_shell/app_shell.dart';

import 'reading_ui_parity_test.dart' show ParityDevice;

void main() {
  testWidgets(
    'media selection stays top left in grid and row layouts, including RTL',
    (tester) async {
      for (final row in [false, true]) {
        for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
          var toggles = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: direction,
                child: Center(
                  child: SizedBox(
                    width: 240,
                    child: MediaItemSelection(
                      selected: true,
                      reserveLeading: row,
                      onToggle: () => toggles++,
                      child: const SizedBox(height: 160, width: 240),
                    ),
                  ),
                ),
              ),
            ),
          );
          final item = tester.getRect(find.byType(MediaItemSelection));
          final checkbox = tester.getRect(find.byType(Checkbox));
          expect(checkbox.left - item.left, 4);
          expect(checkbox.top - item.top, 4);
          await tester.tap(find.byType(Checkbox));
          await tester.pump();
          expect(toggles, 1);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/pixelarticons/Pixel Art Icons')..addFont(
          rootBundle.load('packages/pixelarticons/fonts/pixelarticons.ttf'),
        ))
        .load();
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final font = File(
        '${dir.path}/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
      );
      if (font.existsSync()) {
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
        break;
      }
      dir = dir.parent;
    }
  });
  testWidgets('reading collection settings stays in the settings group', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              CollectionActionsMenu(
                onSelected: (value) => selected = value,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'collectionSettings',
                    child: Text('Collection settings'),
                  ),
                  PopupMenuItem(
                    value: 'readerSettings',
                    child: Text('Reader settings'),
                  ),
                  PopupMenuItem(value: 'tags', child: Text('Manage tags')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Collection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Collection settings'), findsOneWidget);
    expect(find.text('Reader settings'), findsOneWidget);
    expect(find.text('Manage tags'), findsNothing);
    await tester.tap(find.text('Collection settings'));
    await tester.pumpAndSettle();
    expect(selected, 'collectionSettings');
  });
  for (final retro in [false, true]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'shared controls narrow retro=$retro dark=$dark text=$scale',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(360, 800);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final settings = createSettingsController(ParityDevice(0, retro));
            await settings.load();
            settings.dark = dark;
            final query = TextEditingController();
            var filters = 0;
            var views = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: settings.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  appBar: AppBar(
                    title: const Text('Books'),
                    bottom: CollectionExperienceHeader(
                      expanded: true,
                      onExpanded: () {},
                      scope: 'My local collection',
                      overview: false,
                      onScope: () {},
                      onOverview: () {},
                      onBrowse: () {},
                    ),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        CollectionBrowseToolbar(
                          query: query,
                          onChanged: (_) {},
                          onFilters: () => filters++,
                          onView: () => views++,
                          count: 0,
                        ),
                        const SizedBox(height: 32),
                        const Icon(Icons.menu_book_outlined, size: 64),
                        const SizedBox(height: 16),
                        const Text('Your books belong here'),
                        const Text(
                          'Add a folder to discover EPUB, TXT and PDF books.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Filters'));
            await tester.tap(find.text('View'));
            expect(filters, 1);
            expect(views, 1);
            await expectLater(
              find.byType(Scaffold),
              matchesGoldenFile(
                'goldens/collection-${retro ? 'retro' : 'modern'}-${dark ? 'dark' : 'light'}-$scale.png',
              ),
            );
            await tester.pumpWidget(const SizedBox());
            query.dispose();
            settings.dispose();
          },
        );
      }
    }
  }
}
