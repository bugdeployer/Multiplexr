import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/catalog/domain/group_repository.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/reading/domain/reader_adapter.dart';
import 'package:multiplexr/src/reading/domain/reader_settings.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_location.dart';
import 'package:multiplexr/src/reading/reading_repository.dart';
import 'package:multiplexr/src/features/reading/application/reading_session.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';

Map<String, dynamic> copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
final fixture = jsonDecode(
  File('test/fixtures/reading-v1.json').readAsStringSync(),
) as Map<String, dynamic>;
Map<String, dynamic> base() => copy(fixture['base'] as Map<String, dynamic>);

void patch(Map<String, dynamic> data, Map<String, dynamic> patch) {
  final path = patch['path'] as List;
  dynamic parent = data;
  for (final part in path.take(path.length - 1)) {
    parent = parent[part];
  }
  final key = path.last;
  if (patch['op'] == 'remove') {
    if (parent is List) {
      parent.removeAt(key as int);
    } else {
      (parent as Map).remove(key);
    }
  } else {
    parent[key] = patch['value'];
  }
}

class ReadingStore implements StateStore {
  Map<String, dynamic>? value;
  bool fail = false;
  Completer<void>? readGate;
  @override
  Object get persistenceOwner => this;
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    expect(key, ReadingCodec.key);
    await readGate?.future;
    return value;
  }

  @override
  Future<void> writeState(String key, Map<String, dynamic>? next) async {
    expect(key, ReadingCodec.key);
    if (fail) throw StateError('Storage unavailable');
    value = next == null ? null : copy(next);
  }
}

class FakeReader implements ReaderAdapter {
  @override
  String get id => 'fake-text';
  @override
  MediaSubtype get subtype => MediaSubtype.ebook;
  @override
  Set<ReadingFormat> get formats => {ReadingFormat.epub, ReadingFormat.txt};
  @override
  Set<ReaderCapability> get capabilities => {
    ReaderCapability.reflow,
    ReaderCapability.contents,
  };
  ReadingLocation current = TextReadingLocation(
    resourceId: 'first',
    locatorType: TextLocatorType.cssSelector,
    locator: '#start',
    progression: 0,
  );
  ReadingLocation? restored;
  Map<String, Object>? preferences;
  int opens = 0, closes = 0;
  Completer<void>? gate;
  bool failOpen = false;
  @override
  Future<void> open(
    ReadingTitle title,
    ReadingLocation? restore,
    Map<String, Object> settings,
  ) async {
    opens++;
    restored = restore;
    preferences = settings;
    await gate?.future;
    if (failOpen) throw StateError('Renderer failed');
    current = restore ?? current;
  }

  @override
  Future<ReadingLocation> location() async => current;
  @override
  Future<void> close() async {
    closes++;
  }
}

class FakeTextReader extends FakeReader implements TextReaderAdapter {}

class FakeComicReader extends FakeReader implements ComicReaderAdapter {
  @override
  MediaSubtype get subtype => MediaSubtype.comics;
  @override
  Set<ReadingFormat> get formats => {ReadingFormat.cbz, ReadingFormat.images};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('TXT and image directories retain the same title and internal reading order', () {
    final input = base();
    input['titles'][0]['format'] = 'txt';
    input['titles'][2]['format'] = 'images';
    final catalog = ReadingCodec.decode(input);
    expect(catalog.titles.first.format, ReadingFormat.txt);
    expect(catalog.titles.last.format, ReadingFormat.images);
    expect(ReadingCodec.encode(catalog), input);
  });

  test('reading snapshots respect the native state size limit', () {
    final input = base();
    input['titles'][0]['readingOrder'] = [
      for (var i = 0; i < 2600; i++)
        {'id': '$i', 'href': '$i.xhtml', 'label': 'x' * 4096},
    ];
    expect(() => ReadingCodec.decode(input), throwsFormatException);
  });

  test('comic session uses page locations and subtype settings through the same lifecycle', () async {
    final store = ReadingStore()..value = base();
    final repository = ReadingRepository(store), renderer = FakeComicReader();
    final session = ReadingSession(
      repository,
      renderer,
      authorized: (_) => true,
    );
    final title = (await repository.read()).titles.last;
    await session.open(title);
    expect(renderer.restored, isA<PageReadingLocation>());
    expect(renderer.preferences!['direction'], 'rtl');
    renderer.current = PageReadingLocation(
      pageId: 'first',
      pageIndex: 0,
      offset: .2,
    );
    await session.close();
    final saved = (await repository.read()).progress.last;
    expect((saved.location as PageReadingLocation).pageId, 'first');
    expect(saved.finished, false);
  });
  for (final raw in fixture['cases'] as List) {
    final testCase = raw as Map<String, dynamic>;
    test('Dart/native reading wire fixture: ${testCase['name']}', () {
      final input = base();
      for (final operation in testCase['patches'] as List) {
        patch(input, operation as Map<String, dynamic>);
      }
      if (testCase['valid'] == true) {
        final decoded = ReadingCodec.decode(input);
        expect(ReadingCodec.encode(decoded), input);
      } else {
        expect(() => ReadingCodec.decode(input), throwsA(anything));
      }
    });
  }

