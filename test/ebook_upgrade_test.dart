import 'package:multiplexr/src/bootstrap/reader_assembly.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/reading/comic_reader_controller.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_location.dart';
import 'package:multiplexr/src/reading/domain/reader_settings.dart';
import 'package:multiplexr/src/reading/reader_opening.dart';
import 'package:multiplexr/src/reading/reading_comic_source.dart';
import 'package:multiplexr/src/features/settings/application/reader_preferences.dart';
import 'package:multiplexr/src/reading/reading_repository.dart';
import 'package:multiplexr/src/features/reading/application/reading_session.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';

import 'reading_r1_test.dart' show ReadingStore;
import 'reading_r4_test.dart' show ComicSource;
import 'reading_r5_test.dart' show ReadingWorkflowTransport;

Map<String, dynamic> pdfFixture() {
  final raw =
      jsonDecode(
            File('test/fixtures/reading-v1.json').readAsStringSync(),
          )['base']
          as Map<String, dynamic>;
  final title = (raw['titles'] as List).first as Map<String, dynamic>;
  title['format'] = 'pdf';
  title['readingOrder'] = [
    for (var i = 0; i < 2; i++)
      {'id': 'page-$i', 'href': 'page-$i', 'label': 'Page ${i + 1}'},
  ];
  (raw['progress'] as List).removeWhere(
    (p) => p['collectionId'] == title['collectionId'] && p['id'] == title['id'],
  );
  return raw;
}

class ExternalTransport extends ReadingWorkflowTransport {
  int opens = 0;
  bool unavailable = false;
  Map? request;
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (method == 'readingReaderApps') {
      return [
        {'label': 'Test Reader', 'package': 'org.example.reader'},
      ] as T;
    }
    if (method == 'openExternalReading') {
      if (unavailable) {
        throw PlatformException(code: 'reader', message: 'Reader removed');
      }
      opens++;
      request = arguments as Map;
      return true as T;
    }
    return super.invokeMethod<T>(method, arguments);
  }
}

