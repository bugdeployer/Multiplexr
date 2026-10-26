import 'fixtures/legacy_library_assembly.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audio_library.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/audiobooks_page.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/storage.dart';

import 'media_foundation_test.dart' show SharedStore;

AudioFile file(String name, {String? id, int disc = 0, int track = 0}) =>
    AudioFile(
      id: id,
      uri: 'content://audio/$name',
      filename: '$name.mp3',
      durationMs: 60000,
      disc: disc,
      track: track,
    );
Audiobook book({String collection = 'audiobooks'}) => Audiobook(
  id: MediaId(MediaKind.audiobook, collection, 'book'),
  metadata: const AudiobookMetadata(
    title: 'A book',
    author: 'Author',
    narrator: 'Reader',
    description: 'Keep this',
  ),
  files: [
    file('Chapter 1', id: 'one'),
    file('Chapter 2', id: 'two'),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('audiobook import fits a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: AudiobookEditorPage(
          library: createAudioLibrary(SharedStore()),
          files: book().files,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('book and music metadata round trip without shared field meanings', () {
    final b = book().metadata;
    const m = MusicMetadata(
      title: 'Track',
      artist: 'Band',
      album: 'Album',
      albumArtist: 'Various',
      year: 2024,
    );
    expect(AudiobookMetadata.fromJson(b.toJson()).toJson(), b.toJson());
    expect(MusicMetadata.fromJson(m.toJson()).toJson(), m.toJson());
    expect(b.toJson(), isNot(contains('artist')));
    expect(m.toJson(), isNot(contains('author')));
    expect(m.toJson(), isNot(contains('narrator')));
  });
  test('chapter ordering uses disc/track tags and natural filenames deterministically', () {
    final ordered = orderedAudioFiles([
      file('Chapter 10'),
      file('Chapter 2'),
      file('Chapter 1'),
      file('Z', track: 1),
      file('A', track: 2),
      file('Disc 2', disc: 2, track: 1),
      file('Chapter 1'),
    ]);
    expect(ordered.map((f) => f.filename), [
      'Z.mp3',
      'A.mp3',
      'Chapter 1.mp3',
      'Chapter 2.mp3',
      'Chapter 10.mp3',
      'Disc 2.mp3',
    ]);
  });
  test('a multi-file book owns one identity and progress; chapters have stable IDs', () {
    final b = Audiobook.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(book().toJson()))),
    );
    expect(b.durationMs, 120000);
    expect(b.record.chapters.map((c) => c.id), ['one', 'two']);
    expect(b.record.id, book().id);
    expect(b.files.first.displayTitle, 'Chapter 1');
  });
  test(
    'resume chooses stable chapter identity, never filename or item ID alone',
    () {
      final b = book();
      final request = AudioPlaybackRequest.audiobook(
        b,
        AudiobookProgress(
          b.id,
          chapterId: 'two',
          positionMs: 31000,
          finished: false,
        ),
      );
      expect(request.index, 1);
      expect(request.positionMs, 31000);
      expect(request.toJson()['files'][1]['id'], 'two');
      expect(
        () => AudioPlaybackRequest.audiobook(
          b,
          AudiobookProgress(
            book(collection: 'other').id,
            chapterId: 'two',
            positionMs: 3,
            finished: false,
          ),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'finished books and missing chapters start safely at the first chapter',
    () {
      final b = book();
      for (final p in [
        AudiobookProgress(
          b.id,
          chapterId: 'two',
          positionMs: 60000,
          finished: true,
        ),
        AudiobookProgress(
          b.id,
          chapterId: 'removed',
          positionMs: 50000,
          finished: false,
        ),
      ]) {
        final request = AudioPlaybackRequest.audiobook(b, p);
        expect(request.index, 0);
        expect(request.positionMs, 0);
      }
    },
  );
  test('audio catalog persists separately and overlapping imports cannot duplicate books', () async {
    final service = SharedStore();
    service.assets.add({
      'id': 'video',
      'metadata': {'title': 'Keep video'},
    });
    final before = jsonEncode(service.assets);
    final library = createAudioLibrary(service);
    final added = await library.add(
      const AudiobookMetadata(title: '英雄'),
      book().files,
    );
    expect((await createAudioLibrary(service).books()).single.id, added.id);
    await expectLater(
      library.add(const AudiobookMetadata(title: 'Duplicate'), [
        book().files.first,
      ]),
      throwsStateError,
    );
    expect((await library.books()).length, 1);
    expect(jsonEncode(service.assets), before);
  });
  test('reconnection changes source URIs without losing book/chapter progress or bookmarks', () async {
    final service = SharedStore();
    final library = createAudioLibrary(service), b = book();
    await library.save([b]);
    final storage = MediaStorage(service);
    await storage.write(
      AudiobookProgress(
        b.id,
        chapterId: 'two',
        positionMs: 22000,
        finished: false,
        bookmarks: const [AudiobookBookmark('one', 4000, 'Note')],
      ),
    );
    await library.replace(
      Audiobook(
        id: b.id,
        metadata: b.metadata,
        files: [
          file('Moved 1', id: 'one'),
          file('Moved 2', id: 'two'),
        ],
      ),
    );
    final reconnected = (await library.books()).single;
    final progress = await storage.read(b.id) as AudiobookProgress;
    expect(reconnected.files[1].uri, contains('Moved 2'));
    expect(AudioPlaybackRequest.audiobook(reconnected, progress).index, 1);
    expect(progress.positionMs, 22000);
    expect(progress.bookmarks.single.chapterId, 'one');
  });
  test(
    'unsupported catalogs fail visibly rather than being overwritten by import',
    () async {
      final service = SharedStore();
      await service.writeState(AudioLibrary.key, {'version': 99, 'books': []});
      await expectLater(
        createAudioLibrary(service)
            .add(const AudiobookMetadata(title: 'Book'), [file('one')]),
        throwsFormatException,
      );
      expect(service.states[AudioLibrary.key]!['version'], 99);
    },
  );
  test('invalid or duplicated book chapters are rejected', () {
    expect(
      () => Audiobook(id: book().id, metadata: book().metadata, files: []),
      throwsArgumentError,
    );
    expect(
      () => Audiobook(
        id: book().id,
        metadata: book().metadata,
        files: [file('one'), file('one')],
      ),
      throwsArgumentError,
    );
    expect(
      () => Audiobook(
        id: book().id,
        metadata: book().metadata,
        files: [
          file('one', id: 'same'),
          file('two', id: 'same'),
        ],
      ),
      throwsArgumentError,
    );
  });
  testWidgets(
    'import review validates the title and persists one book with multiple chapters',
    (tester) async {
      final service = SharedStore();
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookEditorPage(
            library: createAudioLibrary(service),
            files: book().files,
          ),
        ),
      );
      await tester.tap(find.text('Add book'));
      await tester.pump();
      expect(find.text('Enter a book title'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'My book');
      await tester.tap(find.text('Add book'));
      await tester.pumpAndSettle();
      final saved = (await createAudioLibrary(service).books()).single;
      expect(saved.metadata.title, 'My book');
      expect(saved.files.length, 2);
    },
  );
  testWidgets('editing book metadata preserves fields outside the form', (
    tester,
  ) async {
    final service = SharedStore();
    final library = createAudioLibrary(service);
    await library.save([book()]);
    await tester.pumpWidget(
      MaterialApp(
        home: AudiobookEditorPage(
          library: library,
          files: book().files,
          existing: book(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await tester.tap(find.text('Save book'));
    await tester.pumpAndSettle();
    final saved = (await library.books()).single;
    expect(saved.metadata.description, 'Keep this');
    expect(saved.metadata.title, 'Renamed');
    expect(saved.id, book().id);
  });
  testWidgets(
    'player resumes through audio bridge without a video platform view',
    (tester) async {
      final service = SharedStore();
      final b = book();
      await MediaStorage(service).write(
        AudiobookProgress(
          b.id,
          chapterId: 'two',
          positionMs: 22000,
          finished: false,
        ),
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('multiplexr/audio'), (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'state') {
              return jsonEncode({
                'id': b.id.toJson(),
                'index': 1,
                'positionMs': 22000,
                'durationMs': 60000,
                'playing': true,
                'rate': 1.25,
              });
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('multiplexr/audio'),
              null,
            ),
      );
      final catalog = createAudioLibrary(service);
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookPlayerPage(book: b, catalog: catalog),
        ),
      );
      await tester.pump();
      await tester.pump();
      final request = jsonDecode(
        calls.firstWhere((c) => c.method == 'open').arguments,
      );
      expect(request['index'], 1);
      expect(request['positionMs'], 22000);
      expect(find.byType(AndroidView), findsNothing);
      expect(find.text('Chapter 2 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(calls.any((c) => c.method == 'playPause'), true);
      await tester.pumpWidget(const SizedBox());
      catalog.audio.dispose();
    },
  );
}
