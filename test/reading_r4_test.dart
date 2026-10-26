import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/reading/comic_reader_controller.dart';
import 'package:multiplexr/src/reading/comic_reader_layout.dart';
import 'package:multiplexr/src/reading/comic_reader_page.dart';
import 'package:multiplexr/src/reading/comic_volume_keys.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_location.dart';
import 'package:multiplexr/src/reading/reading_comic_source.dart';
import 'package:multiplexr/src/reading/reading_repository.dart';
import 'package:multiplexr/src/features/reading/application/reading_session.dart';

Map<String, dynamic> copy(Map<String, dynamic> data) =>
    jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
final fixture = jsonDecode(
  File('test/fixtures/reading-comic-v1.json').readAsStringSync(),
) as Map<String, dynamic>;

class ComicStore implements StateStore {
  Map<String, dynamic> data = copy(fixture['catalog'] as Map<String, dynamic>);
  bool fail = false;
  @override
  Object get persistenceOwner => this;
  @override
  Future<Map<String, dynamic>?> readState(String key) async => copy(data);
  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    if (fail) throw StateError('Failed save');
    data = copy(value!);
  }
}

class ComicSource implements ReadingComicSource {
  List<ComicPage> pages = [
    ComicPage('first', 800, 1200),
    ComicPage('second', 800, 1200),
  ];
  int opens = 0, closes = 0, tiles = 0;
  bool fail = false, failCrop = false;
  Completer<void>? gate;
  static final pixels = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAMCAYAAABfnvydAAAAFUlEQVR4nGNQSJjwHx9mGFXwn04KAF3ExaFExWmvAAAAAElFTkSuQmCC',
    ),
  );
  @override
  Future<List<ComicPage>> open(ReadingTitle title) async {
    opens++;
    return pages;
  }

  @override
  Future<Rect> bounds(String id, bool crop) async {
    if (failCrop) throw StateError('Decode failed');
    final p = pages.singleWhere((p) => p.id == id);
    return crop ? Rect.fromLTRB(20, 20, p.width - 20, p.height - 20) : p.bounds;
  }

  @override
  Future<Uint8List> tile(String id, Rect region, int targetWidth) async {
    tiles++;
    await gate?.future;
    if (fail) throw StateError('Decode failed');
    return pixels;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

class TestVolumeKeys implements ComicVolumeKeys {
  bool enabled = false, closed = false;
  void Function(bool)? turn;
  @override
  Future<void> configure(bool enabled, void Function(bool) turn) async {
    this.enabled = enabled;
    this.turn = turn;
  }

  @override
  Future<void> close() async {
    closed = true;
    enabled = false;
  }
}

class ComicHarness {
  ComicHarness({bool long = false}) {
    if (long) {
      source.pages = [
        ComicPage('first', 1000, 40000),
        ComicPage('second', 800, 1200),
      ];
    }
    repository = ReadingRepository(store);
    title = ReadingCodec.decode(store.data).titles.last;
    controller = ComicReaderController(
      source,
      repository,
      authorized: (_) => allowed,
    );
    session = ReadingSession(
      repository,
      controller,
      authorized: (_) => allowed,
    );
  }
  final store = ComicStore();
  final source = ComicSource();
  final keys = TestVolumeKeys();
  bool allowed = true;
  late final ReadingRepository repository;
  late final ReadingTitle title;
  late final ComicReaderController controller;
  late final ReadingSession session;
  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: Platform.environment.containsKey('READING_R4_VISUAL_FONT')
            ? ThemeData(fontFamily: 'ComicPreview')
            : null,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('comic-capture'),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open comic'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComicReaderPage(
                    title: title,
                    controller: controller,
                    session: session,
                    volumeKeys: keys,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open comic'));
    await settle(tester);
  }
}

