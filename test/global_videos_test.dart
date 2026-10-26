import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/bootstrap/app_composition.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/library/video_space.dart';
import 'package:multiplexr/src/library/video_scope.dart';
import 'package:multiplexr/src/library/video_art.dart';
import 'package:multiplexr/src/library/collection_form.dart';
import 'package:multiplexr/src/library/queue_view.dart';

import 'library_test.dart' show MemoryLibrary;

import 'package:multiplexr/src/shell.dart';
import 'package:multiplexr/src/library/catalog.dart';

import 'widget_test.dart' show TestDevice;

class VideosStorage extends MemoryLibrary {
  bool failQueue = false;
  final Map<String, List<int>> positions = {};
  @override
  Future<void> saveQueue(List<String> items) async {
    if (failQueue) throw StateError('Storage full');
    await super.saveQueue(items);
  }

  @override
  Future<void> watchState(VideoAsset asset, String action) async {}
  @override
  Future<void> position(VideoAsset asset, int point) async {
    positions.putIfAbsent(asset.collectionId, () => []).add(point);
  }
}

Future<LibraryController> videosLibrary({
  VideosStorage? storage,
  int extra = 0,
}) async {
  final service = storage ?? VideosStorage();
  for (final id in ['a', 'b', 'private', 'excluded', 'movies']) {
    service.collections.add(
      VideoCollection(
        id: id,
        name: id.toUpperCase(),
        subtype: id == 'movies' ? VideoSubtype.cinema : VideoSubtype.videos,
        locked: id == 'private',
        includeInGlobalVideos: id != 'excluded',
        roots: const [LibraryRoot('root', 'Files')],
      ).toJson(),
    );
    service.assets.add(
      VideoAsset(
        id: 'same',
        collectionId: id,
        uri: 'content://$id/same',
        filename: '$id.mp4',
        metadata: {
          'title': id == 'a'
              ? 'A old clip'
              : id == 'b'
              ? 'Z new clip'
              : id,
          'tags': id == 'a' ? 'Travel, Summer' : 'Family',
        },
        relativePath: 'Trips/$id.mp4',
        rootUri: 'root',
        addedAt: id == 'a' ? 10 : 20,
        positionMs: 4200,
        durationMs: id == 'a' ? 3600000 : 10000,
      ).toJson(),
    );
  }
  for (var n = 0; n < extra; n++) {
    service.assets.add(
      VideoAsset(
        id: 'extra$n',
        collectionId: 'b',
        uri: 'content://b/extra$n',
        filename: 'clip$n.mp4',
        metadata: {'title': 'Clip $n'},
        addedAt: 100 + n,
        positionMs: 4200,
        durationMs: 10000,
      ).toJson(),
    );
  }
  final library = createLibraryController(service);
  await library.load();
  return library;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  testWidgets(
    'Spaces opens global Videos and source navigation returns to the same feed',
    (tester) async {
      final library = await videosLibrary();
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            settings: settings,
            library: library,
            sessions: AppComposition.createSessions(
              settings: settings,
              library: library,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('SPACES'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Open Videos'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Videos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MultiplexrVideoSpace>(find.byType(MultiplexrVideoSpace))
            .collectionId,
        isNull,
      );
      await tester.ensureVisible(
        find.byTooltip('Video actions for Z new clip'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Video actions for Z new clip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open source collection'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CollectionCatalog>(find.byType(CollectionCatalog))
            .collectionId,
        'b',
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(MultiplexrVideoSpace), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    },
  );

  test('global Videos includes only opted-in unlocked Videos, while local access remains independent', () async {
    final library = await videosLibrary();
    expect(globalVideoCollections(library).map((c) => c.id), ['a', 'b']);
    expect(videoSpaceItems(library).map((a) => a.collectionId), ['a', 'b']);
    expect(videoSpaceItems(library, collectionId: 'excluded'), hasLength(1));
    expect(videoSpaceItems(library, collectionId: 'private'), isEmpty);
    library.beginCollectionSession('private');
    library.authorizeCollection('private');
    expect(videoSpaceItems(library, collectionId: 'private'), hasLength(1));
    expect(globalVideoCollections(library).map((c) => c.id), ['a', 'b']);
    final legacy = {...library.collections.first.toJson()}
      ..remove('includeInGlobalVideos');
    expect(VideoCollection.fromJson(legacy).includeInGlobalVideos, true);
  });
  test('feed filters use scoped folders, tags and real newest-first ordering without a 20-video limit', () async {
    final library = await videosLibrary(extra: 25);
    final source = videoSpaceItems(library);
    final a = source.firstWhere((a) => a.collectionId == 'a');
    final b = source.firstWhere((a) => a.id == 'same' && a.collectionId == 'b');
    expect(videoFolderKey(a), isNot(videoFolderKey(b)));
    expect(browseVideoFeed(source), hasLength(27));
    expect(browseVideoFeed(source).first.id, 'extra24');
    expect(
      browseVideoFeed(source, folder: videoFolderKey(a)).single.collectionId,
      'a',
    );
    expect(
      browseVideoFeed(
        source,
        tag: 'travel',
        query: 'Trips',
      ).single.collectionId,
      'a',
    );
    expect(browseVideoFeed(source, sort: 'duration').first.collectionId, 'a');
    expect(feedDuration(3600000), '1:00:00');
  });
  test(
    'scoped queue reorder preserves unrelated slots and rolls back failures',
    () async {
      final storage = VideosStorage();
      final library = await videosLibrary(storage: storage);
      final a = videoSpaceItems(library).first,
          b = videoSpaceItems(library).last;
      final other = library.items('excluded').single;
      await library.enqueue(a);
      await library.enqueue(other);
      await library.enqueue(b);
      await library.reorderQueued([b, a]);
      expect(library.queuedVideos.map((a) => a.collectionId), [
        'b',
        'excluded',
        'a',
      ]);
      expect(videoSpaceQueue(library).map((a) => a.collectionId), ['b', 'a']);
      expect(
        videoSpaceQueue(library, collectionId: 'a').single.collectionId,
        'a',
      );
      storage.failQueue = true;
      await expectLater(library.reorderQueued([a, b]), throwsStateError);
      expect(videoSpaceQueue(library).map((a) => a.collectionId), ['b', 'a']);
    },
  );
  testWidgets('Videos settings persist a separate global inclusion toggle', (
    tester,
  ) async {
    final library = await videosLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionForm(
          library: library,
          existing: library.collections.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Include in global Videos'));
    await tester.tap(find.text('Include in global Videos'));
    await tester.ensureVisible(find.text('Save collection'));
    await tester.tap(find.text('Save collection'));
    await tester.pumpAndSettle();
    final saved = library.collections.firstWhere((c) => c.id == 'a');
    expect(saved.includeInGlobalVideos, false);
    expect(saved.includeInGlobalCinema, true);
    expect(videoSpaceItems(library).single.collectionId, 'b');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'global feed uses inline menus, scoped source actions and tag filters',
    (tester) async {
      final library = await videosLibrary();
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrVideoSpace(
            library: library,
            openCollection: (c) async {
              opened = c.id;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<VideoFeedCard>(find.byType(VideoFeedCard))
            .first
            .asset
            .collectionId,
        'b',
      );
      await tester.ensureVisible(
        find.byTooltip('Video actions for Z new clip'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Video actions for Z new clip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open source collection'));
      await tester.pumpAndSettle();
      expect(opened, 'b');
      expect(find.byTooltip('Feed options'), findsNothing);
      await tester.tap(find.text('Overview & filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Feed options'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Travel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VideoFeedCard>(find.byType(VideoFeedCard))
            .asset
            .collectionId,
        'a',
      );
      await tester.tap(find.byTooltip('Search videos'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'family');
      await tester.pumpAndSettle();
      expect(find.text('No matching videos'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide space controls'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('No matching videos'), findsOneWidget);
      await tester.tap(find.text('Browse & filters'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'family',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('queue shows explicit ordering and drag handles', (tester) async {
    final library = await videosLibrary();
    for (final a in videoSpaceItems(library)) {
      await library.enqueue(a);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showVideoQueue(
                context,
                library,
                (_) {},
                items: () => videoSpaceQueue(library),
              ),
              child: const Text('Queue'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byTooltip('Queue options for Z new clip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to next'));
    await tester.pumpAndSettle();
    expect(videoSpaceQueue(library).first.collectionId, 'b');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