  test('standalone ebooks, series and internal navigation share neutral contracts without enabling readers', () {
    final catalog = ReadingCodec.decode(base());
    final standalone = catalog.titles.first;
    final graph = GroupSnapshot(
      groups: catalog.groups,
      titles: catalog.titles.map((t) => t.catalog.id),
      memberships: catalog.memberships,
      titleSubtypes: {
        for (final t in catalog.titles) t.catalog.id: t.catalog.subtype,
      },
    );
    expect(graph.children(catalog.groups.first.id), [
      catalog.titles[1].catalog.id,
    ]);
    expect(
      catalog.memberships.any((m) => m.child == standalone.catalog.id),
      false,
    );
    expect(standalone.readingOrder.length, 2);
    expect(standalone.catalog.segments, isEmpty);
    expect(() => standalone.readingOrder.clear(), throwsUnsupportedError);
    expect(
      () => standalone.catalog.metadata.authors.clear(),
      throwsUnsupportedError,
    );
    for (final subtype in [MediaSubtype.ebook, MediaSubtype.comics]) {
      expect(appSubtypes.requireEnabled(subtype).id, subtype);
      expect(appSubtypes.definition(subtype).engine, MediaEngineKind.reader);
    }
    expect(
      appSubtypes.definition(MediaSubtype.ebook).hierarchy.titleRequiresGroup,
      false,
    );
    expect(
      appSubtypes.definition(MediaSubtype.comics).hierarchy.titleRequiresGroup,
      true,
    );
    expect(ReadingCodec.encode(catalog), base());
  });

  test('reader settings reuse inheritance, provenance and reset with subtype validation', () {
    final catalog = ReadingCodec.decode(base());
    final layers = catalog.settings
        .where((s) => s.subtype == MediaSubtype.ebook)
        .map((s) => s.layer)
        .toList();
    const resolver = SettingsResolver();
    final resolved = resolver.resolve(ReaderSettings.fontSize, layers);
    expect(resolved.value, 24.0);
    expect(resolved.scope, SettingsScope.title);
    expect(
      resolver.resolve(ReaderSettings.fontSize, layers.take(3)).value,
      22.0,
    );
    final reset = ReadingSettingsLayer(
      scope: SettingsScope.title,
      subtype: MediaSubtype.ebook,
      collectionId: 'books:[]',
      entityId: 'volume',
    );
    expect(
      resolver.resolve(ReaderSettings.fontSize, [
        ...layers.take(3),
        reset.layer,
      ]).scope,
      SettingsScope.group,
    );
    expect(
      () => ReadingSettingsLayer(
        scope: SettingsScope.app,
        subtype: MediaSubtype.comics,
        values: {'fontSize': 18},
      ),
      throwsFormatException,
    );
    expect(
      () =>
          ReaderSettings.validate(MediaSubtype.ebook, {'fontSize': double.nan}),
      throwsFormatException,
    );
    expect(
      () => PageReadingLocation(
        pageId: 'p',
        pageIndex: 0,
        offset: double.infinity,
      ),
      throwsFormatException,
    );
    expect(
      () => ReadingLocation.fromJson({
        ...catalog.progress.first.location.toJson(),
        'positionMs': 12,
      }),
      throwsFormatException,
    );
  });

  test('two repositories merge progress and failed writes preserve durable state and allow retry', () async {
    final store = ReadingStore()..value = base();
    final a = ReadingRepository(store), b = ReadingRepository(store);
    final original = await a.read();
    final first = original.progress.first, second = original.progress.last;
    ReadingProgress finish(ReadingProgress p) => ReadingProgress(
      id: p.id,
      sourceId: p.sourceId,
      sourceRevision: p.sourceRevision,
      location: p.location,
      finished: true,
    );
    await Future.wait([
      a.saveProgress(finish(first)),
      b.saveProgress(finish(second)),
    ]);
    expect((await a.read()).progress.every((p) => p.finished), true);
    final before = copy(store.value!);
    store.fail = true;
    await expectLater(a.removeCollection('books:[]'), throwsStateError);
    expect(store.value, before);
    store.fail = false;
    await a.removeCollection('books:[]');
    final after = await b.read();
    expect(after.collections.map((c) => c.id), ['comics']);
    expect(after.groups.length, 1);
    expect(after.titles.length, 1);
    expect(after.progress.single.id.collectionId, 'comics');
    expect(after.settings.any((s) => s.collectionId == 'books:[]'), false);
    expect(after.settings.any((s) => s.scope == SettingsScope.app), true);
    expect(original.collections.length, 2); // Detached, immutable projection.
  });

