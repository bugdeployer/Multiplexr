import 'support/space_controls.dart';
import 'fixtures/legacy_metadata_assembly.dart';

import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';

import 'fixtures/legacy_library_service.dart';

import 'package:multiplexr/src/features/catalog/application/video_queries.dart';
import 'package:multiplexr/src/library/catalog.dart';
import 'package:multiplexr/src/library/cinema_view.dart';

import 'library_test.dart' show MemoryLibrary, LibraryDevice;

class FailingWriteLibrary extends BatchLibrary {
  int writes = 0;
  @override
  Future<void> saveAsset(VideoAsset asset, {bool preserveTags = false}) async {
    writes++;
    throw StateError('storage full');
  }
}

class DeferredLibrary extends LibraryService {
  @override
  Object get persistenceOwner => this;
  final requests = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> load() {
    final request = Completer<Map<String, dynamic>>();
    requests.add(request);
    return request.future;
  }
}

class ScanLibrary extends BatchLibrary {
  @override
  Future<List<String>> scan(String id, {String? requestId}) async => [];
}

class BatchLibrary extends MemoryLibrary {
  final queries = <String>[];
  final loadCounts = <int>[];
  final saved = <String>[];
  Completer<void>? gate;
  bool failNetwork = false;
  @override
  Future<bool> metadataConfigured() async => true;
  @override
  Future<Map<String, dynamic>> load() async {
    loadCounts.add(queries.length);
    return super.load();
  }

  @override
  Future<List<Map<String, dynamic>>> search(String type, String query) async {
    queries.add(query);
    if (gate != null) await gate!.future;
    if (failNetwork) throw StateError('offline');
    return [
      {'id': 1, 'title': query, 'release_date': '2020-01-01'},
    ];
  }

  @override
  Future<Map<String, dynamic>> details(
    String type,
    int id, {
    int? season,
    int? episode,
  }) async => {'title': queries.last, 'release_date': '2020-01-01'};
  @override
  Future<void> saveAsset(VideoAsset asset, {bool preserveTags = false}) async {
    saved.add(asset.id);
    await super.saveAsset(asset);
  }
}

VideoAsset video(String id, {Map<String, dynamic> extra = const {}}) =>
    VideoAsset.fromJson({
      'id': id,
      'collectionId': 'c',
      'uri': 'content://$id',
      'filename': 'Film $id (2020).mp4',
      ...extra,
    }, VideoSubtype.movies);
Future<LibraryController> batchSetup(BatchLibrary service, int count) async {
  service.collections.add(
    const VideoCollection(
      id: 'c',
      name: 'Movies',
      subtype: VideoSubtype.cinema,
    ).toJson(),
  );
  service.assets.addAll(List.generate(count, (i) => video('$i').toJson()));
  final library = createLibraryController(service);
  await library.load();
  return library;
}

