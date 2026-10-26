import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/reading/domain/reading_annotations.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_location.dart';
import 'package:multiplexr/src/reading/reading_annotations_repository.dart';
import 'package:multiplexr/src/reading/reading_repository.dart';
import 'package:multiplexr/src/features/reading/application/reading_session.dart';
import 'package:multiplexr/src/reading/reading_text_source.dart';
import 'package:multiplexr/src/reading/text_reader_controller.dart';
import 'package:multiplexr/src/reading/text_reader_layout.dart';
import 'package:multiplexr/src/reading/text_reader_page.dart';

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
Map<String, dynamic> _catalog() {
  final result =
      (jsonDecode(File('test/fixtures/reading-v1.json').readAsStringSync())
              as Map<String, dynamic>)['base']
          as Map<String, dynamic>;
  result['progress'] = [];
  return result;
}

class TextReaderStore implements StateStore {
  final values = <String, Map<String, dynamic>>{ReadingCodec.key: _catalog()};
  bool failWrites = false;
  @override
  Object get persistenceOwner => this;
  @override
  Future<Map<String, dynamic>?> readState(String key) async =>
      values[key] == null ? null : _copy(values[key]!);
  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    if (failWrites) throw StateError('Failed save');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = _copy(value);
    }
  }
}

class FakeTextSource implements ReadingTextSource {
  final texts = <String, ReadingTextResource>{
    'first': ReadingTextResource(
      text:
          'Reader heading\n\n${'A paragraph with searchable words and emoji 👩🏽‍🚀.\n\n' * 300}',
      anchors: {'paragraph': 0},
    ),
    'second': ReadingTextResource(
      text: 'The second chapter contains a secret phrase. ' * 80,
    ),
  };
  int opens = 0, closes = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> open(ReadingTitle title) async {
    opens++;
    if (fail) throw StateError('Offline source failed');
  }

  @override
  Future<ReadingTextResource> resource(String id) async {
    await gate?.future;
    return texts[id]!;
  }

  @override
  Future<List<ReadingSearchResult>> search(String query) async => [
    for (final entry in texts.entries)
      if (entry.value.text.contains(query))
        ReadingSearchResult(
          entry.key,
          entry.value.text.indexOf(query),
          query,
          'Result in ${entry.key}: $query',
        ),
  ];
  @override
  Future<void> cancel() async {}
  @override
  Future<List<ReadingContentsEntry>> contents() async => const [
    ReadingContentsEntry('first', 'First', anchor: 'paragraph'),
    ReadingContentsEntry('second', 'Second'),
  ];
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<void> textAction(String action, String text) async {}
}

