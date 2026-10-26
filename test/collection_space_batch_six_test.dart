import 'support/space_controls.dart';
import 'fixtures/legacy_library_assembly.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/features/catalog/application/collection_presenter.dart';
import 'package:multiplexr/src/features/catalog/application/space_queries.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/audio_library.dart';
import 'package:multiplexr/src/media/audiobooks_page.dart';
import 'package:multiplexr/src/media/audiobook_cover.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:app_shell/app_shell.dart';

import 'grouped_media_test.dart' show audiobook;
import 'media_foundation_test.dart' show SharedStore;

class FailingAudioStore extends SharedStore {
  bool fail = false;
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    if (fail && key == AudioLibrary.key) throw StateError('Unavailable');
    return super.readState(key);
  }
}

class TestCollectionJob implements CollectionJob {
  int cancellations = 0, disposals = 0;
  @override
  bool get running => false;
  @override
  int get done => 0;
  @override
  int get total => 0;
  @override
  void cancel() {
    cancellations++;
  }

  @override
  void dispose() {
    disposals++;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });

  test('collection owns job cancellation and disposes each job once', () {
    final controller = CollectionController<String, String>(identity: (s) => s);
    final job = controller.ownJob(TestCollectionJob());
    expect(controller.jobs, [job]);
    controller.dispose();
    controller.dispose();
    expect(job.cancellations, 1);
    expect(job.disposals, 1);
    expect(controller.jobs, isEmpty);
  });

  test('newer load wins, failures retain contents and disposal rejects late results', () async {
    final controller = CollectionController<String, String>(identity: (s) => s);
    final older = Completer<List<String>>();
    final task = controller.load(() => older.future, failure: 'Failed');
    await controller.load(() async => ['new'], failure: 'Failed');
    older.complete(['old']);
    expect(await task, false);
    expect(controller.items, ['new']);
    await controller.load(
      () async => throw StateError('storage'),
      failure: 'Failed',
    );
    expect(controller.items, ['new']);
    expect(controller.error, 'Failed');
    final late = Completer<List<String>>();
    final lateTask = controller.load(() => late.future, failure: 'Failed');
    controller.dispose();
    late.complete(['late']);
    expect(await lateTask, false);
    expect(controller.items, ['new']);
  });

  test(
    'refresh prunes deleted selections without losing query or other selection',
    () {
      final controller =
          CollectionController<String, String>(identity: (s) => s)
            ..replace(['a', 'b'])
            ..query = 'saved'
            ..folder = 'folder'
            ..selecting = true;
      controller.selected.addAll(['a', 'b']);
      controller.replace(['b', 'c']);
      expect(controller.selected, {'b'});
      expect(controller.query, 'saved');
      expect(controller.folder, 'folder');
      controller.endSelection();
      expect(controller.selected, isEmpty);
      expect(controller.selecting, false);
    },
  );

  test(
    'each subtype shares local/global exclusion and authorization rules',
    () {
      for (final subtype in [
        MediaSubtype.moviesTv,
        MediaSubtype.videos,
        MediaSubtype.audiobooks,
      ]) {
        final collection = CatalogCollection(
          id: 'c',
          name: 'C',
          subtype: subtype,
          access: const CatalogAccess(locked: true, includeInGlobal: false),
          roots: [],
        );
        expect(
          SpaceScope(subtype).includes(collection, authorized: true),
          false,
        );
        expect(
          SpaceScope(
            subtype,
            collectionId: 'c',
          ).includes(collection, authorized: true),
          true,
        );
        expect(
          SpaceScope(
            subtype,
            collectionId: 'c',
          ).includes(collection, authorized: false),
          false,
        );
        expect(
          SpaceScope(
            subtype,
            collectionId: 'other',
          ).includes(collection, authorized: true),
          false,
        );
      }
    },
  );

  test('pins retain order, remove ineligible references and enforce three distinct items', () {
    final controller = SpaceController<String, String>(identity: (s) => s);
    expect(
      controller.showcase(
        ['a', 'b', 'c', 'd'],
        ['b', 'b', 'locked', 'a', 'c', 'd'],
        pinned: true,
      ),
      ['b', 'a'],
    );
    final all = ['finished', 'active'];
    expect(
      controller.browsing(
        all,
        hideCompleted: true,
        completed: (s) => s == 'finished',
      ),
      ['active'],
    );
    expect(all, ['finished', 'active']);
  });

  for (final view in [
    CatalogView.compact,
    CatalogView.list,
    CatalogView.grid,
  ]) {
    testWidgets(
      'audiobook $view retains hierarchy and authorized excluded collection',
      (tester) async {
        final store = SharedStore();
        store.collections.add(
          VideoCollection(
            id: 'a',
            name: 'Audio',
            kind: MediaKind.audiobook,
            subtype: VideoSubtype.videos,
            view: view,
            includeInGlobalAudio: false,
          ).toJson(),
        );
        await createAudioLibrary(store).save([audiobook('Standalone')]);
        final library = createLibraryController(store);
        await library.load();
        await tester.pumpWidget(
          MaterialApp(
            home: AudiobooksPage(
              catalog: library.audiobookCatalog(collectionId: 'a'),
              libraryController: library,
              collectionId: 'a',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          view == CatalogView.grid
              ? find.byWidgetPredicate(
                  (w) => w is AudiobookArtworkTile && w.title == 'Standalone',
                )
              : find.text('Standalone'),
          findsOneWidget,
        );
        if (view == CatalogView.grid) {
          expect(find.byType(AudiobookArtworkTile), findsOneWidget);
        } else {
          final tile = tester.widget<ListTile>(
            find.widgetWithText(ListTile, 'Standalone'),
          );
          expect(tile.dense, view == CatalogView.compact);
        }
        await openSpaceControls(tester);
        await tester.enterText(find.byType(TextField).first, 'no match');
        await tester.pumpAndSettle();
        expect(find.text('No audiobooks in this view'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        library.dispose();
      },
    );
  }

  testWidgets(
    'audiobook loading failure has working retry without an empty-library message',
    (tester) async {
      final store = FailingAudioStore();
      await createAudioLibrary(store).save([audiobook('Recovered')]);
      store.fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobooksPage(
            catalog: createAudioLibrary(store, collectionId: 'a'),
            collectionId: 'a',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load the audiobook library.'),
        findsOneWidget,
      );
      expect(find.text('No audiobooks'), findsNothing);
      store.fail = false;
      await openSpaceControls(tester);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Recovered'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('return from series restores collection query and scroll', (
    tester,
  ) async {
    final store = SharedStore();
    store.collections.add(
      const VideoCollection(
        id: 'a',
        name: 'Audio',
        kind: MediaKind.audiobook,
        subtype: VideoSubtype.videos,
        view: CatalogView.list,
      ).toJson(),
    );
    await createAudioLibrary(store)
        .save([for (var i = 0; i < 30; i++) audiobook('Book $i')]);
    final library = createLibraryController(store);
    await library.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AudiobooksPage(
          catalog: library.audiobookCatalog(collectionId: 'a'),
          libraryController: library,
          collectionId: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    final searchController = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    await openSpaceControls(tester);
    await tester.enterText(find.byType(TextField).first, 'Book');
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.ensureVisible(find.text('Book 20'));
    await tester.pumpAndSettle();
    final sourceScroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final offset = sourceScroll.pixels;
    expect(offset, greaterThan(0));
    await openSpaceControls(tester);
    await tester.tap(find.text('Book 20'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(searchController.text, 'Book');
    expect(sourceScroll.pixels, closeTo(offset, 1));
    await tester.pumpWidget(const SizedBox());
    library.dispose();
  });
}
