import 'package:multiplexr/src/features/sources/application/reading_scan_plan.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_index.dart';
import 'package:multiplexr/src/reading/reading_scan.dart';

Map<String, dynamic> catalog({
  String subtype = 'ebook',
  List<String> roots = const ['content://root/one'],
}) => {
  'version': 1,
  'collections': [
    {
      'id': 'c',
      'name': 'Reading',
      'subtype': subtype,
      'locked': false,
      'includeInGlobal': true,
      'roots': [
        for (final uri in roots) {'uri': uri, 'name': 'Root'},
      ],
    },
  ],
  'groups': [],
  'titles': [],
  'memberships': [],
  'progress': [],
  'settings': [],
};
Map<String, dynamic> source(
  String key, {
  String root = 'content://root/one',
  String title = 'Embedded',
  String name = 'Book.epub',
  String series = '',
  String? bytes,
  bool ambiguous = false,
  String format = 'epub',
}) => {
  'sourceKey': key,
  'uri': 'content://local/$key',
  'name': name,
  'rootUri': root,
  'relativePath': name,
  'format': format,
  'fingerprint': sha256.convert(utf8.encode(bytes ?? key)).toString(),
  'metadata': ReadingMetadata(title: title, authors: ['Author']).toJson(),
  'readingOrder': [
    {'id': 'first', 'href': 'first.xhtml', 'label': 'First'},
    {'id': 'second', 'href': 'second.xhtml', 'label': 'Second'},
  ],
  'cover': '',
  'encoding': format == 'txt' ? 'utf-8' : '',
  'series': series,
  'ambiguous': ambiguous,
};
Map<String, dynamic> discovery(
  List<Map<String, dynamic>> sources, {
  List<String> roots = const ['content://root/one'],
  bool complete = true,
}) => {
  'version': 1,
  'collectionId': 'c',
  'requestId': 'request',
  'sources': sources,
  'roots': [
    for (final uri in roots) {'uri': uri, 'complete': complete},
  ],
  'warnings': <String>[],
};

