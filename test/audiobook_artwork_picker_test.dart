import 'package:multiplexr/src/core/application/mutations.dart';

import 'fixtures/legacy_provider_adapters.dart';

import 'fixtures/legacy_library_assembly.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'fixtures/legacy_audiobook_metadata_service.dart';
import 'package:multiplexr/src/core/platform/native_media_imports.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audiobook_management.dart';
import 'package:multiplexr/src/media/grouping.dart';

import 'dart:async';

import 'package:multiplexr/src/media/media_ui_patterns.dart';
import 'package:multiplexr/src/media/audiobook_details.dart';
import 'package:multiplexr/src/media/storage.dart';
import 'package:multiplexr/src/media/contracts.dart';

import 'media_foundation_test.dart' show SharedStore;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audiobook_artwork_picker.dart';

import 'grouped_media_test.dart' show audiobook;

void main() {
  test(
    'collection and space search includes edited series identity and narrator',
    () {
      final book = audiobook(
        'Member',
        series: 'Original',
      ).withMetadata({'narrator': 'Reader'});
      final text = audiobookSearchText(
        book,
        series: const AudiobookSeriesMetadata(
          id: 'group',
          collectionId: 'a',
          title: 'Custom saga',
          author: 'Series author',
        ),
      );
      expect(text.contains('custom saga'), true);
      expect(text.contains('reader'), true);
      expect(text.contains('series author'), true);
    },
  );

  testWidgets(
    'series artwork selection changes only the series cover and preserves member metadata and progress',
    (tester) async {
      final store = SharedStore();
      final catalog = createAudioLibrary(store);
      final book = audiobook(
        'Member',
        series: 'Saga',
      ).withMetadata({'cover': '/missing/member.png', 'author': 'Author'});
      await catalog.save([book]);
      final progress = AudiobookProgress(
        book.id,
        chapterId: book.chapterMarkers.first.id,
        positionMs: 2500,
        finished: false,
      );
      await MediaStorage(store).write(progress);
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookSeriesPage(
            group: MediaGroup('a:saga', 'Saga', [book]),
            library: catalog,
            openBook: (_) async {},
            editBook: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Series menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose artwork'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member'));
      await tester.pumpAndSettle();
      expect(
        (await catalog.seriesMetadata('a:saga'))?.cover,
        '/missing/member.png',
      );
      expect((await catalog.books()).single.toJson(), book.toJson());
      expect(
        (await MediaStorage(store).read(book.id))?.toJson(),
        progress.toJson(),
      );
    },
  );

  test('shared metadata actions retain reference labels, ordering and capability disabling', () {
    final actions = mediaMetadataActions(
      settings: true,
      canArtwork: false,
    ).cast<PopupMenuItem<String>>();
    expect(actions.map((a) => (a.child as Text).data), [
      'Settings',
      'Edit metadata',
      'Choose artwork',
      'Find metadata online',
    ]);
    expect(actions.elementAt(2).enabled, false);
    expect(mediaMetadataActions(includeFind: false).length, 2);
  });
  testWidgets(
    'audiobook details uses saved Continue state and prevents duplicate opening',
    (tester) async {
      final store = SharedStore();
      final book = audiobook('Title');
      final catalog = createAudioLibrary(store);
      await catalog.save([book]);
      await MediaStorage(store).write(
        AudiobookProgress(
          book.id,
          chapterId: book.chapterMarkers.first.id,
          positionMs: 1000,
          finished: false,
        ),
      );
      final finished = Completer<void>();
      var launches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookDetailsPage(
            library: catalog,
            book: book,
            edit: () async {},
            play: () async {
              launches++;
              await finished.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Opening…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Opening…'))
            .onPressed,
        isNull,
      );
      expect(launches, 1);
      finished.complete();
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
    },
  );
  testWidgets(
    'cover grid remains square and scrollable through its parent on narrow layouts',
    (tester) async {
      tester.view.physicalSize = const Size(240, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: SingleChildScrollView(
                child: MediaArtworkGrid(
                  children: [
                    ColoredBox(color: Colors.red),
                    ColoredBox(color: Colors.blue),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.red),
      );
      expect(size.width, 240);
      expect(size.height, 240);
      expect(find.byType(GridView), findsNothing);
    },
  );

  testWidgets(
    'series artwork offers existing audiobook covers without a device picker or network call',
    (tester) async {
      String? selected;
      final book = audiobook('First')
          .withMetadata({'cover': '/not-present/cover.png'});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await chooseSeriesArtwork(
                  context,
                  search: MetadataWorkflow(const [
                    AudiobookMetadataProvider('audible'),
                    AudiobookMetadataProvider('audiobookdb'),
                  ], mutations: const OwnerApplicationMutations()),
                  imports: const NativeMediaImports(),
                  download: (url, source) => const AudiobookMetadataService()
                      .cover(url, provider: source),
                  title: 'Saga',
                  books: [book],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Find artwork with a plugin'), findsOneWidget);
      await tester.tap(find.text('First'));
      await tester.pumpAndSettle();
      expect(selected, book.metadata.cover);
    },
  );
  for (final individual in [false, true]) {
    testWidgets(
      'artwork without plugins performs no legacy provider I/O (individual: $individual)',
      (tester) async {
        const channel = MethodChannel('multiplexr/audio');
        final calls = <MethodCall>[];
        String? selected;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            if (call.method == 'searchMetadata') {
              return jsonEncode([
                {
                  'title': 'Online cover',
                  'coverUrl': 'https://audiobookdb.org/cover/large.jpg',
                  'metadataSource': 'audiobookdb',
                },
              ]);
            }
            if (call.method == 'metadataCover') return 'downloaded-cover';
            throw StateError('Unexpected method: ${call.method}');
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = individual
                      ? await chooseAudiobookCover(
                          context,
                          search: MetadataWorkflow(const [
                            AudiobookMetadataProvider('audible'),
                            AudiobookMetadataProvider('audiobookdb'),
                          ], mutations: const OwnerApplicationMutations()),
                          imports: const NativeMediaImports(),
                          download: (url, source) =>
                              const AudiobookMetadataService().cover(
                                url,
                                provider: source,
                              ),
                          title: 'Title',
                        )
                      : await chooseSeriesArtwork(
                          context,
                          search: MetadataWorkflow(const [
                            AudiobookMetadataProvider('audible'),
                            AudiobookMetadataProvider('audiobookdb'),
                          ], mutations: const OwnerApplicationMutations()),
                          imports: const NativeMediaImports(),
                          download: (url, source) =>
                              const AudiobookMetadataService().cover(
                                url,
                                provider: source,
                              ),
                          title: 'Saga',
                          books: [],
                        );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        await tester.tap(find.text('Find artwork with a plugin'));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(selected, isNull);
        expect(find.text('No plugin platform is available.'), findsOneWidget);
      },
    );
  }
  testWidgets('individual artwork retains device selection', (tester) async {
    const channel = MethodChannel('multiplexr/audio');
    String? selected;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return 'data:image/jpeg;base64,AA==';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await chooseAudiobookCover(
                context,
                search: MetadataWorkflow(const [
                  AudiobookMetadataProvider('audible'),
                  AudiobookMetadataProvider('audiobookdb'),
                ], mutations: const OwnerApplicationMutations()),
                imports: const NativeMediaImports(),
                download: (url, source) => const AudiobookMetadataService()
                    .cover(url, provider: source),
                title: 'Title',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('Find artwork with a plugin'), findsOneWidget);
    await tester.tap(find.text('Select image from device'));
    await tester.pumpAndSettle();
    expect(calls, ['pickCover']);
    expect(selected, 'data:image/jpeg;base64,AA==');
  });
}
