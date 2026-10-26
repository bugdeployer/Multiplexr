import 'fixtures/legacy_metadata_assembly.dart' show historicalAudio;
import 'fixtures/legacy_metadata_settings.dart';

import 'fixtures/legacy_library_assembly.dart';
import 'package:multiplexr/src/media/audiobook_hierarchy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audiobook_space.dart';
import 'package:multiplexr/src/media/audiobooks_page.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/space_preferences.dart';

import 'grouped_media_test.dart' show audiobook;
import 'media_foundation_test.dart' show SharedStore;

class FailingSpaceStore extends SharedStore {
  bool fail = true;
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    if (fail && key == 'spaces:audiobooks:a') {
      throw StateError('storage unavailable');
    }
    return super.readState(key);
  }
}

void main() {
  test('Continue series prioritizes a started title and restarts the first after completion', () {
    final first = audiobook('First'), second = audiobook('Second');
    expect(
      audiobookResumeTarget(
        [first, second],
        {
          second.id: AudiobookProgress(
            second.id,
            chapterId: second.chapterMarkers.first.id,
            positionMs: 1000,
            finished: false,
          ),
        },
      ),
      second,
    );
    expect(
      audiobookResumeTarget(
        [first, second],
        {
          for (final book in [first, second])
            book.id: AudiobookProgress(
              book.id,
              chapterId: book.chapterMarkers.first.id,
              positionMs: 1000,
              finished: true,
            ),
        },
      ),
      first,
    );
    expect(audiobookResumeTarget([], {}), isNull);
  });

  test('concurrent scoped catalog writes retain both collections and series metadata', () async {
    final store = SharedStore();
    final a = createAudioLibrary(store, collectionId: 'a'),
        b = createAudioLibrary(store, collectionId: 'b');
    await Future.wait([
      a.save([audiobook('First')]),
      b.save([audiobook('Second', collection: 'b')]),
      a.saveSeriesMetadata(
        const AudiobookSeriesMetadata(
          id: 'series-a',
          collectionId: 'a',
          title: 'A',
        ),
      ),
      b.saveSeriesMetadata(
        const AudiobookSeriesMetadata(
          id: 'series-b',
          collectionId: 'b',
          title: 'B',
        ),
      ),
    ]);
    expect((await createAudioLibrary(store).books()).length, 2);
    expect((await a.seriesMetadata('series-a'))?.title, 'A');
    expect((await b.seriesMetadata('series-b'))?.title, 'B');
  });
  test('concurrent title edits and a rejected mutation do not erase other titles or poison later saves', () async {
    final store = SharedStore();
    final library = createAudioLibrary(store);
    final a = audiobook('A'), b = audiobook('B');
    await library.save([a, b]);
    await Future.wait([
      library.replace(a.withMetadata({'author': 'Author A'})),
      library.replace(b.withMetadata({'author': 'Author B'})),
    ]);
    expect((await library.books()).map((b) => b.metadata.author), [
      'Author A',
      'Author B',
    ]);
    await expectLater(library.replace(audiobook('missing')), throwsStateError);
    await library.replace(a.withMetadata({'title': 'Updated'}));
    expect((await library.books()).first.metadata.title, 'Updated');
  });
  test(
    'saving one space preserves settings edited by another open space',
    () async {
      final store = SharedStore();
      final first = SpacePreferences(), second = SpacePreferences();
      await first.load(store.userPreferences);
      await second.load(store.userPreferences);
      first.cinema.confirmExit = false;
      second.audiobooks.pins = ['["a","title"]'];
      second.audiobooks.source = 'pinned';
      await Future.wait([
        first.save(store.userPreferences),
        second.save(store.userPreferences),
      ]);
      final restored = SpacePreferences();
      await restored.load(store.userPreferences);
      expect(restored.cinema.confirmExit, false);
      expect(restored.audiobooks.pins, ['["a","title"]']);
    },
  );
  testWidgets('local space settings read failure leaves a retryable screen', (
    tester,
  ) async {
    final store = FailingSpaceStore();
    final library = createLibraryController(store)
      ..collections = [
        const VideoCollection(
          id: 'a',
          name: 'Audio',
          subtype: VideoSubtype.videos,
          kind: MediaKind.audiobook,
        ),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: AudiobookSpace(library: library, collectionId: 'a'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load space settings. Try again.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    store.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load space settings. Try again.'),
      findsNothing,
    );
  });
  testWidgets(
    'metadata credentials disable empty saves and recover from a failed key without losing connection',
    (tester) async {
      var calls = 0;
      var credential = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataCredentialCard(
              name: 'Catalog',
              label: 'API key',
              configured: () async => true,
              save: (value) async {
                calls++;
                credential = value;
                if (value == 'bad') {
                  throw PlatformException(
                    code: 'authentication',
                    message: 'Invalid key',
                  );
                }
              },
              footer: 'Catalog',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Verify and save'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pump();
      await tester.tap(find.text('Verify and save'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid key'), findsOneWidget);
      expect(find.textContaining('Connected'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'good');
      await tester.pump();
      await tester.tap(find.text('Verify and save'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(credential, 'good');
      expect(find.text('Invalid key'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets('audiobook metadata batch stops after authentication failure', (
    tester,
  ) async {
    final store = SharedStore();
    await createAudioLibrary(store)
        .save([audiobook('First'), audiobook('Second')]);
    var searches = 0;
    const channel = MethodChannel('multiplexr/audio');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'metadataDbConfigured') return true;
      if (call.method == 'searchMetadata') {
        searches++;
        throw PlatformException(code: 'authentication', message: 'Invalid key');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AudiobooksPage(
          catalog: createAudioLibrary(
            store,
            collectionId: 'a',
            metadataWorkflow: historicalAudio,
          ),
          collectionId: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch missing metadata'));
    await tester.pumpAndSettle();
    expect(searches, 1);
    expect(find.text('Invalid key'), findsOneWidget);
    expect(
      (store.states['metadata:audiobooks:a']!['entries'] as Map).length,
      1,
    );
  });
}
