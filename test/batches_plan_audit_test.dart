import 'fixtures/legacy_library_assembly.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/media/catalog_progress_adapter.dart';
import 'package:multiplexr/src/media/contracts.dart'
    show MediaId, MediaKind, AudiobookProgress;
import 'package:multiplexr/src/media/storage.dart';
import 'package:multiplexr/src/media/audiobook_details.dart';
import 'package:multiplexr/src/library/library_models.dart';

import 'grouped_media_test.dart' show audiobook;
import 'media_foundation_test.dart' show SharedStore;

class SettingsGateStore extends SharedStore {
  final gate = Completer<void>();
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    if (key.startsWith('media:settings:')) await gate.future;
    return super.readState(key);
  }
}

VideoAsset video(String id) => VideoAsset(
  id: id,
  collectionId: 'c',
  uri: 'content://video/$id',
  filename: '$id.mp4',
  metadata: {},
  durationMs: 1000,
  width: 100,
  height: 100,
  addedAt: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('neutral progress adapter retains legacy identity and rejects mismatches or unsupported types', () async {
    final store = SharedStore();
    final adapter = CatalogProgressAdapter(MediaStorage(store));
    final identity = CatalogIdentity('c', 'one', CatalogEntityKind.title);
    const legacy = MediaId(MediaKind.audiobook, 'c', 'one');
    final progress = AudiobookProgress(
      legacy,
      chapterId: 'chapter',
      positionMs: 500,
      finished: false,
    );
    await adapter.write(identity, MediaSubtype.audiobooks, progress);
    expect(store.states.containsKey('progress:${legacy.key}'), true);
    expect(
      (await adapter.read(identity, MediaSubtype.audiobooks))!.toJson(),
      progress.toJson(),
    );
    expect(
      () => adapter.write(
        CatalogIdentity('c', 'other', CatalogEntityKind.title),
        MediaSubtype.audiobooks,
        progress,
      ),
      throwsArgumentError,
    );
    expect(
      () => adapter.read(identity, MediaSubtype.comics),
      throwsUnsupportedError,
    );
    expect(
      () => legacyTitleId(
        CatalogIdentity('c', 'series', CatalogEntityKind.group),
        MediaSubtype.audiobooks,
      ),
      throwsArgumentError,
    );
  });
  test('two controllers preserve concurrent queue edits through the same repository owner', () async {
    final store = SharedStore();
    final first = createLibraryController(store),
        second = createLibraryController(store);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait([
      first.enqueue(video('one')),
      second.enqueue(video('two')),
    ]);
    expect(store.savedQueue, [
      first.queueKey(video('one')),
      first.queueKey(video('two')),
    ]);
  });
  testWidgets(
    'audiobook open rechecks collection authorization after async settings lookup',
    (tester) async {
      final store = SettingsGateStore();
      var allowed = true, played = false;
      final library = createAudioLibrary(
        store,
        collectionId: 'a',
        authorized: (_) => allowed,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => openAudiobookTitle(
                context,
                library,
                const VideoCollection(
                  id: 'a',
                  name: 'Audio',
                  subtype: VideoSubtype.cinema,
                  kind: MediaKind.audiobook,
                ),
                audiobook('One'),
                (_) async {
                  played = true;
                },
                () async {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      allowed = false;
      store.gate.complete();
      await tester.pumpAndSettle();
      expect(played, false);
    },
  );
  test('audiobook replacement cannot write after access is revoked', () async {
    final store = SharedStore();
    var allowed = true;
    final library = createAudioLibrary(
      store,
      collectionId: 'a',
      authorized: (_) => allowed,
    );
    final book = audiobook('One');
    await library.save([book]);
    allowed = false;
    await expectLater(
      library.replace(book.withMetadata({'title': 'Changed'})),
      throwsStateError,
    );
    expect(
      (await createAudioLibrary(store).books()).single.metadata.title,
      'One',
    );
  });
  test('unscoped audiobook edits preserve inaccessible titles and reject their modification', () async {
    final store = SharedStore();
    final first = audiobook('Allowed', collection: 'a');
    final locked = audiobook('Locked', collection: 'b');
    await createAudioLibrary(store).save([first, locked]);
    final scoped = createAudioLibrary(store, authorized: (id) => id == 'a');
    await scoped.update(
      (books) => [
        for (final book in books)
          book.id.collectionId == 'a'
              ? book.withMetadata({'title': 'Updated'})
              : book,
      ],
    );
    await expectLater(
      scoped.update(
        (books) => books.where((b) => b.id.collectionId != 'b').toList(),
      ),
      throwsStateError,
    );
    final saved = await createAudioLibrary(store).books();
    expect(saved.map((b) => b.metadata.title), ['Updated', 'Locked']);
  });
}