class ScanTransport implements PlatformTransport {
  Map<String, dynamic>? state = catalog(), index;
  Map<String, dynamic> result = discovery([source('one')]);
  final calls = <String>[];
  Completer<void>? gate;
  bool failCommit = false;
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    calls.add(method);
    if (method == 'readingSnapshot') {
      return jsonEncode({'catalog': state, 'index': index}) as T;
    }
    if (method == 'discoverReading') {
      final request = arguments as Map;
      await gate?.future;
      return jsonEncode({...result, 'requestId': request['requestId']}) as T;
    }
    if (method == 'cancelReadingScan') return null;
    if (method == 'commitReadingScan') {
      if (failCommit) {
        throw PlatformException(code: 'storage', message: 'Failed');
      }
      final data = jsonDecode(arguments as String) as Map<String, dynamic>;
      if (jsonEncode(data['expectedCatalog']) != jsonEncode(state) ||
          jsonEncode(data['expectedIndex']) != jsonEncode(index)) {
        throw PlatformException(code: 'conflict');
      }
      state = data['catalog'] as Map<String, dynamic>;
      index = data['index'] as Map<String, dynamic>;
      return null;
    }
    throw StateError('Unexpected method $method');
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = jsonDecode(
    File('test/fixtures/reading-index-v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final testCase in fixture['cases'] as List) {
    test('Dart/native index fixture: ${testCase['name']}', () {
      final input = ReadingIndex.copy(fixture['index'] as Map<String, dynamic>);
      final path = testCase['path'] as List;
      dynamic target = input;
      for (final part in path.take(path.length - 1)) {
        target = target[part];
      }
      target[path.last] = testCase['value'];
      final model = ReadingCodec.decode(
        fixture['catalog'] as Map<String, dynamic>,
      );
      if (testCase['valid'] == true) {
        expect(ReadingIndex(input, model).json, input);
      } else {
        expect(() => ReadingIndex(input, model), throwsA(anything));
      }
    });
  }
  test('bad root snapshots and malformed ambiguity flags fail before reconciliation', () {
    final input = catalog(roots: ['content://root/one', 'content://root/two']);
    final result = discovery(
      [],
      roots: ['content://root/one', 'content://root/one'],
    );
    expect(
      () => ReadingScanPlanner.preview(input, null, result),
      throwsFormatException,
    );
    final malformed = source('one')..['ambiguous'] = 'false';
    expect(
      () => ReadingScanPlanner.preview(catalog(), null, discovery([malformed])),
      throwsFormatException,
    );
  });
  test(
    'embedded covers refresh and explicit artwork overrides survive rescanning',
    () {
      final a = source('one')..['cover'] = 'reading-cover:${'a' * 64}';
      final b = source('one')..['cover'] = 'reading-cover:${'b' * 64}';
      final first = ReadingScanPlanner.preview(catalog(), null, discovery([a]));
      var next = ReadingScanPlanner.preview(
        first.catalog,
        first.index,
        discovery([b]),
      );
      expect(next.index['entries'][0]['cover'], b['cover']);
      next.index['entries'][0]['manualCover'] = true;
      next = ReadingScanPlanner.preview(
        next.catalog,
        next.index,
        discovery([a]),
      );
      expect(next.index['entries'][0]['cover'], b['cover']);
    },
  );
  test(
    'a preview can be corrected without repeating filesystem discovery',
    () async {
      final transport = ScanTransport()
        ..result = discovery([source('one', ambiguous: true)]);
      final service = ReadingScanService(
        LibraryService(transport: transport),
        authorized: (_) => true,
      );
      final original = await service.preview('c');
      expect(original.canApply, false);
      final corrected = service.revise(original, grouping: {'one': ''});
      expect(corrected.canApply, true);
      expect(transport.calls.where((c) => c == 'discoverReading').length, 1);
      await service.apply('c', corrected);
      expect(transport.state!['titles'].length, 1);
    },
  );
  test('multiple roots, duplicate display names and editions keep independent stable identities', () {
    final initial = catalog(
      roots: ['content://root/one', 'content://root/two'],
    );
    final response = discovery(
      [source('one'), source('two', root: 'content://root/two')],
      roots: ['content://root/one', 'content://root/two'],
    );
    final preview = ReadingScanPlanner.preview(initial, null, response);
    expect(preview.canApply, true);
    expect(preview.added, 2);
    final titles = ReadingCodec.decode(preview.catalog).titles;
    expect(titles.map((t) => t.catalog.id).toSet().length, 2);
    expect(titles.map((t) => t.catalog.metadata.title).toSet(), {'Embedded'});
    expect(preview.catalog['groups'], isEmpty);
    expect(initial['titles'], isEmpty);
    final repeated = ReadingScanPlanner.preview(
      preview.catalog,
      preview.index,
      response,
    );
    expect(repeated.added, 0);
    expect(repeated.relinked, 0);
    expect(repeated.catalog, preview.catalog);
    expect(repeated.index, preview.index);
  });

  test('repeat scanning respects manual fields while refreshing untouched embedded fields', () {
    final first = ReadingScanPlanner.preview(
      catalog(),
      null,
      discovery([source('one')]),
    );
    first.catalog['titles'][0]['metadata']['title'] = 'My title';
    final changed = source('one', title: 'New embedded');
    changed['metadata']['language'] = 'ja';
    final preview = ReadingScanPlanner.preview(
      first.catalog,
      first.index,
      discovery([changed]),
    );
    expect(preview.catalog['titles'][0]['metadata']['title'], 'My title');
    expect(preview.catalog['titles'][0]['metadata']['language'], 'ja');
    expect(preview.index['entries'][0]['manualFields'], ['title']);
    final again = ReadingScanPlanner.preview(
      preview.catalog,
      preview.index,
      discovery([source('one', title: 'Third')]),
    );
    expect(again.catalog['titles'][0]['metadata']['title'], 'My title');
  });

  test('missing and uniquely reconnected roots retain title/source IDs, metadata, groups and progress', () {
    final first = ReadingScanPlanner.preview(
      catalog(),
      null,
      discovery([source('old', bytes: 'same', series: 'Saga')]),
    );
    final title = first.catalog['titles'][0] as Map;
    first.catalog['progress'] = [
      {
        'collectionId': 'c',
        'id': title['id'],
        'sourceId': title['source']['id'],
        'sourceRevision': title['source']['revision'],
        'finished': true,
        'location': {
          'version': 1,
          'kind': 'text',
          'resourceId': 'first',
          'locatorType': 'cssSelector',
          'locator': '#p',
          'progression': .4,
          'before': '',
          'highlight': '',
          'after': '',
        },
      },
    ];
    final missing = ReadingScanPlanner.preview(
      first.catalog,
      first.index,
      discovery([]),
    );
    expect(missing.missing, 1);
    expect(missing.catalog['titles'][0]['source']['available'], false);
    final reconnected = ReadingScanPlanner.preview(
      missing.catalog,
      missing.index,
      discovery(
        [
          source(
            'new',
            root: 'content://root/new',
            bytes: 'same',
            series: 'Changed',
          ),
        ],
        roots: ['content://root/new'],
      ),
      rootReplacements: {'content://root/one': 'content://root/new'},
    );
    expect(reconnected.relinked, 1);
    expect(reconnected.added, 0);
    expect(reconnected.catalog['titles'][0]['id'], title['id']);
    expect(
      reconnected.catalog['titles'][0]['source']['id'],
      title['source']['id'],
    );
    expect(
      reconnected.catalog['titles'][0]['source']['revision'],
      title['source']['revision'],
    );
    expect(reconnected.catalog['progress'], first.catalog['progress']);
    expect(reconnected.catalog['memberships'], first.catalog['memberships']);
    expect(reconnected.index['replacements'], [
      {
        'collectionId': 'c',
        'from': 'content://root/one',
        'to': 'content://root/new',
      },
    ]);
    final repeated = ReadingScanPlanner.preview(
      reconnected.catalog,
      reconnected.index,
      discovery(
        [source('new', root: 'content://root/new', bytes: 'same')],
        roots: ['content://root/new'],
      ),
    );
    expect(repeated.relinked, 0);
    expect(repeated.catalog['titles'].length, 1);
    final returned = ReadingScanPlanner.preview(
      repeated.catalog,
      repeated.index,
      discovery([source('old', bytes: 'same')]),
      rootReplacements: {'content://root/new': 'content://root/one'},
    );
    expect(returned.canApply, true);
    expect(returned.catalog['titles'][0]['id'], title['id']);
  });

  test('same filenames without content evidence never reconnect; duplicate fingerprints need reviewed choices', () {
    final first = ReadingScanPlanner.preview(
      catalog(),
      null,
      discovery([source('old')]),
    );
    final different = ReadingScanPlanner.preview(
      first.catalog,
      first.index,
      discovery([source('new')]),
    );
    expect(different.added, 1);
    expect(different.relinked, 0);
    expect(different.missing, 1);
    final duplicates = ReadingScanPlanner.preview(
      catalog(),
      null,
      discovery([source('a', bytes: 'same'), source('b', bytes: 'same')]),
    );
    final ambiguous = ReadingScanPlanner.preview(
      duplicates.catalog,
      duplicates.index,
      discovery([source('c', bytes: 'same'), source('d', bytes: 'same')]),
    );
    expect(ambiguous.canApply, false);
    expect(ambiguous.unresolved.length, 2);
    final ids = (duplicates.catalog['titles'] as List)
        .map((t) => t['id'] as String)
        .toList();
    final fixed = ReadingScanPlanner.preview(
      duplicates.catalog,
      duplicates.index,
      discovery([source('c', bytes: 'same'), source('d', bytes: 'same')]),
      relinks: {ids[0]: 'c', ids[1]: 'd'},
    );
    expect(fixed.canApply, true);
    expect(fixed.relinked, 2);
    expect(fixed.added, 0);
    expect(
      () => ReadingScanPlanner.preview(
        duplicates.catalog,
        duplicates.index,
        discovery([source('c')]),
        relinks: {ids[0]: 'c', ids[1]: 'c'},
      ),
      throwsArgumentError,
    );
  });

  test('ambiguous folder layouts require a correction and comics retain required series containers', () {
    final response = discovery([
      source('one', ambiguous: true, series: 'Too/Deep'),
    ]);
    final pending = ReadingScanPlanner.preview(catalog(), null, response);
    expect(pending.canApply, false);
    expect(pending.catalog['titles'], isEmpty);
    final fixed = ReadingScanPlanner.preview(
      catalog(),
      null,
      response,
      grouping: {'one': ''},
    );
    expect(fixed.canApply, true);
    expect(fixed.catalog['groups'], isEmpty);
    final comic = ReadingScanPlanner.preview(
      catalog(subtype: 'comics'),
      null,
      discovery([source('comic', format: 'cbz')]),
    );
    expect(comic.catalog['groups'].length, 1);
    expect(comic.catalog['memberships'].length, 1);
  });

  test('natural order, decimal chapters, specials and manual order survive repeat scans', () {
    final names = [
      'Chapter 10',
      'Chapter 2',
      'Chapter 1.5',
      'Special',
      'Chapter 1',
    ];
    final response = discovery([
      for (var i = 0; i < names.length; i++)
        source('$i', name: names[i], series: 'Saga'),
    ]);
    final first = ReadingScanPlanner.preview(catalog(), null, response);
    final titles = {
      for (final t in first.catalog['titles']) t['id']: t['source']['name'],
    };
    List<String> ordered(ReadingDocumentPlan p) =>
        (p.catalog['memberships'] as List)
            .toList()
            .cast<Map>()
            .sorted((a, b) => (a['order'] as int).compareTo(b['order'] as int))
            .map((m) => titles[m['titleId']] as String)
            .toList();
    expect(ordered(first), [
      'Chapter 1',
      'Chapter 1.5',
      'Chapter 2',
      'Chapter 10',
      'Special',
    ]);
    final manual = (first.catalog['titles'] as List)
        .map((t) => t['id'] as String)
        .toList();
    final corrected = ReadingScanPlanner.preview(
      first.catalog,
      first.index,
      response,
      titleOrder: manual,
      resourceOrder: {
        '0': ['second', 'first'],
      },
    );
    expect(corrected.catalog['titles'][0]['readingOrder'][0]['id'], 'second');
    final repeated = ReadingScanPlanner.preview(
      corrected.catalog,
      corrected.index,
      response,
    );
    expect(ordered(repeated), names);
    expect(repeated.catalog['titles'][0]['readingOrder'][0]['id'], 'second');
    expect(
      repeated.catalog['titles'][0]['source']['revision'],
      corrected.catalog['titles'][0]['source']['revision'],
    );
    expect(
      () => ReadingScanPlanner.preview(
        first.catalog,
        first.index,
        response,
        resourceOrder: {
          '0': ['first'],
        },
      ),
      throwsArgumentError,
    );
  });

  test(
    'incomplete scans cannot be applied or mark previous titles missing',
    () async {
      final first = ReadingScanPlanner.preview(
        catalog(),
        null,
        discovery([source('one')]),
      );
      final pending = ReadingScanPlanner.preview(
        first.catalog,
        first.index,
        discovery([], complete: false),
      );
      expect(pending.canApply, false);
      expect(pending.missing, 0);
      expect(pending.catalog['titles'][0]['source']['available'], true);
      final transport = ScanTransport()
        ..state = first.catalog
        ..index = first.index;
      final service = ReadingScanService(
        LibraryService(transport: transport),
        authorized: (_) => true,
      );
      await expectLater(
        service.apply(
          'c',
          ReadingScanPreview(
            collectionId: 'c',
            requestId: 'test',
            complete: false,
            added: 0,
            relinked: 0,
            missing: 0,
          ),
        ),
        throwsStateError,
      );
      expect(transport.calls, isEmpty);
    },
  );

  test('scan apply is atomic, rejects stale snapshots and surfaces failed saves for retry', () async {
    final transport = ScanTransport();
    final service = ReadingScanService(
      LibraryService(transport: transport),
      authorized: (_) => true,
    );
    final preview = await service.preview('c');
    expect(transport.state!['titles'], isEmpty);
    transport.failCommit = true;
    await expectLater(
      service.apply('c', preview),
      throwsA(isA<PlatformException>()),
    );
    expect(transport.state!['titles'], isEmpty);
    expect(transport.index, null);
    transport.failCommit = false;
    await service.apply('c', preview);
    expect(transport.state!['titles'].length, 1);
    expect(transport.index!['entries'].length, 1);
    await expectLater(service.apply('c', preview), throwsStateError);
  });

  test('cancellation and authorization changes never produce or apply a partial scan', () async {
    final transport = ScanTransport()..gate = Completer<void>();
    var allowed = true;
    final service = ReadingScanService(
      LibraryService(transport: transport),
      authorized: (_) => allowed,
    );
    final scanning = service.preview('c');
    await Future<void>.delayed(Duration.zero);
    await expectLater(service.preview('c'), throwsStateError);
    await service.cancel();
    transport.gate!.complete();
    await expectLater(scanning, throwsStateError);
    expect(transport.calls, contains('cancelReadingScan'));
    expect(transport.state!['titles'], isEmpty);
    transport.gate = null;
    final preview = await service.preview('c');
    allowed = false;
    await expectLater(service.apply('c', preview), throwsStateError);
    expect(transport.calls, isNot(contains('commitReadingScan')));
  });
}

extension _Sorted<T> on List<T> {
  List<T> sorted(int Function(T, T) compare) => this..sort(compare);
}
