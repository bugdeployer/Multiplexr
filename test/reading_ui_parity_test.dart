import 'package:multiplexr/src/reading/domain/reading_index.dart';
import 'package:multiplexr/src/reading/domain/reading_management.dart';
import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/bootstrap/reading_assembly.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/main.dart';
import 'package:multiplexr/src/platform_service.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:app_shell/app_shell.dart';

import 'reading_r5_test.dart'
    show ReadingWorkflowTransport, ReadingWorkflowHarness;

import 'package:multiplexr/src/reading/reading_collection_page.dart';
import 'package:multiplexr/src/reading/reading_management_pages.dart';
import 'package:multiplexr/src/reading/reading_space.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/features/catalog/application/space_queries.dart';
import 'package:multiplexr/src/media/media_ui_patterns.dart';

class MixedLibrary extends LibraryService {
  MixedLibrary() : super(transport: ReadingWorkflowTransport());
  @override
  Future<Map<String, dynamic>> load() async => {
    'collections': [
      const VideoCollection(
        id: 'movies',
        name: 'Movies',
        subtype: VideoSubtype.cinema,
      ).toJson(),
      const VideoCollection(
        id: 'videos',
        name: 'YouTube',
        subtype: VideoSubtype.videos,
      ).toJson(),
    ],
    'assets': [],
    'series': [],
    'seasons': [],
    'episodes': [],
  };
}