void main() {
  test('watch history survives serialization and continuation ignores watched/hidden/unavailable', () {
    final items = [
      video(
        'resume',
        extra: {'positionMs': 1000, 'durationMs': 10000, 'lastPlayedAt': 20},
      ),
      video('older', extra: {'positionMs': 2000, 'lastPlayedAt': 10}),
      video(
        'watched',
        extra: {'positionMs': 2000, 'watched': true, 'completedAt': 30},
      ),
      video('hidden', extra: {'positionMs': 1000, 'hiddenFromContinue': true}),
      video('missing', extra: {'positionMs': 1000, 'available': false}),
    ];
    expect(continuingVideos(items).map((a) => a.id), ['resume', 'older']);
    final restored = VideoAsset.fromJson(
      items[2].toJson(),
      VideoSubtype.movies,
    );
    expect(restored.watched, true);
    expect(restored.completedAt, 30);
    expect(browseVideos(items, filter: 'watched').single.id, 'watched');
    expect(browseVideos(items, filter: 'unavailable').single.id, 'missing');
  });
  test(
    'sorts use numeric years, history and duration with stable title ties',
    () {
      final items = [
        video(
          'z',
          extra: {
            'metadata': {'title': 'Z', 'year': '1999'},
            'durationMs': 100,
            'lastPlayedAt': 4,
          },
        ),
        video(
          'a',
          extra: {
            'metadata': {'title': 'A', 'year': '2020'},
            'durationMs': 20,
            'lastPlayedAt': 8,
          },
        ),
      ];
      expect(browseVideos(items, sort: 'year').first.id, 'a');
      expect(browseVideos(items, sort: 'played').first.id, 'a');
      expect(browseVideos(items, sort: 'duration').first.id, 'z');
    },
  );
  test(
    'legacy collection defaults remain flat and browsing preferences persist',
    () {
      final original = const VideoCollection(
        id: 'c',
        name: 'C',
        subtype: VideoSubtype.videos,
      ).toJson()..remove('allowFolders');
      expect(VideoCollection.fromJson(original).allowFolders, false);
      final restored = VideoCollection.fromJson({
        ...original,
        'allowFolders': true,
        'sort': 'played',
        'filter': 'unwatched',
        'cardSize': 240.0,
        'scrollOffset': 400.0,
        'folder': folderToken('content://root', 'Season 1/'),
      });
      expect(
        restored.toJson()['folder'],
        folderToken('content://root', 'Season 1/'),
      );
      expect(restored.sort, 'played');
      expect(restored.cardSize, 240);
    },
  );
  test(
    'metadata runs 20 at a time and preserves matched and manual entries',
    () async {
      final service = BatchLibrary();
      final library = await batchSetup(service, 43);
      await library.load();
      service.assets.add(
        video(
          'manual',
          extra: {
            'metadataSource': 'manual',
            'metadata': {'title': 'My title'},
          },
        ).toJson(),
      );
      service.assets.add(
        video('matched', extra: {'metadataSource': 'tmdb'}).toJson(),
      );
      await library.load();
      service.loadCounts.clear();
      final job = createMetadataJob(library, library.collections.single);
      await job.run();
      expect(job.matched, 43);
      expect(job.batches, 3);
      expect(job.done, 43);
      expect(service.loadCounts, [20, 40, 43]);
      expect(service.saved, isNot(contains('manual')));
      expect(service.saved, isNot(contains('matched')));
      expect(
        library.items('c').firstWhere((a) => a.id == 'manual').title,
        'My title',
      );
    },
  );
  test('cancelled metadata leaves unprocessed assets retryable', () async {
    final service = BatchLibrary();
    final library = await batchSetup(service, 4);
    await library.load();
    service.gate = Completer<void>();
    final job = createMetadataJob(library, library.collections.single);
    final running = job.run();
    while (service.queries.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    job.cancel();
    service.gate!.complete();
    await running;
    expect(job.running, false);
    expect(job.done, 0);
    expect(service.saved, isEmpty);
    service.gate = null;
    await job.run();
    expect(job.matched, 4);
  });
  test(
    'network failures persist for retry without replacing manual data',
    () async {
      final service = BatchLibrary();
      final library = await batchSetup(service, 2);
      await library.load();
      service.failNetwork = true;
      final job = createMetadataJob(library, library.collections.single);
      await job.run();
      expect(job.failed, 2);
      expect(
        library.items('c').every((a) => a.metadataStatus == 'failed'),
        true,
      );
      service.failNetwork = false;
      await job.run(failedOnly: true);
      expect(job.matched, 2);
      expect(library.items('c').every((a) => a.metadataStatus.isEmpty), true);
    },
  );
  test(
    'database failures abort metadata without a second stale save',
    () async {
      final service = FailingWriteLibrary();
      final library = await batchSetup(service, 2);
      final job = createMetadataJob(library, library.collections.single);
      await expectLater(
        job.run(),
        throwsA(
          isA<MetadataFailure>().having(
            (e) => e.kind,
            'kind',
            MetadataFailureKind.storage,
          ),
        ),
      );
      expect(service.writes, 1);
      expect(job.running, false);
      expect(job.done, 0);
      expect(job.failed, 0);
      expect(
        library.items('c').every((a) => a.metadataSource == 'filename'),
        true,
      );
    },
  );
  test(
    'older asynchronous loads cannot roll back a newer library snapshot',
    () async {
      final service = DeferredLibrary();
      final library = createLibraryController(service);
      final first = library.load();
      final second = library.load();
      service.requests[1].complete({
        'collections': [
          const VideoCollection(
            id: 'new',
            name: 'New',
            subtype: VideoSubtype.videos,
          ).toJson(),
        ],
      });
      await second;
      service.requests[0].complete({
        'collections': [
          const VideoCollection(
            id: 'old',
            name: 'Old',
            subtype: VideoSubtype.videos,
          ).toJson(),
        ],
      });
      await first;
      expect(library.collections.single.id, 'new');
    },
  );
  test(
    'malformed records never partially replace the current library',
    () async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Original',
          subtype: VideoSubtype.videos,
        ).toJson(),
      );
      final library = createLibraryController(service);
      await library.load();
      service.collections[0] = {
        ...service.collections[0],
        'name': 'Uncommitted',
      };
      service.assets.add({'collectionId': 'c', 'id': 'broken'});
      await library.load();
      expect(library.error, isNotNull);
      expect(library.collections.single.name, 'Original');
      expect(library.assets, isEmpty);
    },
  );
  test('extension restrictions hide retained history until the file type is allowed again', () async {
    final service = MemoryLibrary();
    service.collections.add(
      const VideoCollection(
        id: 'c',
        name: 'C',
        subtype: VideoSubtype.videos,
        extensions: ['mp4'],
      ).toJson(),
    );
    service.assets.add(
      video(
        'mkv',
        extra: {'filename': 'clip.MKV', 'positionMs': 5000},
      ).toJson(),
    );
    final library = createLibraryController(service);
    await library.load();
    expect(library.items('c'), isEmpty);
    expect(library.assets.single.positionMs, 5000);
    await library.save(
      VideoCollection.fromJson({
        ...library.collections.single.toJson(),
        'extensions': ['mp4', 'mkv'],
      }),
    );
    expect(library.items('c').single.positionMs, 5000);
  });
  testWidgets(
    'grouped settings page saves subtype and appearance without losing metadata',
    (tester) async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Collection',
          subtype: VideoSubtype.videos,
        ).toJson(),
      );
      service.assets.add(
        video(
          'manual',
          extra: {
            'metadataSource': 'manual',
            'metadata': {'title': 'My title'},
          },
        ).toJson(),
      );
      final library = createLibraryController(service);
      await library.load();
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionCatalog(
            library: library,
            collectionId: 'c',
            notifications: LibraryDevice(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Allow folder viewing'), findsNothing);
      expect(find.text('Card size'), findsNothing);
      await openSpaceControls(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsNWidgets(2));
      expect(find.text('Card size'), findsNothing);
      Navigator.of(tester.element(find.text('Filters').last)).pop();
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection settings'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      for (final title in ['General', 'Appearance', 'Playback', 'Sources']) {
        expect(find.text(title), findsOneWidget);
      }
      await openSpaceControls(tester);
      await tester.tap(find.byType(DropdownButtonFormField<VideoSubtype>));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Movies & TV').last);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.byType(Slider));
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Allow folder viewing'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Allow folder viewing'));
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Save collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(library.collections.single.subtype, VideoSubtype.cinema);
      expect(library.collections.single.allowFolders, true);
      expect(library.collections.single.cardSize, isNot(180));
      expect(library.items('c').single.title, 'My title');
      expect(library.items('c').single.metadataSource, 'manual');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'switching Movies & TV to Videos clears an incompatible saved filter',
    (tester) async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'C',
          subtype: VideoSubtype.cinema,
          filter: 'tv',
        ).toJson(),
      );
      final library = createLibraryController(service);
      await library.load();
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionCatalog(
            library: library,
            collectionId: 'c',
            notifications: LibraryDevice(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection settings'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.byType(DropdownButtonFormField<VideoSubtype>));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Videos').last);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Save collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(library.collections.single.filter, 'all');
      await openSpaceControls(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'collection removal exists only in Danger zone and returns to library without restoring index',
    (tester) async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'C',
          subtype: VideoSubtype.videos,
        ).toJson(),
      );
      final library = createLibraryController(service);
      await library.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CollectionCatalog(
                      library: library,
                      collectionId: 'c',
                      notifications: LibraryDevice(),
                    ),
                  ),
                ),
                child: const Text('Open collection'),
              ),
            ),
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Open collection'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Collection view'), findsNothing);
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection actions'));
      await tester.pumpAndSettle();
      expect(find.text('Remove collection'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection settings'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Danger zone'));
      expect(find.text('Danger zone'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Remove collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Remove collection'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.collections, hasLength(1));
      await openSpaceControls(tester);
      await tester.tap(find.text('Remove collection'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove collection'));
      await tester.pumpAndSettle();
      expect(find.text('Open collection'), findsOneWidget);
      expect(library.collections, isEmpty);
      expect(service.collections, isEmpty);
    },
  );
  testWidgets('folder indexing never starts online metadata retrieval', (
    tester,
  ) async {
    final service = ScanLibrary();
    final library = await batchSetup(service, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionCatalog(
          library: library,
          collectionId: 'c',
          notifications: LibraryDevice(),
          scanOnOpen: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.queries, isEmpty);
    expect(library.scanning, isEmpty);
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('Collection actions'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Manage collection'));
    await tester.pumpAndSettle();
    expect(find.text('Fetch missing metadata (1)'), findsOneWidget);
    expect(find.text('Enter Multiplexr cinema'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'normal views show folders only when allowed and search stays recursive',
    (tester) async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Collection',
          subtype: VideoSubtype.videos,
          view: CatalogView.list,
          roots: [LibraryRoot('content://root', 'Device movies')],
        ).toJson(),
      );
      service.assets.addAll([
        video(
          'one',
          extra: {
            'rootUri': 'content://root',
            'relativePath': 'Nested/Film.mp4',
            'metadata': {'title': 'Nested film'},
          },
        ).toJson(),
        video(
          'two',
          extra: {
            'rootUri': 'content://root',
            'relativePath': 'Other.mp4',
            'metadata': {'title': 'Root film'},
          },
        ).toJson(),
      ]);
      final library = createLibraryController(service);
      await library.load();
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionCatalog(
            library: library,
            collectionId: 'c',
            notifications: LibraryDevice(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nested film'), findsOneWidget);
      expect(find.text('Allow folder viewing'), findsNothing);
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection settings'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Allow folder viewing'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Allow folder viewing'));
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Save collection'));
      await openSpaceControls(tester);
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(library.collections.single.allowFolders, true);
      expect(find.text('Nested film'), findsNothing);
      expect(find.text('Device movies'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.tap(find.text('Device movies'));
      await tester.pumpAndSettle();
      expect(find.text('Nested'), findsOneWidget);
      expect(find.text('Root film'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.tap(find.text('Nested'));
      await tester.pumpAndSettle();
      expect(find.text('Nested film'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Parent folder'));
      await tester.pumpAndSettle();
      expect(find.text('Nested'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextField), 'Nested film');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Nested film'),
        findsOneWidget,
      );
      expect(find.text('Nested'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