  test('reading repository uses the existing native state channel with a separate namespace', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    String? stored;
    messenger.setMockMethodCallHandler(LibraryService.channel, (call) async {
      calls.add(call);
      if (call.method == 'readState') {
        expect(call.arguments, ReadingCodec.key);
        return stored;
      }
      if (call.method == 'writeState') {
        final args = call.arguments as Map;
        expect(args['key'], ReadingCodec.key);
        stored = args['value'] as String;
        return null;
      }
      fail('Unexpected legacy method ${call.method}');
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(LibraryService.channel, null),
    );
    final repository = ReadingRepository(const LibraryService());
    await repository.update((_) async => ReadingCodec.decode(base()));
    expect(ReadingCodec.encode(await repository.read()), base());
    expect(calls.map((c) => c.method), [
      'readState',
      'writeState',
      'readState',
    ]);
  });

  test('reading session restores exact text position and inherited settings; failed close stays open for retry', () async {
    final store = ReadingStore()..value = base();
    final repository = ReadingRepository(store), renderer = FakeTextReader();
    final session = ReadingSession(
      repository,
      renderer,
      authorized: (_) => true,
    );
    final catalog = await repository.read();
    await session.open(catalog.titles.first);
    expect(
      renderer.restored!.toJson(),
      catalog.progress.first.location.toJson(),
    );
    expect(renderer.preferences!['fontSize'], 20.0);
    store.fail = true;
    await expectLater(session.close(), throwsStateError);
    expect(session.state, ReaderSessionState.open);
    expect(renderer.closes, 0);
    store.fail = false;
    await session.save(finished: true);
    await session.close();
    expect(session.state, ReaderSessionState.closed);
    expect(
      (await repository.read()).progress
          .firstWhere((p) => p.id == catalog.titles.first.catalog.id)
          .finished,
      true,
    );
    await session.open(catalog.titles[1]);
    expect(renderer.preferences!['fontSize'], 24.0);
    await session.discard();
  });

  test('source revisions require explicit recovery; restart never reuses unsafe progress', () async {
    final input = base();
    (input['progress'] as List).first['sourceRevision'] = 'older';
    (input['progress'] as List).first['location']['resourceId'] = 'gone';
    final store = ReadingStore()..value = input;
    final repository = ReadingRepository(store), renderer = FakeTextReader();
    final session = ReadingSession(
      repository,
      renderer,
      authorized: (_) => true,
    );
    final title = (await repository.read()).titles.first;
    await expectLater(
      session.open(title),
      throwsA(isA<ReadingRecoveryRequired>()),
    );
    expect(session.state, ReaderSessionState.recoveryRequired);
    expect(renderer.opens, 0);
    expect(store.value, input);
    await session.open(title, restart: true);
    expect(renderer.restored, isNull);
    await session.close();
    expect(
      (await repository.read()).progress.last.sourceRevision,
      title.sourceRevision,
    );
    expect((await repository.read()).progress.last.finished, false);
  });

  test('session rejects overlapping launches, permission revocation and changed sources', () async {
    final store = ReadingStore()..value = base();
    final repository = ReadingRepository(store), renderer = FakeTextReader();
    var allowed = true;
    final session = ReadingSession(
      repository,
      renderer,
      authorized: (_) => allowed,
    );
    final title = (await repository.read()).titles.first;
    renderer.gate = Completer<void>();
    final opening = session.open(title);
    await Future<void>.delayed(Duration.zero);
    await expectLater(session.open(title), throwsStateError);
    renderer.gate!.complete();
    await opening;
    expect(renderer.opens, 1);
    allowed = false;
    await expectLater(session.save(), throwsStateError);
    await session.discard();
    expect(session.state, ReaderSessionState.closed);
    expect(renderer.closes, 1);
    allowed = true;
    renderer.gate = null;
    await session.open(title);
    store.value!['titles'][0]['source']['revision'] = 'new';
    final before = copy(store.value!);
    await expectLater(session.save(), throwsStateError);
    expect(store.value, before);
    await session.discard();
  });

  test('authorization is checked after asynchronous reads and failed renderer opening releases resources', () async {
    final store = ReadingStore()..value = base();
    final repository = ReadingRepository(store), renderer = FakeTextReader();
    var allowed = true;
    final session = ReadingSession(
      repository,
      renderer,
      authorized: (_) => allowed,
    );
    final title = (await repository.read()).titles.first;
    store.readGate = Completer<void>();
    final opening = session.open(title);
    allowed = false;
    store.readGate!.complete();
    await expectLater(opening, throwsStateError);
    expect(renderer.opens, 0);
    expect(session.state, ReaderSessionState.closed);
    allowed = true;
    renderer.failOpen = true;
    await expectLater(session.open(title), throwsStateError);
    expect(renderer.closes, 1);
    expect(session.state, ReaderSessionState.closed);
  });
}