class ParityDevice extends PlatformService {
  ParityDevice(this.view, this.retro);
  final int view;
  final bool retro;
  @override
  Future<Map<String, dynamic>> load() async => {
    'supported': true,
    'libraryView': view,
    'pixel': retro,
  };
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final pixel = FontLoader('packages/pixelarticons/Pixel Art Icons')
      ..addFont(
        rootBundle.load('packages/pixelarticons/fonts/pixelarticons.ttf'),
      );
    await pixel.load();
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final file = File(
        '${dir.path}/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
      );
      if (file.existsSync()) {
        final font = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        await font.load();
        break;
      }
      dir = dir.parent;
    }
  });
  for (final retro in [false, true]) {
    for (final view in [0, 1, 2]) {
      testWidgets('mixed library uses one layout view=$view retro=$retro', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(430, 932);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MultiplexrApp(
              platform: ParityDevice(view, retro),
              libraryService: MixedLibrary(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final movie = find.byKey(const ValueKey('library-collection:movies'));
        final book = find.byKey(const ValueKey('library-collection:books:[]'));
        final comics = find.byKey(const ValueKey('library-collection:comics'));
        expect(movie, findsOneWidget);
        expect(book, findsOneWidget);
        expect(comics, findsOneWidget);
        expect(tester.getSize(book).width, tester.getSize(movie).width);
        expect(tester.getSize(comics).width, tester.getSize(movie).width);
        if (view == 1) {
          expect(tester.getSize(book), tester.getSize(movie));
          expect(tester.getSize(comics), tester.getSize(movie));
          expect(tester.getSize(book).width, lessThan(215));
          expect(
            find.descendant(of: book, matching: find.byType(ListTile)),
            findsNothing,
          );
          expect(tester.getTopLeft(book).dx, tester.getTopLeft(movie).dx);
        } else {
          expect(
            find.descendant(of: book, matching: find.byType(ListTile)),
            findsOneWidget,
          );
        }
        expect(find.text('No collections'), findsNothing);
        expect(tester.takeException(), null);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/reading-parity/library-${retro ? 'retro' : 'modern'}-$view.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets(
    'reading screens reuse details, series, settings and space patterns',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final h = ReadingWorkflowHarness();
      final settings = createSettingsController(ParityDevice(1, false));
      await settings.load();
      final app = createReadingAppController(
        h.service,
        authenticate: () async => true,
        appBlocked: () => false,
      );
      await app.load();
      Future<void> render(String name, Widget child) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: settings.theme,
              home: child,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('build/reading-parity/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await render(
        'details',
        ReadingTitleDetailsPage(
          library: h.library,
          identity: h.book,
          actions: (_) async {},
          open: () async {},
        ),
      );
      expect(find.byType(MediaDetailsBody), findsOneWidget);
      expect(find.textContaining('internal resources'), findsNothing);
      expect(find.text('Edit metadata'), findsNothing);
      await tester.tap(find.byTooltip('Title actions'));
      await tester.pumpAndSettle();
      final labels = [
        'Settings',
        'Edit metadata',
        'Choose artwork',
        'Find metadata online',
      ];
      for (var i = 1; i < labels.length; i++) {
        expect(
          tester.getTopLeft(find.text(labels[i])).dy,
          greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        );
      }
      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Read'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await render(
        'series',
        ReadingCollectionPage(
          library: h.library,
          collectionId: 'books:[]',
          groupId: CatalogIdentity('books:[]', 'saga', CatalogEntityKind.group),
        ),
      );
      expect(find.byType(MediaDetailsBody), findsOneWidget);
      expect(find.byTooltip('Collection settings'), findsNothing);
      await render(
        'collection-settings',
        ReadingCollectionSettingsPage(
          library: h.library,
          collectionId: 'books:[]',
        ),
      );
      expect(find.text('Collection settings'), findsOneWidget);
      await render(
        'space',
        ReadingSpace(app: app, scope: const SpaceScope(MediaSubtype.ebook)),
      );
      expect(find.byType(MediaRail), findsWidgets);
      expect(find.byTooltip('Application reader defaults'), findsNothing);
      await tester.tap(find.byTooltip('Space settings'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      h.transport.fail = true;
      await tester.ensureVisible(
        find.widgetWithText(SwitchListTile, 'Show counts'),
      );
      await tester.tap(find.widgetWithText(SwitchListTile, 'Show counts'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save space settings. Retry.'),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      app.dispose();
      settings.dispose();
    },
  );
  testWidgets(
    'shared reading settings save preserves titles and removal clears every owned document atomically',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final before = await h.library.read();
      Future<void> openSettings() async {
        await h.show(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingCollectionSettingsPage(
                      library: h.library,
                      collectionId: 'books:[]',
                    ),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open settings'));
        await tester.pumpAndSettle();
      }

      await openSettings();
      await tester.enterText(find.byType(TextFormField).first, 'Books');
      await tester.scrollUntilVisible(
        find.text('Save collection'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      h.transport.fail = true;
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the collection. Try again.'),
        findsOneWidget,
      );
      expect(
        (await h.library.read()).catalog.collections.first.name,
        before.catalog.collections.first.name,
      );
      h.transport.fail = false;
      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      final saved = await h.library.read();
      expect(saved.catalog.collections.first.name, 'Books');
      expect(saved.catalog.titles.length, before.catalog.titles.length);
      expect(
        saved.catalog.titles.first.catalog.metadata.toJson(),
        before.catalog.titles.first.catalog.metadata.toJson(),
      );
      expect(saved.catalog.progress.length, before.catalog.progress.length);
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Remove collection'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Remove collection'),
      );
      await tester.pumpAndSettle();
      h.transport.fail = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Remove collection'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not remove the collection. Try again.'),
        findsOneWidget,
      );
      expect(
        (await h.library.read()).catalog.collections.any(
          (c) => c.id == 'books:[]',
        ),
        true,
      );
      h.transport.fail = false;
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Remove collection'),
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Remove collection'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove collection'));
      await tester.pumpAndSettle();
      final removed = await h.library.read();
      expect(removed.catalog.collections.any((c) => c.id == 'books:[]'), false);
      expect(
        removed.catalog.titles.any(
          (t) => t.catalog.id.collectionId == 'books:[]',
        ),
        false,
      );
      expect(removed.catalog.collections.any((c) => c.id == 'comics'), true);
      for (final doc in [
        h.transport.state[ReadingIndex.key]!,
        h.transport.state[ReadingManagement.key]!,
      ]) {
        for (final rows in doc.values.whereType<List>()) {
          expect(
            rows.where((r) => r is Map && r['collectionId'] == 'books:[]'),
            isEmpty,
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