Future<void> settle(WidgetTester tester) async {
  // Engine image decoding runs outside the fake test clock.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

class ComicBridge implements PlatformTransport {
  final opened = Completer<String>();
  final nextOpened = Completer<String>();
  int opens = 0;
  final closed = <String>[];
  final cancelled = <String>[];
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (method == 'openReadingComic') {
      return await (++opens == 1 ? opened : nextOpened).future as T;
    }
    if (method == 'closeReadingComic') closed.add(arguments as String);
    if (method == 'cancelReadingComic') cancelled.add(arguments as String);
    return null;
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) async => null;
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('comic-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/reading-r4-$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final path = Platform.environment['READING_R4_VISUAL_FONT'];
    if (path == null) return;
    final loader = FontLoader('ComicPreview')
      ..addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
    await loader.load();
  });
  for (final raw in fixture['cases'] as List) {
    test('comic preference contract: ${raw['name']}', () {
      final catalog = copy(fixture['catalog'] as Map<String, dynamic>);
      catalog['settings'][0]['values'] = raw['values'];
      if (raw['valid'] == true) {
        expect(ReadingCodec.encode(ReadingCodec.decode(catalog)), catalog);
      } else {
        expect(() => ReadingCodec.decode(catalog), throwsA(anything));
      }
    });
  }
  test('stable page and within-page offset survive settings changes and session recreation', () async {
    final h = ComicHarness(long: true);
    await h.session.open(h.title);
    await h.controller.jump(0, withinPage: .65);
    await h.controller.setPreferences({
      'comicMode': 'webtoon',
      'direction': 'rtl',
      'fit': 'width',
    });
    expect(h.controller.offset, .65);
    await h.session.close();
    final next = ComicReaderController(
      h.source,
      h.repository,
      authorized: (_) => true,
    );
    final session = ReadingSession(h.repository, next, authorized: (_) => true);
    await session.open(h.title);
    expect(next.pageIndex, 0);
    expect(next.offset, .65);
    expect(next.rtl, true);
    final position = await next.location();
    expect(position.pageId, 'first');
    await session.close();
    next.dispose();
    h.controller.dispose();
  });
  test('mismatched page identity and unavailable authorization require explicit recovery', () async {
    final h = ComicHarness();
    await expectLater(
      h.controller.open(
        h.title,
        PageReadingLocation(pageId: 'second', pageIndex: 0, offset: .4),
        {},
      ),
      throwsA(isA<ComicLocationRecovery>()),
    );
    expect(h.store.data['progress'], isEmpty);
    h.allowed = false;
    await expectLater(h.controller.open(h.title, null, {}), throwsStateError);
    h.controller.dispose();
  });
  test('long-strip webtoon geometry paints a bounded visible subset and maps original coordinates', () async {
    final h = ComicHarness(long: true);
    await h.session.open(h.title);
    await h.controller.setPreferences({'comicMode': 'webtoon'});
    final layout = ComicReaderLayout(h.controller, const Size(360, 600));
    final origin = layout.originFor(0, .65);
    final (index, fraction) = layout.anchor(origin);
    expect(index, 0);
    expect(fraction, closeTo(.65, .0001));
    final tiles = layout.tiles(Rect.fromLTWH(0, origin.dy, 360, 600), 2, 1);
    expect(
      tiles.length,
      inInclusiveRange(1, ComicReaderLayout.maxVisibleTiles),
    );
    expect(tiles.every((t) => t.page == 0 && t.source.height < 40000), true);
    final rotated = ComicReaderLayout(h.controller, const Size(900, 360));
    expect(rotated.anchor(rotated.originFor(0, .65)).$2, closeTo(.65, .0001));
    await h.session.close();
    h.controller.dispose();
  });
  test('RTL spreads preserve indexed order, keep cover single and turn between pairs', () async {
    final h = ComicHarness();
    final raw = h.store.data['titles'][2] as Map<String, dynamic>;
    raw['readingOrder'] = [
      for (var i = 0; i < 6; i++) {'id': '$i', 'href': '$i.png', 'label': '$i'},
    ];
    final title = ReadingCodec.decode(h.store.data).titles.last;
    h.source.pages = [for (var i = 0; i < 6; i++) ComicPage('$i', 800, 1200)];
    await h.session.open(title);
    await h.controller.setPreferences({
      'spreads': 'landscape',
      'direction': 'rtl',
    });
    expect(h.controller.visiblePages(true), [0]);
    await h.controller.jump(1);
    expect(h.controller.visiblePages(true), [2, 1]);
    expect(h.controller.turnTarget(true, landscape: true), 3);
    await h.controller.jump(4);
    expect(h.controller.turnTarget(false, landscape: true), 2);
    expect(h.controller.visiblePages(false), [4]);
    await h.session.close();
    h.controller.dispose();
  });
  test('tile requests coalesce, cache is bounded, failed requests retry and close invalidates late pixels', () async {
    final h = ComicHarness();
    await h.session.open(h.title);
    const rect = Rect.fromLTWH(0, 0, 800, 200);
    await Future.wait([
      h.controller.tile(0, rect, 512),
      h.controller.tile(0, rect, 512),
    ]);
    expect(h.source.tiles, 1);
    for (var i = 0; i < 20; i++) {
      await h.controller.tile(0, Rect.fromLTWH(0, i * 10, 800, 200), 512);
    }
    expect(h.controller.cachedTiles, lessThanOrEqualTo(8));
    expect(
      h.controller.cachedBytes,
      lessThanOrEqualTo(ComicReaderController.maxCacheBytes),
    );
    h.source.fail = true;
    await expectLater(h.controller.tile(1, rect, 512), throwsStateError);
    h.source.fail = false;
    await h.controller.tile(1, rect, 512);
    h.source.gate = Completer<void>();
    final pending = h.controller.tile(1, Rect.fromLTWH(0, 201, 800, 200), 512);
    final rejected = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await h.controller.close();
    h.source.gate!.complete();
    await rejected;
    expect(h.controller.cachedBytes, 0);
    h.controller.dispose();
  });
  test('crop/settings failures retain the previous durable overrides and reset restores inheritance', () async {
    final h = ComicHarness();
    await h.session.open(h.title);
    h.controller.anchor(1, .4);
    final before = copy(h.store.data);
    h.source.failCrop = true;
    await expectLater(
      h.controller.setPreferences({'cropBorders': true}),
      throwsStateError,
    );
    expect(h.store.data, before);
    h.source.failCrop = false;
    h.store.fail = true;
    await expectLater(
      h.controller.setPreferences({'direction': 'rtl'}),
      throwsStateError,
    );
    expect(h.controller.rtl, false);
    h.store.fail = false;
    await h.controller.setPreferences({
      'direction': 'rtl',
      'cropBorders': true,
    });
    expect(h.controller.bounds(1).left, 20);
    await h.controller.setPreferences({}, reset: true);
    expect(h.controller.rtl, false);
    expect(h.controller.offset, .4);
    h.allowed = false;
    expect(
      () => h.controller.tile(0, const Rect.fromLTWH(0, 0, 10, 10), 512),
      throwsStateError,
    );
    h.allowed = true;
    await h.session.close();
    h.controller.dispose();
  });
  testWidgets(
    'comic page gestures, contents, finished Undo and Back preserve the original route',
    (tester) async {
      final h = ComicHarness();
      await h.show(tester);
      expect(find.byType(RawImage), findsWidgets);
      await tester.drag(find.byType(InteractiveViewer), const Offset(-180, 0));
      await settle(tester);
      expect(h.controller.pageIndex, 1);
      await tester.tap(find.byTooltip('Pages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page 1'));
      await settle(tester);
      expect(h.controller.pageIndex, 0);
      await tester.tap(find.byTooltip('Reader actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark finished'));
      await tester.pumpAndSettle();
      expect(h.session.finished, true);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.session.finished, false);
      ScaffoldMessenger.of(tester.element(find.byType(ComicReaderPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open comic'), findsOneWidget);
      expect(h.keys.closed, true);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'failed Back save keeps the current page and supports retry without replacing progress',
    (tester) async {
      final h = ComicHarness();
      await h.show(tester);
      final before = copy(h.store.data);
      h.store.fail = true;
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving'), findsOneWidget);
      expect(h.store.data, before);
      h.store.fail = false;
      await tester.tap(find.text('Retry save'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Open comic'), findsOneWidget);
    },
  );
  testWidgets(
    'large text, narrow screens, rotation and long-strip zoom retain canonical location',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = ComicHarness(long: true);
      await h.show(tester, scale: 1.8);
      await capture(tester, 'portrait');
      await h.controller.setPreferences({'comicMode': 'webtoon'});
      await settle(tester);
      await tester.fling(
        find.byType(InteractiveViewer),
        const Offset(0, -280),
        1500,
      );
      await settle(tester);
      expect(h.controller.offset, greaterThan(0));
      final anchor = h.controller.offset;
      final viewport = tester.getSize(find.byType(InteractiveViewer));
      final origin = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .toScene(Offset.zero);
      expect(
        anchor,
        closeTo(
          ComicReaderLayout(h.controller, viewport).anchor(origin).$2,
          .00001,
        ),
      );
      tester.view.physicalSize = const Size(640, 360);
      await settle(tester);
      expect(h.controller.offset, anchor);
      await capture(tester, 'landscape');
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await settle(tester);
      expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
      expect(
        find.byType(RawImage).evaluate().length,
        lessThanOrEqualTo(ComicReaderLayout.maxVisibleTiles),
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'settings persist volume navigation only while the reader is active; failure remains retryable',
    (tester) async {
      final h = ComicHarness();
      await h.show(tester);
      await tester.tap(find.byTooltip('Comic reader settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Volume-key navigation'), 200);
      h.store.fail = true;
      await tester.tap(find.text('Volume-key navigation'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save comic settings. Retry your change.'),
        findsWidgets,
      );
      h.store.fail = false;
      await tester.scrollUntilVisible(find.text('Volume-key navigation'), 200);
      await tester.tap(find.text('Volume-key navigation'));
      await tester.pumpAndSettle();
      expect(h.controller.preferences['volumeKeys'], true);
      await tester.pageBack();
      await settle(tester);
      expect(h.keys.enabled, true);
      await tester.tap(find.byTooltip('Reader actions'));
      await tester.pumpAndSettle();
      expect(h.keys.enabled, false);
      await tester.tapAt(const Offset(5, 300));
      await tester.pumpAndSettle();
      expect(h.keys.enabled, true);
      h.keys.turn!(true);
      await settle(tester);
      expect(h.controller.pageIndex, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(h.keys.enabled, false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.keys.enabled, true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(h.keys.closed, true);
    },
  );
  testWidgets(
    'decode failure offers a visible tile retry and leaves progress intact',
    (tester) async {
      final h = ComicHarness();
      h.source.fail = true;
      await h.show(tester);
      expect(find.byTooltip('Retry page image'), findsWidgets);
      expect(h.store.data['progress'], isEmpty);
      h.source.fail = false;
      await tester.tap(find.byTooltip('Retry page image').first);
      await settle(tester);
      expect(find.byType(RawImage), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test('fit width and crop geometry preserve image proportions and original within-page offsets', () async {
    final h = ComicHarness(long: true);
    await h.session.open(h.title);
    final page = ComicReaderLayout(h.controller, const Size(360, 600));
    expect(page.placements.single.destination.height, 600);
    await h.controller.setPreferences({'fit': 'width', 'cropBorders': true});
    final cropped = ComicReaderLayout(h.controller, const Size(360, 600));
    final p = cropped.placements.single;
    expect(
      p.destination.width / p.destination.height,
      closeTo(p.source.width / p.source.height, .00001),
    );
    expect(cropped.anchor(cropped.originFor(0, .4)).$2, closeTo(.4, .00001));
    await h.session.close();
    h.controller.dispose();
  });
  testWidgets(
    'RTL and inverted tap zones advance in the configured direction and pinch does not turn pages',
    (tester) async {
      final h = ComicHarness();
      await h.show(tester);
      await h.controller.setPreferences({'direction': 'rtl'});
      await settle(tester);
      final box = tester.getRect(find.byType(InteractiveViewer));
      await tester.tapAt(Offset(box.left + 30, box.center.dy));
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(h.controller.pageIndex, 1);
      await h.controller.jump(0);
      await h.controller.setPreferences({'tapZones': 'inverted'});
      await settle(tester);
      await tester.tapAt(Offset(box.right - 30, box.center.dy));
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(h.controller.pageIndex, 1);
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final first = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveTo(center - const Offset(100, 0));
      await second.moveTo(center + const Offset(100, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await settle(tester);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1),
      );
      expect(h.controller.pageIndex, 1);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test('superseded navigation cannot replace a newer page selection', () async {
    final h = ComicHarness();
    await h.session.open(h.title);
    final old = h.controller.jump(0, withinPage: .8);
    final rejected = expectLater(old, throwsStateError);
    final latest = h.controller.jump(1, withinPage: .2);
    await latest;
    await rejected;
    expect(h.controller.pageIndex, 1);
    expect(h.controller.offset, .2);
    await h.session.close();
    h.controller.dispose();
  });
  test('native source cancellation closes a late handle instead of leaking or reopening it', () async {
    final h = ComicHarness();
    final bridge = ComicBridge();
    final source = NativeReadingComicSource(LibraryService(transport: bridge));
    final opened = source.open(h.title);
    final rejected = expectLater(opened, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await source.close();
    bridge.opened.complete(
      jsonEncode({
        'token': 'late-handle',
        'pages': [
          {'id': 'first', 'width': 10, 'height': 10},
        ],
      }),
    );
    await rejected;
    expect(bridge.closed, ['late-handle']);
    expect(bridge.cancelled, hasLength(1));
    h.controller.dispose();
  });
  test(
    'a superseded source open cannot close the latest native handle',
    () async {
      final h = ComicHarness();
      final bridge = ComicBridge();
      final source = NativeReadingComicSource(
        LibraryService(transport: bridge),
      );
      final old = source.open(h.title);
      final rejected = expectLater(old, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final latest = source.open(h.title);
      await Future<void>.delayed(Duration.zero);
      bridge.nextOpened.complete(
        jsonEncode({
          'token': 'new',
          'pages': [
            {'id': 'first', 'width': 10, 'height': 10},
          ],
        }),
      );
      await latest;
      bridge.opened.complete(
        jsonEncode({
          'token': 'old',
          'pages': [
            {'id': 'first', 'width': 10, 'height': 10},
          ],
        }),
      );
      await rejected;
      expect(bridge.closed, ['old']);
      await source.close();
      expect(bridge.closed, ['old', 'new']);
      h.controller.dispose();
    },
  );
  test('large-page zoom tiles cover the visible area without decoding the full image', () async {
    final h = ComicHarness();
    h.source.pages = [
      ComicPage('first', 10000, 10000),
      ComicPage('second', 800, 1200),
    ];
    await h.session.open(h.title);
    for (final viewport in [
      const Size(360, 640),
      const Size(900, 360),
      const Size(1440, 2560),
    ]) {
      final layout = ComicReaderLayout(h.controller, viewport);
      final visible = Rect.fromCenter(
        center: layout.placements.first.destination.center,
        width: viewport.width / 4,
        height: viewport.height / 4,
      );
      final tiles = layout.tiles(visible, 3, 4);
      final expected = layout.placements.first.destination.intersect(visible);
      final area = tiles.fold<double>(0, (sum, tile) {
        final r = tile.destination.intersect(visible);
        return sum + r.width * r.height;
      });
      expect(area, closeTo(expected.width * expected.height, .001));
      expect(
        tiles.length,
        lessThanOrEqualTo(ComicReaderLayout.maxVisibleTiles),
      );
      expect(
        tiles.every(
          (tile) => tile.source.width < 10000 && tile.source.height < 10000,
        ),
        true,
      );
    }
    await h.session.close();
    h.controller.dispose();
  });
  test('comic renderer has final production reading bindings', () {
    expect(appSubtypes.definition(MediaSubtype.comics).enabled, true);
    expect(appSubtypes.definition(MediaSubtype.ebook).enabled, true);
  });
}
