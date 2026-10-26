import 'support/space_controls.dart';

import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import 'fixtures/legacy_publication_provider.dart';

import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';
import 'package:multiplexr/src/bootstrap/reading_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'reading_document_fixture.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'package:multiplexr/src/library/backup_page.dart';

import 'fixtures/legacy_library_service.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

import 'package:multiplexr/src/metadata/metadata_review_page.dart';
import 'package:multiplexr/src/platform_service.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_index.dart';
import 'package:multiplexr/src/reading/domain/reading_management.dart';
import 'package:multiplexr/src/reading/reading_collection_page.dart';
import 'package:multiplexr/src/reading/reading_comic_notes.dart';
import 'package:multiplexr/src/reading/reading_library.dart';
import 'package:multiplexr/src/reading/reading_management_pages.dart';
import 'package:multiplexr/src/reading/reading_scan.dart';
import 'package:multiplexr/src/reading/reading_workflow_widgets.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';

final readingFixture = jsonDecode(
  File('test/fixtures/reading-management-v1.json').readAsStringSync(),
) as Map<String, dynamic>;
Map<String, dynamic> detached(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

class ReadingWorkflowTransport implements PlatformTransport {
  ReadingWorkflowTransport() {
    state[ReadingCodec.key] = detached(
      readingFixture['catalog'] as Map<String, dynamic>,
    );
    state[ReadingIndex.key] = detached(
      readingFixture['index'] as Map<String, dynamic>,
    );
    state[ReadingManagement.key] = detached(
      readingFixture['management'] as Map<String, dynamic>,
    );
  }
  final state = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  bool fail = false, complete = true;
  Completer<void>? scanGate;
  static final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAMCAYAAABfnvydAAAAFUlEQVR4nGNQSKj4jw8zjIoNWMCGAABVJxWxgyuDdwAAAABJRU5ErkJggg==',
  );
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    calls.add(method);
    if (method == 'readingSnapshot') {
      return jsonEncode({
        'catalog': state[ReadingCodec.key],
        'index': state[ReadingIndex.key],
        'management': state[ReadingManagement.key],
      }) as T;
    }
    if (method == 'readState') {
      return (state[arguments] == null ? null : jsonEncode(state[arguments]))
          as T?;
    }
    if (method == 'writeState') {
      if (fail) throw StateError('Storage failed');
      final a = arguments as Map;
      if (a['value'] == null) {
        state.remove(a['key']);
      } else {
        state[a['key'] as String] =
            jsonDecode(a['value'] as String) as Map<String, dynamic>;
      }
      return null;
    }
    if (method == 'commitReadingManagement' || method == 'commitReadingScan') {
      if (fail) throw StateError('Storage failed');
      final a = jsonDecode(arguments as String) as Map<String, dynamic>;
      if (!metadataValueEquals(a['expectedCatalog'], state[ReadingCodec.key]) ||
          !metadataValueEquals(a['expectedIndex'], state[ReadingIndex.key]) ||
          method == 'commitReadingManagement' &&
              !metadataValueEquals(
                a['expectedManagement'],
                state[ReadingManagement.key],
              )) {
        throw StateError('Concurrent changes');
      }
      final catalog = ReadingCodec.decode(a['catalog'] as Map<String, dynamic>);
      ReadingIndex(a['index'] as Map<String, dynamic>, catalog);
      if (method == 'commitReadingManagement') {
        ReadingManagement(a['management'] as Map<String, dynamic>, catalog);
      }
      state[ReadingCodec.key] = detached(a['catalog'] as Map<String, dynamic>);
      state[ReadingIndex.key] = detached(a['index'] as Map<String, dynamic>);
      if (method == 'commitReadingManagement') {
        state[ReadingManagement.key] = detached(
          a['management'] as Map<String, dynamic>,
        );
      }
      return null;
    }
    if (method == 'discoverReading') {
      final a = arguments as Map;
      await scanGate?.future;
      final catalog = state[ReadingCodec.key]!;
      final index = state[ReadingIndex.key]!;
      return jsonEncode({
        'version': 1,
        'collectionId': a['id'],
        'requestId': a['requestId'],
        'warnings': <String>[],
        'roots': [
          for (final r in a['collection']['roots'] as List)
            {'uri': r['uri'], 'complete': complete},
        ],
        'sources': [
          for (final t in catalog['titles'] as List)
            if (t['collectionId'] == a['id'])
              {
                'sourceKey': (index['entries'] as List).singleWhere(
                  (e) =>
                      e['collectionId'] == t['collectionId'] &&
                      e['id'] == t['id'],
                )['sourceKey'],
                'uri': t['source']['uri'],
                'name': t['source']['name'],
                'rootUri': a['collection']['roots'][0]['uri'],
                'relativePath': t['source']['name'],
                'format': t['format'],
                'fingerprint': (index['entries'] as List).singleWhere(
                  (e) =>
                      e['collectionId'] == t['collectionId'] &&
                      e['id'] == t['id'],
                )['fingerprint'],
                'metadata': {
                  ...t['metadata'] as Map,
                  'title': 'Embedded refresh',
                },
                'readingOrder': t['readingOrder'],
                'cover': '',
                'encoding': '',
                'series': '',
                'ambiguous': false,
              },
        ],
      }) as T;
    }
    if (method == 'cancelReadingScan') return null;
    if (method == 'storeReadingArtwork') {
      if (fail) throw StateError('Failed artwork save');
      return 'reading-cover:${'b' * 64}' as T;
    }
    if (method == 'readReadingArtwork') return Uint8List.fromList(image) as T;
    if (method == 'load') {
      return {
        'collections': [],
        'assets': [],
        'series': [],
        'seasons': [],
        'episodes': [],
      } as T;
    }
    if (method == 'exportBackup') return true as T;
    throw StateError('Unexpected $method');
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) async {
    if (method == 'pickRoot') {
      return Map<K, V>.from({
        'uri': 'content://local/new-root',
        'name': 'Chosen root',
      });
    }
    if (method == 'load') {
      return Map<K, V>.from({
        'collections': [],
        'assets': [],
        'series': [],
        'seasons': [],
        'episodes': [],
      });
    }
    throw StateError('Unexpected map $method');
  }
}