class ReaderHarness {
  ReaderHarness() {
    repository = ReadingRepository(store);
    title = ReadingCodec.decode(store.values[ReadingCodec.key]!).titles.first;
    controller = TextReaderController(
      source,
      repository,
      authorized: (_) => allowed,
    );
    session = ReadingSession(
      repository,
      controller,
      authorized: (_) => allowed,
    );
    annotations = ReadingAnnotationsRepository(
      store,
      authorized: (_) => allowed,
    );
  }
  final store = TextReaderStore();
  final source = FakeTextSource();
  bool allowed = true;
  late final ReadingRepository repository;
  late final ReadingTitle title;
  late final TextReaderController controller;
  late final ReadingSession session;
  late final ReadingAnnotationsRepository annotations;
  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open reader'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TextReaderPage(
                    title: title,
                    controller: controller,
                    session: session,
                    annotations: annotations,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open reader'));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/reading-annotations-v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final testCase in fixture['cases'] as List) {
    test('Dart/native annotation fixture: ${testCase['name']}', () {
      final data = _copy(fixture['annotations'] as Map<String, dynamic>);
      dynamic target = data;
      final path = testCase['path'] as List;
      for (final part in path.take(path.length - 1)) {
        target = target[part];
      }
      if (target is List && (path.last as int) == target.length) {
        target.add(testCase['value']);
      } else {
        target[path.last] = testCase['value'];
      }
      final catalog = ReadingCodec.decode(
        fixture['catalog'] as Map<String, dynamic>,
      );
      if (testCase['valid'] == true) {
        expect(
          ReadingAnnotationCodec.encode(
            ReadingAnnotationCodec.decode(data, catalog),
          ),
          data,
        );
      } else {
        expect(
          () => ReadingAnnotationCodec.decode(data, catalog),
          throwsA(anything),
        );
      }
    });
  }
  test('actual text adapter saves and restores a canonical offset across controller recreation and typography changes', () async {
    final h = ReaderHarness();
    await h.session.open(h.title);
    h.controller.setOffset(329);
    await h.controller.setPreferences({
      'fontSize': 28.0,
      'fontWeight': 700,
      'textMode': 'scroll',
      'paragraphSpacing': 16.0,
    });
    expect(h.controller.offset, 329);
    await h.session.close();
    final restored = TextReaderController(
      FakeTextSource(),
      h.repository,
      authorized: (_) => true,
    );
    final session = ReadingSession(
      h.repository,
      restored,
      authorized: (_) => true,
    );
    await session.open(h.title);
    expect(restored.offset, 329);
    expect(restored.preferences['fontSize'], 28.0);
    expect((await restored.location()).locatorType, TextLocatorType.textOffset);
    await session.close();
    restored.dispose();
    h.controller.dispose();
  });
  test('unresolvable CFI and out-of-range offsets require recovery instead of starting at zero', () async {
    final h = ReaderHarness();
    for (final position in [
      TextReadingLocation(
        resourceId: 'first',
        locatorType: TextLocatorType.epubCfi,
        locator: 'epubcfi(/6/2)',
        progression: .3,
      ),
      TextReadingLocation(
        resourceId: 'first',
        locatorType: TextLocatorType.textOffset,
        locator: '9999999',
        progression: .3,
      ),
    ]) {
      await expectLater(
        h.controller.open(h.title, position, {'fontSize': 18.0}),
        throwsA(isA<TextLocationRecovery>()),
      );
    }
    expect(h.store.values[ReadingCodec.key]!['progress'], isEmpty);
    h.controller.dispose();
  });
  test('bounded layout preserves the text stream and reflows an anchored page without processing a whole long resource', () {
    final resource = ReadingTextResource(
      text: 'Long text with words and emoji 🚀.\n\n' * 40000,
      styles: [
        {'start': 0, 'end': 20, 'kind': 'heading'},
      ],
    );
    final small = TextReaderLayout(
      resource,
      const TextStyle(fontSize: 18, height: 1.5, color: Colors.black),
      TextScaler.noScaling,
      TextDirection.ltr,
      TextAlign.start,
      8,
    );
    final large = TextReaderLayout(
      resource,
      const TextStyle(fontSize: 30, height: 1.8, color: Colors.black),
      const TextScaler.linear(1.8),
      TextDirection.ltr,
      TextAlign.justify,
      16,
    );
    final start = 500;
    final firstEnd = small.pageEnd(start, 320, 400),
        secondEnd = large.pageEnd(start, 320, 400);
    expect(firstEnd, greaterThan(start));
    expect(secondEnd, lessThan(firstEnd));
    expect(
      small.span(start, firstEnd).toPlainText(),
      resource.text.substring(start, firstEnd),
    );
    expect(firstEnd - start, lessThanOrEqualTo(TextReaderLayout.maxWindow));
    final previous = small.pageBefore(firstEnd, 320, 400);
    expect(previous, lessThan(firstEnd));
    expect(TextReaderController.safeOffset('a🚀b', 2), 1);
    final palette = ReaderPalette.resolve({
      'palette': 'custom',
      'readerBackground': 0xff000000,
      'readerForeground': 0xff000000,
    }, ColorScheme.fromSeed(seedColor: Colors.blue));
    expect(
      ReaderPalette.contrast(palette.background, palette.foreground),
      greaterThanOrEqualTo(4.5),
    );
  });
  test('annotation saves are independent of progress; concurrent edits merge and failed writes retain the previous notes', () async {
    final h = ReaderHarness();
    final raw = fixture['annotations']['items'][0] as Map<String, dynamic>;
    final first = ReadingAnnotation.fromJson(raw),
        second = ReadingAnnotation.fromJson({...raw, 'id': 'second'});
    final other = ReadingAnnotationsRepository(
      h.store,
      authorized: (_) => true,
    );
    await Future.wait([h.annotations.save(first), other.save(second)]);
    expect((await h.annotations.read()).length, 2);
    expect(h.store.values[ReadingCodec.key]!['progress'], isEmpty);
    h.store.failWrites = true;
    await expectLater(other.remove(first), throwsStateError);
    expect((await other.read()).length, 2);
    h.store.failWrites = false;
    h.allowed = false;
    await expectLater(h.annotations.remove(first), throwsStateError);
    expect(await h.annotations.read(), isEmpty);
    h.controller.dispose();
  });
  testWidgets(
    'reader changes pages, searches contents and returns to its original route',
    (tester) async {
      final h = ReaderHarness();
      await h.show(tester);
      expect(find.byType(SelectableText), findsOneWidget);
      final span = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      expect(
        span.toPlainText().length,
        lessThan(h.source.texts['first']!.text.length),
      );
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(h.controller.offset, greaterThan(0));
      await tester.tap(find.byTooltip('Contents and settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contents'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(h.controller.offset, 0);
      await tester.tap(find.byTooltip('Search publication'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Result in second: secret'));
      await tester.pumpAndSettle();
      expect(h.controller.resourceId, 'second');
      expect(h.controller.offset, 30);
      await tester.tap(find.byTooltip('Reader actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark finished'));
      await tester.pumpAndSettle();
      expect(h.session.finished, true);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(h.session.finished, false);
      ScaffoldMessenger.of(tester.element(find.byType(TextReaderPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();
      expect(find.text('Open reader'), findsOneWidget);
      expect(h.store.values[ReadingCodec.key]!['progress'].length, 1);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'failed Back save keeps the reader open with retry and preserves the saved snapshot',
    (tester) async {
      final h = ReaderHarness();
      await h.show(tester);
      final before = _copy(h.store.values[ReadingCodec.key]!);
      h.store.failWrites = true;
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Leave without saving'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(h.store.values[ReadingCodec.key], before);
      h.store.failWrites = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving'), findsNothing);
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();
      expect(find.text('Open reader'), findsOneWidget);
    },
  );
  testWidgets(
    'narrow large-text reader and keyboard search fit; font and rotation preserve the anchor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = ReaderHarness();
      await h.show(tester, scale: 1.8);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      final anchor = h.controller.offset;
      await h.controller.setPreferences({
        'fontSize': 30.0,
        'textMode': 'scroll',
      });
      await tester.pumpAndSettle();
      expect(h.controller.offset, anchor);
      tester.view.physicalSize = const Size(640, 360);
      await tester.pumpAndSettle();
      expect(h.controller.offset, anchor);
      expect(tester.takeException(), null);
      await tester.tap(find.byTooltip('Search publication'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 160);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.text('No matches. Try another search.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'bookmarks persist and failed note saves retain the draft until retry succeeds',
    (tester) async {
      final h = ReaderHarness();
      await h.show(tester);
      await tester.tap(find.byTooltip('Add bookmark'));
      await tester.pumpAndSettle();
      expect(
        (await h.annotations.read()).single.kind,
        ReadingAnnotationKind.bookmark,
      );
      final point =
          tester.getTopLeft(find.byType(SelectableText)) + const Offset(25, 12);
      await tester.longPressAt(point);
      await tester.pumpAndSettle();
      expect(find.text('Add note'), findsOneWidget);
      await tester.tap(find.text('Add note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A retained draft');
      h.store.failWrites = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save this note. Your draft is retained.'),
        findsOneWidget,
      );
      expect(find.text('A retained draft'), findsOneWidget);
      h.store.failWrites = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        (await h.annotations.read())
            .where((a) => a.kind == ReadingAnnotationKind.note)
            .single
            .note,
        'A retained draft',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test('contents anchors resolve and revoked access prevents search and settings writes', () async {
    final h = ReaderHarness();
    await h.session.open(h.title);
    final entries = await h.controller.contents();
    await h.controller.jump(
      entries.first.resourceId,
      30,
      anchor: entries.first.anchor,
    );
    expect(h.controller.offset, 0);
    await expectLater(
      h.controller.jump('first', 0, anchor: 'missing'),
      throwsA(isA<TextLocationRecovery>()),
    );
    h.allowed = false;
    await expectLater(h.controller.search('secret'), throwsStateError);
    await expectLater(h.controller.contents(), throwsStateError);
    await expectLater(
      h.controller.setPreferences({'fontSize': 28.0}),
      throwsStateError,
    );
    h.allowed = true;
    h.controller.setOffset(80);
    final old = _copy(h.store.values[ReadingCodec.key]!);
    h.store.failWrites = true;
    await expectLater(
      h.controller.setPreferences({'fontSize': 32.0}),
      throwsStateError,
    );
    expect(h.store.values[ReadingCodec.key], old);
    expect(h.controller.preferences['fontSize'], 20.0);
    h.store.failWrites = false;
    await h.controller.setPreferences({'fontSize': 32.0});
    await h.controller.setPreferences({}, reset: true);
    expect(h.controller.preferences['fontSize'], 20.0);
    expect(h.controller.offset, 80);
    await h.session.close();
    h.controller.dispose();
  });
  test('reader features have final production bindings', () {
    expect(appSubtypes.definition(MediaSubtype.ebook).enabled, true);
    expect(appSubtypes.definition(MediaSubtype.comics).enabled, true);
  });
}