void main() {
  test(
    'PDF catalog roundtrip uses page positions and rejects text positions',
    () {
      final catalog = ReadingCodec.decode(pdfFixture());
      final title = catalog.titles.first;
      expect(title.format, ReadingFormat.pdf);
      final next = ReadingCatalog(
        collections: catalog.collections,
        groups: catalog.groups,
        titles: catalog.titles,
        memberships: catalog.memberships,
        settings: catalog.settings,
        progress: [
          ReadingProgress(
            id: title.catalog.id,
            sourceId: title.catalog.sources.single.id,
            sourceRevision: title.sourceRevision,
            location: PageReadingLocation(
              pageId: 'page-1',
              pageIndex: 1,
              offset: .4,
            ),
            finished: false,
          ),
        ],
      );
      expect(
        (ReadingCodec.decode(ReadingCodec.encode(next)).progress.single.location
                as PageReadingLocation)
            .offset,
        .4,
      );
      final raw = ReadingCodec.encode(next);
      raw['progress'][0]['location'] = TextReadingLocation(
        resourceId: 'page-1',
        locatorType: TextLocatorType.textOffset,
        locator: '0',
        progression: 0,
        before: '',
        highlight: '',
        after: '',
      ).toJson();
      expect(() => ReadingCodec.decode(raw), throwsFormatException);
    },
  );

  test(
    'PDF adapter restores mixed-size pages and saves ebook-specific appearance',
    () async {
      final store = ReadingStore()..value = pdfFixture();
      final repository = ReadingRepository(store);
      final title = (await repository.read()).titles.first;
      final source = ComicSource()
        ..pages = [
          ComicPage('page-0', 600, 800),
          ComicPage('page-1', 1200, 700),
        ];
      final controller = ComicReaderController(
        source,
        repository,
        authorized: (_) => true,
        pdf: true,
      );
      final session = ReadingSession(
        repository,
        controller,
        authorized: (_) => true,
      );
      await session.open(title);
      await controller.jump(1, withinPage: .45);
      await controller.setPreferences({'comicMode': 'webtoon', 'fit': 'width'});
      expect(controller.webtoon, true);
      await session.save();
      await session.discard();
      await session.open(title);
      expect(controller.pageIndex, 1);
      expect(controller.offset, .45);
      expect(controller.preferences['fit'], 'width');
      expect(
        (await repository.read()).settings.last.subtype,
        MediaSubtype.ebook,
      );
      await session.discard();
      controller.dispose();
      expect(source.closes, greaterThanOrEqualTo(2));
    },
  );

  test('per-format reader preferences inherit with title precedence', () {
    final original = ReadingCodec.decode(pdfFixture());
    final title = original.titles.first;
    final catalog = ReadingCatalog(
      collections: original.collections,
      groups: original.groups,
      titles: original.titles,
      memberships: original.memberships,
      settings: [
        ReadingSettingsLayer(
          scope: SettingsScope.app,
          subtype: MediaSubtype.ebook,
          values: {'reader_pdf': 'app:org.example.reader'},
        ),
        ReadingSettingsLayer(
          scope: SettingsScope.collection,
          subtype: MediaSubtype.ebook,
          collectionId: title.catalog.id.collectionId,
          values: {'reader_pdf': 'ask'},
        ),
        ReadingSettingsLayer(
          scope: SettingsScope.title,
          subtype: MediaSubtype.ebook,
          collectionId: title.catalog.id.collectionId,
          entityId: title.catalog.id.entityId,
          values: {'reader_pdf': 'internal'},
        ),
      ],
    );
    expect(
      resolveReaderPreferences(catalog, title)['reader_pdf']!.scope,
      SettingsScope.title,
    );
    expect(
      resolveReaderPreferences(catalog, title)['reader_epub']!.value,
      'internal',
    );
    expect(
      () => ReaderSettings.validate(MediaSubtype.ebook, {
        'reader_pdf': 'app:../../bad',
      }),
      throwsFormatException,
    );
  });

  testWidgets(
    'missing external app offers recovery and retains the saved default',
    (tester) async {
      final transport = ExternalTransport()..unavailable = true;
      final raw = transport.state[ReadingCodec.key]!;
      raw['settings'] = [
        {
          'scope': 'app',
          'subtype': 'ebook',
          'values': {'reader_epub': 'app:org.example.removed'},
        },
      ];
      final title = ReadingCodec.decode(raw).titles.first;
      final before = jsonEncode(raw['progress']);
      final service = LibraryService(transport: transport);
      var allowed = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openEbookReader(
                  context,
                  ReaderSessionFactory(service, authorized: (_) => true),
                  title,
                  authorized: (_) => allowed,
                ),
                child: const Text('Read'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Read'));
      await tester.pumpAndSettle();
      expect(find.text('Built-in reader'), findsOneWidget);
      expect(find.text('Test Reader'), findsOneWidget);
      expect(transport.opens, 0);
      // A collection lock arriving while the chooser is open must prevent launch.
      allowed = false;
      transport.unavailable = false;
      await tester.tap(find.text('Test Reader'));
      await tester.pumpAndSettle();
      expect(transport.opens, 0);
      expect(
        jsonEncode(transport.state[ReadingCodec.key]!['progress']),
        before,
      );
      expect(
        (transport.state[ReadingCodec.key]!['settings'] as List)
            .single['values']['reader_epub'],
        'app:org.example.removed',
      );
      expect(find.text('Read'), findsOneWidget);
    },
  );

  for (final ask in [false, true]) {
    testWidgets(
      'external opening respects ${ask ? 'chooser cancellation' : 'saved app'} without changing progress',
      (tester) async {
        final transport = ExternalTransport();
        final raw = transport.state[ReadingCodec.key]!;
        (raw['settings'] as List).clear();
        (raw['settings'] as List).add({
          'scope': 'app',
          'subtype': 'ebook',
          'values': {'reader_epub': ask ? 'ask' : 'app:org.example.reader'},
        });
        final title = ReadingCodec.decode(raw).titles.first;
        final before = jsonEncode(raw['progress']);
        final service = LibraryService(transport: transport);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openEbookReader(
                    context,
                    ReaderSessionFactory(service, authorized: (_) => true),
                    title,
                    authorized: (_) => true,
                  ),
                  child: const Text('Read'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Read'));
        await tester.pumpAndSettle();
        if (ask) {
          expect(find.text('Test Reader'), findsOneWidget);
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          expect(transport.opens, 0);
        } else {
          expect(transport.opens, 1);
          expect(transport.request!['package'], 'org.example.reader');
        }
        expect(
          jsonEncode(transport.state[ReadingCodec.key]!['progress']),
          before,
        );
        expect(find.text('Read'), findsOneWidget);
      },
    );
  }
}