class ReadingWorkflowHarness {
  ReadingWorkflowHarness() {
    service = LibraryService(transport: transport);
    library = createReadingLibrary(service, authorized: (_) => allowed);
    provider = OpenLibraryReadingProvider(rateLimit: false, get: response);
    for (final job
        in (transport.state[ReadingManagement.key]!['jobs'] as List)) {
      job['implementationEpoch'] = MetadataWorkflow([
        provider,
      ], mutations: const OwnerApplicationMutations()).implementationEpoch;
    }
  }
  final transport = ReadingWorkflowTransport();
  late final LibraryService service;
  late final ReadingLibrary library;
  late final OpenLibraryReadingProvider provider;
  bool allowed = true;
  int status = 200;
  final requests = <Uri>[];
  Future<ReadingResponse> response(Uri uri) async {
    requests.add(uri);
    if (uri.host == 'covers.openlibrary.org') {
      return ReadingResponse(
        status,
        Uint8List.fromList(ReadingWorkflowTransport.image),
      );
    }
    return ReadingResponse(
      status,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            uri.path == '/search.json'
                ? {
                    'numFound': 1,
                    'docs': [
                      {
                        'title': 'Matched title',
                        'author_name': ['Lookup author'],
                        'editions': {
                          'docs': [
                            {'key': '/books/OL1M', 'title': 'Matched title'},
                          ],
                        },
                      },
                    ],
                  }
                : {
                    'key': '/books/OL1M',
                    'title': 'Matched title',
                    'description': {'value': 'Edition description'},
                    'isbn_13': ['9781234567890'],
                    'languages': [
                      {'key': '/languages/eng'},
                    ],
                    'covers': [42],
                  },
          ),
        ),
      ),
    );
  }

  CatalogIdentity get book =>
      CatalogIdentity('books:[]', 'standalone', CatalogEntityKind.title);
  CatalogIdentity get volume =>
      CatalogIdentity('books:[]', 'volume', CatalogEntityKind.title);
  Future<ReadingMetadataTarget> target() =>
      ReadingMetadataTarget(library, book, provider).initialize();
  Future<MetadataCandidate> candidate() async =>
      (await MetadataWorkflow([
            provider,
          ], mutations: const OwnerApplicationMutations()).search(
            MetadataSearchRequest(
              provider: provider.id,
              entity: MetadataEntityType.ebook,
              title: 'A title',
            ),
            MetadataCancellation(),
          ))
          .candidates
          .single;
  Future<void> show(
    WidgetTester tester,
    Widget home, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final c in readingFixture['cases'] as List) {
    test('management wire: ${c['name']}', () {
      final raw = detached(
        readingFixture['management'] as Map<String, dynamic>,
      );
      dynamic target = raw;
      final path = c['path'] as List;
      for (final part in path.take(path.length - 1)) {
        target = target[part];
      }
      target[path.last] = c['value'];
      final catalog = ReadingCodec.decode(
        readingFixture['catalog'] as Map<String, dynamic>,
      );
      if (c['valid'] == true) {
        expect(ReadingManagement(raw, catalog).json, raw);
      } else {
        expect(() => ReadingManagement(raw, catalog), throwsA(anything));
      }
    });
  }
  test('manual metadata and portrait artwork survive rescans with stable IDs and independent progress', () async {
    final h = ReadingWorkflowHarness();
    final before = await h.library.read();
    await h.library.metadata(h.book, {
      'title': 'Personal title',
      'cover': 'reading-cover:${'b' * 64}',
    });
    final scan = ReadingScanService(h.service, authorized: (_) => true);
    final preview = await scan.preview('books:[]');
    await scan.apply('books:[]', preview);
    final after = await h.library.read();
    expect(after.catalog.titles.first.catalog.metadata.title, 'Personal title');
    expect(
      after.catalog.titles.first.catalog.sources.single.id,
      before.catalog.titles.first.catalog.sources.single.id,
    );
    expect(after.index.entry(h.book)!.cover, 'reading-cover:${'b' * 64}');
    expect(after.catalog.progress, isEmpty);
  });
  test(
    'moving a title within its group preserves unique source order',
    () async {
      final h = ReadingWorkflowHarness();
      await h.library.group('books:[]', 'saga', 'Saga', ['standalone']);
      await h.library.group('books:[]', 'saga', 'Saga', ['volume']);
      final snapshot = h.transport.state[ReadingCodec.key]!;
      final members = (snapshot['memberships'] as List)
          .where(
            (m) => m['collectionId'] == 'books:[]' && m['parentId'] == 'saga',
          )
          .toList();
      expect(members.map((m) => m['order']).toSet(), {0, 1});
      expect(members.singleWhere((m) => m['titleId'] == 'volume')['order'], 1);
    },
  );
  test('failed atomic writes and revoked access preserve catalog, tags and evidence', () async {
    final h = ReadingWorkflowHarness();
    final before = jsonEncode(h.transport.state);
    h.transport.fail = true;
    await expectLater(
      h.library.metadata(h.book, {'title': 'Lost'}),
      throwsStateError,
    );
    expect(jsonEncode(h.transport.state), before);
    h.transport.fail = false;
    h.allowed = false;
    await expectLater(
      h.library.tags('books:[]', [h.book], ['Hidden']),
      throwsStateError,
    );
    expect(jsonEncode(h.transport.state), before);
  });
  test('concurrent tags and metadata merge; tag rename/delete stay collection-local', () async {
    final h = ReadingWorkflowHarness();
    await Future.wait([
      h.library.metadata(h.book, {'description': 'Manual description'}),
      h.library.tags('books:[]', [h.book], ['One', 'Two']),
    ]);
    await h.library.tags(
      'books:[]',
      [],
      ['one'],
      operation: 'rename',
      target: 'New',
    );
    await h.library.tags('books:[]', [], ['two'], operation: 'delete');
    final b = await h.library.read();
    expect(b.management.entity(h.book).tags, ['New']);
    expect(
      b.catalog.titles.first.catalog.metadata.description,
      'Manual description',
    );
    expect(
      b.management
          .entity(CatalogIdentity('comics', 'issue', CatalogEntityKind.title))
          .tags,
      ['Favourite'],
    );
  });
  test('shared coordinator protects manual defaults and detects conflicts during review', () async {
    final h = ReadingWorkflowHarness();
    final target = await h.target();
    final candidate = await h.candidate();
    final coordinator = MetadataWorkflow([
      h.provider,
    ], mutations: const OwnerApplicationMutations());
    final review = await coordinator.review(
      target,
      candidate,
      MetadataCancellation(),
    );
    expect(review.defaults.contains('title'), false);
    await h.library.metadata(h.book, {'identifier': 'Manual ISBN'});
    await expectLater(
      coordinator.apply(target, review, {'identifier'}, MetadataCancellation()),
      throwsA(isA<MetadataFailure>()),
    );
    expect(
      (await h.library.read()).catalog.titles.first.catalog.metadata.identifier,
      'Manual ISBN',
    );
  });
  test('edition lookup preserves exact ID, caches results and fetches no content or covers until selected', () async {
    final h = ReadingWorkflowHarness();
    final first = await h.candidate();
    await h.candidate();
    expect(h.requests, hasLength(1));
    expect(first.id, '/books/OL1M');
    final target = await h.target();
    final review = await MetadataWorkflow(
      [h.provider],
      mutations: const OwnerApplicationMutations(),
    ).review(target, first, MetadataCancellation());
    expect(review.proposed['identifier'], 'ISBN:9781234567890');
    await MetadataWorkflow([
      h.provider,
    ], mutations: const OwnerApplicationMutations()).apply(target, review, {
      'description',
      'identifier',
    }, MetadataCancellation());
    final b = await h.library.read();
    expect(b.management.entity(h.book).provider, 'openlibrary');
    expect(
      b.catalog.titles.first.catalog.metadata.description,
      'Edition description',
    );
    expect(h.requests.every((u) => u.host == 'openlibrary.org'), true);
  });
  test('metadata jobs checkpoint pause/recover/retry and keep selected results for manual review', () async {
    final h = ReadingWorkflowHarness();
    final job = createReadingMetadataJob(h.library, 'books:[]', h.provider);
    await job.recover();
    expect(job.remaining, ['volume']);
    h.status = 429;
    await expectLater(
      job.start([], resume: true),
      throwsA(isA<MetadataFailure>()),
    );
    final restored = createReadingMetadataJob(
      h.library,
      'books:[]',
      h.provider,
    );
    await restored.recover();
    expect(restored.remaining, ['volume']);
    expect(restored.entries['volume']!['status'], 'failed');
    h.status = 200;
    await restored.start([], retry: true);
    expect(restored.remaining, isEmpty);
    expect(restored.entries['volume']!['status'], 'review');
    expect(
      (await h.library.read()).catalog.titles[1].catalog.metadata.title,
      'volume',
    );
    expect(h.requests.every((u) => u.host == 'openlibrary.org'), true);
    job.dispose();
    restored.dispose();
  });
  test('a failed lookup checkpoint performs no provider I/O and a new batch cannot erase reviews implicitly', () async {
    final h = ReadingWorkflowHarness();
    final job = createReadingMetadataJob(h.library, 'books:[]', h.provider);
    await expectLater(job.start(['standalone']), throwsStateError);
    h.transport.fail = true;
    await expectLater(
      job.start(['standalone'], replace: true),
      throwsStateError,
    );
    expect(h.requests, isEmpty);
    job.dispose();
  });
  test('scoped settings reset inheritance and keep the one progress owner untouched', () async {
    final h = ReadingWorkflowHarness();
    await h.library.settings(
      'books:[]',
      MediaSubtype.ebook,
      SettingsScope.collection,
      null,
      {'fontSize': 27.0},
    );
    await h.library.settings(
      'books:[]',
      MediaSubtype.ebook,
      SettingsScope.title,
      'standalone',
      {'fontSize': 32.0},
    );
    await h.library.settings(
      'books:[]',
      MediaSubtype.ebook,
      SettingsScope.title,
      'standalone',
      {},
      reset: true,
    );
    final b = await h.library.read();
    expect(b.catalog.settings.any((s) => s.entityId == 'standalone'), false);
    expect(b.catalog.progress, isEmpty);
  });
  test(
    'page notes remain separate from progress and stale revisions are retained',
    () async {
      final h = ReadingWorkflowHarness();
      final b = await h.library.read();
      final note = b.management.pageNotes.single;
      expect(comicNoteMatches(note, b.catalog.titles.last), true);
      await h.library.updateFixture(
        'comics',
        (d) => d.row(
          CatalogIdentity('comics', 'issue', CatalogEntityKind.title),
        )['source']['revision'] = 'new',
      );
      final after = await h.library.read();
      expect(after.management.pageNotes.length, 1);
      expect(comicNoteMatches(note, after.catalog.titles.last), false);
      expect(after.catalog.progress, isEmpty);
    },
  );
  test('backup summary includes reading entities and both annotation forms without changing legacy-only labels', () {
    final base = {
      'collections': [],
      'assets': [],
      'state': <String, dynamic>{},
    };
    expect(
      backupSummary(base),
      '0 collections · 0 videos · 0 audiobooks (0 audio files) · 0 music tracks',
    );
    base['state'] = {
      ReadingCodec.key: readingFixture['catalog'],
      ReadingManagement.key: readingFixture['management'],
    };
    expect(
      backupSummary(base),
      contains('2 ebooks · 1 comics · 1 reading annotations'),
    );
  });
  testWidgets(
    'collection group contents, details and reader return preserve the query and original route',
    (tester) async {
      final h = ReadingWorkflowHarness();
      await h.show(
        tester,
        ReadingCollectionPage(
          library: h.library,
          collectionId: 'books:[]',
          provider: h.provider,
          openTitle: (context, title) async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('Reader ${title.catalog.title}')),
                ),
              ),
            );
          },
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Saga'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('volume'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('volume'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search collection'),
        'standalone',
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(ListTile, 'standalone'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Read'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Read'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(find.text('Reader standalone'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Search collection'),
            )
            .controller!
            .text,
        'standalone',
      );
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('failed metadata editor keeps its draft and succeeds on retry', (
    tester,
  ) async {
    final h = ReadingWorkflowHarness();
    await h.show(
      tester,
      ReadingCollectionPage(
        library: h.library,
        collectionId: 'books:[]',
        provider: h.provider,
      ),
    );
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('Actions for standalone'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Edit metadata'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.enterText(
      find.byKey(const ValueKey('reading-field-title')),
      'Retained personal title',
    );
    h.transport.fail = true;
    await openSpaceControls(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save. Your draft is retained.'),
      findsOneWidget,
    );
    expect(find.text('Retained personal title'), findsOneWidget);
    h.transport.fail = false;
    await openSpaceControls(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await h.library.read()).catalog.titles.first.catalog.metadata.title,
      'Retained personal title',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Folder health preview cannot silently apply an incomplete scan and reviewed apply preserves IDs',
    (tester) async {
      final h = ReadingWorkflowHarness();
      h.transport.complete = false;
      await h.show(
        tester,
        ReadingFolderHealthPage(library: h.library, collectionId: 'books:[]'),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Scan and preview'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(find.text('Apply reviewed scan'), 250);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply reviewed scan'),
            )
            .onPressed,
        null,
      );
      expect(h.transport.calls.where((m) => m == 'commitReadingScan'), isEmpty);
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(find.text('Scan and preview'), -400);
      h.transport.complete = true;
      await openSpaceControls(tester);
      await tester.tap(find.text('Scan and preview'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(find.text('Apply reviewed scan'), 300);
      await openSpaceControls(tester);
      await tester.tap(find.text('Apply reviewed scan'));
      await tester.pumpAndSettle();
      expect((await h.library.read()).catalog.titles.first.catalog.id, h.book);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'shared metadata review applies chosen fields and leaves manual title unchecked',
    (tester) async {
      final h = ReadingWorkflowHarness();
      final target = await h.target();
      final candidate = await h.candidate();
      await h.show(
        tester,
        MetadataReviewPage(
          workflow: MetadataWorkflow(
            [],
            mutations: const OwnerApplicationMutations(),
          ),
          target: target,
          candidate: candidate,
        ),
      );
      expect(find.text('Title'), findsOneWidget);
      final titleTile = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Title'),
      );
      expect(titleTile.value, false);
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Apply selected metadata'),
        400,
      );
      h.transport.fail = true;
      await openSpaceControls(tester);
      await tester.tap(find.text('Apply selected metadata'));
      await tester.pumpAndSettle();
      expect(
        find.text('Metadata provider could not complete the request.'),
        findsOneWidget,
      );
      h.transport.fail = false;
      await openSpaceControls(tester);
      await tester.tap(find.text('Apply selected metadata'));
      await tester.pumpAndSettle();
      expect(
        (await h.library.read()).catalog.titles.first.catalog.metadata.title,
        'standalone',
      );
    },
  );
  testWidgets(
    'page notes and text notes appear in the shared annotation surface; failed deletion retains them',
    (tester) async {
      final h = ReadingWorkflowHarness();
      await h.show(
        tester,
        ReadingAnnotationsPage(library: h.library, collectionId: 'comics'),
      );
      expect(find.text('Page 2'), findsOneWidget);
      h.transport.fail = true;
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Delete saved page'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not delete the saved page. It is retained.'),
        findsOneWidget,
      );
      h.transport.fail = false;
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Delete saved page'));
      await tester.pumpAndSettle();
      expect((await h.library.read()).management.pageNotes, isEmpty);
      await openSpaceControls(tester);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'large text and narrow layouts keep collection and settings usable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = ReadingWorkflowHarness();
      await h.show(
        tester,
        ReadingCollectionPage(
          library: h.library,
          collectionId: 'books:[]',
          provider: h.provider,
        ),
        scale: 1.8,
      );
      expect(tester.takeException(), null);
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Reader settings'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Reader settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'locked reading collections require existing device authentication before backup export',
    (tester) async {
      final h = ReadingWorkflowHarness();
      h.transport.state[ReadingCodec.key]!['collections'][0]['locked'] = true;
      final legacy = createLibraryController(h.service);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('multiplexr/device'),
        (call) async => false,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('multiplexr/device'),
          null,
        );
        legacy.dispose();
      });
      await h.show(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: LibraryBackupSettings(
              library: legacy,
              platform: const PlatformService(),
            ),
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Export library backup'));
      await tester.pumpAndSettle();
      expect(h.transport.calls.contains('exportBackup'), false);
      expect(find.text('Authentication cancelled.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'revoked collection access hides titles, counts and artwork before a refresh',
    (tester) async {
      final h = ReadingWorkflowHarness();
      h.allowed = false;
      await h.show(
        tester,
        ReadingCollectionPage(library: h.library, collectionId: 'books:[]'),
      );
      expect(find.text('standalone'), findsNothing);
      expect(find.byType(ReadingCover), findsNothing);
      expect(find.text('Collection access is required.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  test('shared reading workflows have final production bindings', () {
    expect(appSubtypes.definition(MediaSubtype.ebook).enabled, true);
    expect(appSubtypes.definition(MediaSubtype.comics).enabled, true);
  });
}
