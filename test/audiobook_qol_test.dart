import 'fixtures/legacy_library_assembly.dart';
import 'fixtures/legacy_audiobook_metadata_service.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:multiplexr/src/media/audiobook_cover.dart';
import 'package:multiplexr/src/media/audiobook_details.dart';
import 'package:flutter/material.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/collection_form.dart';
import 'package:multiplexr/src/media/contracts.dart';

import 'media_foundation_test.dart' show SharedStore;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audiobook_space.dart';
import 'package:multiplexr/src/space_preferences.dart';

import 'grouped_media_test.dart' show audiobook;

void main() {
  testWidgets('playback rebuilds retain decoded artwork provider', (
    tester,
  ) async {
    const data =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
    Widget screen() => const MaterialApp(home: AudiobookCover(cover: data));
    await tester.pumpWidget(screen());
    final before = tester.widget<Image>(find.byType(Image)).image;
    await tester.pumpWidget(screen());
    expect(
      identical(before, tester.widget<Image>(find.byType(Image)).image),
      isTrue,
    );
    await tester.pumpWidget(const MaterialApp(home: AudiobookCover(cover: '')));
    expect(find.byType(Image), findsNothing);
  });
  testWidgets(
    'audiobook selected external player routes content URI without opening internal player',
    (tester) async {
      MethodCall? request;
      const channel = MethodChannel('multiplexr/audio');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        request = call;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              page = context;
              return const SizedBox();
            },
          ),
        ),
      );
      var internal = false;
      final book = audiobook('test');
      await openAudiobookTitle(
        page,
        createAudioLibrary(SharedStore()),
        const VideoCollection(
          id: 'a',
          name: 'Audio',
          subtype: VideoSubtype.videos,
          kind: MediaKind.audiobook,
          player: PlaybackTarget.external,
        ),
        book,
        (_) async {
          internal = true;
        },
        () async {},
        forcePlay: true,
      );
      expect(request?.method, 'external');
      expect(request?.arguments, book.files.first.uri);
      expect(internal, false);
    },
  );
  test('AudiobookDB search passes provider identity to Android', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    MethodCall? request;
    const channel = MethodChannel('multiplexr/audio');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          request = call;
          return jsonEncode([]);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await const AudiobookMetadataService().find(
      'A title',
      provider: 'audiobookdb',
    );
    expect((request?.arguments as Map)['provider'], 'audiobookdb');
  });

  testWidgets(
    'local Audiobooks space includes its excluded collection only and saves isolated preferences',
    (tester) async {
      final store = SharedStore();
      final library = createLibraryController(store)
        ..collections = [
          VideoCollection(
            id: 'a',
            name: 'Local',
            subtype: VideoSubtype.videos,
            kind: MediaKind.audiobook,
            includeInGlobalAudio: false,
          ),
          VideoCollection(
            id: 'b',
            name: 'Other',
            subtype: VideoSubtype.videos,
            kind: MediaKind.audiobook,
          ),
        ];
      await createAudioLibrary(store).save([
        audiobook('Local title'),
        audiobook('Other title', collection: 'b'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookSpace(library: library, collectionId: 'a'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Local title'), findsOneWidget);
      expect(find.bySemanticsLabel('Other title'), findsNothing);
      await tester.tap(find.byTooltip('Space settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.states['spaces:audiobooks:a'], isNotNull);
      expect(store.states['spaces:display'], isNull);
    },
  );
  testWidgets(
    'Player settings shortcut exposes audio speed and autoplay without video controls',
    (tester) async {
      final library = createLibraryController(SharedStore());
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionForm(
            library: library,
            existing: VideoCollection(
              id: 'a',
              name: 'Audio',
              subtype: VideoSubtype.videos,
              kind: MediaKind.audiobook,
            ),
            initialSection: 'Playback',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Autoplay next audiobook').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Default playback speed'), findsNothing);
      expect(find.text('Default player'), findsOneWidget);
    },
  );

  test('showcase uses selected order and removes unavailable titles', () {
    final a = audiobook('a'), b = audiobook('b'), hidden = audiobook('hidden');
    final display = SpaceDisplay()
      ..source = 'pinned'
      ..pins = [
        audiobookShowcaseKey(b),
        audiobookShowcaseKey(hidden),
        audiobookShowcaseKey(a),
      ];
    expect(audiobookShowcaseTitles([a, b], display), [b, a]);
    expect(audiobookShowcaseTitles([], display), isEmpty);
  });
  test('automatic showcase and restored pins are limited to three', () {
    final books = [for (var i = 0; i < 5; i++) audiobook('$i')];
    final display = SpaceDisplay();
    expect(audiobookShowcaseTitles(books, display), books.take(3));
    display.restore({
      'source': 'pinned',
      'pins': books.map(audiobookShowcaseKey).toList(),
    });
    expect(display.pins.length, 3);
    expect(
      audiobookShowcaseTitles(books.reversed.toList(), display),
      books.take(3),
    );
  });
}
