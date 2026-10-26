import 'support/space_controls.dart';
import 'fixtures/legacy_video_details.dart';
import 'fixtures/legacy_metadata_assembly.dart' show historicalVideo;

import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/main.dart';
import 'package:multiplexr/src/platform_service.dart';
import 'package:multiplexr/src/library/library_models.dart';

import 'fixtures/legacy_library_service.dart';

import 'package:multiplexr/src/features/metadata/application/video_metadata_policy.dart';
import 'package:multiplexr/src/library/catalog.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/library/video_space.dart';
import 'package:multiplexr/src/library/video_art.dart';

class MatchingLibrary extends MemoryLibrary {
  final queries = <String>[];
  @override
  Future<bool> metadataConfigured() async => true;
  @override
  Future<List<Map<String, dynamic>>> search(String type, String query) async {
    queries.add(query);
    return query == 'Arrival'
        ? [
            {'id': 1, 'title': 'Arrival', 'release_date': '2016-11-11'},
          ]
        : [];
  }

  @override
  Future<Map<String, dynamic>> details(
    String type,
    int id, {
    int? season,
    int? episode,
  }) async => {
    'title': 'Arrival',
    'release_date': '2016-11-11',
    'overview': 'Fetched summary',
    'backdrop_path': '/landscape.jpg',
    'runtime': 116,
    'tagline': 'A test tagline',
    'credits': {
      'cast': [
        {'name': 'Actor One'},
      ],
    },
  };
}

class MemoryLibrary extends LibraryService {
  @override
  Future<Map<String, Map<String, dynamic>?>> readStates(
    List<String> keys,
  ) async => {for (final key in keys) key: await readState(key)};
  @override
  Object get persistenceOwner => this;
  final Map<String, Map<String, dynamic>> states = {};
  @override
  Future<Map<String, dynamic>?> readState(String key) async => states[key];
  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    if (value == null) {
      states.remove(key);
    } else {
      states[key] = Map<String, dynamic>.from(value)
        ..['remaining'] = List<String>.from(value['remaining'] ?? []);
    }
  }

  final List<Map<String, dynamic>> collections = [];
  final List<Map<String, dynamic>> assets = [];
  bool failSave = false;
  @override
  Future<Map<String, dynamic>> load() async => {
    'collections': collections,
    'assets': assets,
  };
  List<String> savedQueue = [];
  @override
  Future<void> saveQueue(List<String> queue) async {
    savedQueue = List.of(queue);
  }

  @override
  Future<void> saveSeriesIndex(Map<String, dynamic> index) async {}
  @override
  Future<void> updateFlags(
    List<VideoAsset> selected,
    String action,
    bool value,
  ) async {
    for (final asset in selected) {
      final i = assets.indexWhere(
        (a) => a['id'] == asset.id && a['collectionId'] == asset.collectionId,
      );
      if (i >= 0) {
        assets[i] = {
          ...assets[i],
          (action == 'hideContinue' ? 'hiddenFromContinue' : action): value,
          if (action == 'watched') ...{
            'positionMs': 0,
            'completedAt': value ? 123 : 0,
          },
        };
      }
    }
  }

  @override
  Future<void> saveGrouping(List<VideoAsset> selected) async {
    if (failSave) throw StateError('save failed');
    for (final asset in selected) {
      final i = assets.indexWhere(
        (a) => a['id'] == asset.id && a['collectionId'] == asset.collectionId,
      );
      if (i >= 0) {
        assets[i] = {
          ...assets[i],
          'metadata': asset.metadata,
          'metadataSource': 'manual',
        };
      }
    }
  }

  @override
  Future<void> saveBrowsing(String id, Map<String, dynamic> values) async {
    final index = collections.indexWhere((c) => c['id'] == id);
    if (index >= 0) collections[index] = {...collections[index], ...values};
  }

  @override
  Future<void> saveCollection(VideoCollection collection) async {
    if (failSave) throw Exception('disk failure');
    collections.removeWhere((c) => c['id'] == collection.id);
    collections.add(collection.toJson());
  }

  @override
  Future<void> saveAsset(VideoAsset asset, {bool preserveTags = false}) async {
    assets.removeWhere((a) => a['id'] == asset.id);
    assets.add(asset.toJson());
  }

  @override
  Future<void> applyMetadataPatch(
    VideoAsset before,
    VideoAsset after,
    Set<String> selected,
  ) => saveAsset(after, preserveTags: true);
  @override
  Future<bool> metadataConfigured() async => false;
  @override
  Future<void> removeCollection(String id) async {
    collections.removeWhere((c) => c['id'] == id);
    assets.removeWhere((a) => a['collectionId'] == id);
  }

  @override
  Future<LibraryRoot?> pickRoot() async =>
      const LibraryRoot('content://test/tree/videos', 'Videos');
}

class LibraryDevice extends PlatformService {
  LibraryDevice({this.lock = false});
  final bool lock;
  @override
  Future<Map<String, dynamic>> load() async => {
    'supported': true,
    'lockEnabled': lock,
    'secureDevice': true,
  };
  @override
  Future<bool> authenticate() async => true;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test(
    'merged Movies & TV preserves legacy TV roots and per-file schemas',
    () async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'tv',
          name: 'Shows',
          subtype: VideoSubtype.tv,
          roots: [LibraryRoot('content://shows', 'Shows')],
        ).toJson(),
      );
      service.assets.add({
        'id': 'episode',
        'collectionId': 'tv',
        'uri': 'content://episode',
        'filename': 'Pilot.mp4',
        'positionMs': 1234,
      });
      final library = createLibraryController(
        service,
        metadataWorkflow: () =>
            historicalVideo(createLibraryController(service)),
      );
      await library.load();
      expect(library.collections.single.subtype, VideoSubtype.cinema);
      expect(
        library.collections.single.roots.single.contentSubtype,
        VideoSubtype.tv,
      );
      expect(library.assets.single.mediaSubtype, VideoSubtype.tv);
      expect(library.assets.single.positionMs, 1234);
      final root = LibraryRoot.fromJson(
        const LibraryRoot(
          'content://tv',
          'TV',
          contentSubtype: VideoSubtype.tv,
        ).toJson(),
      );
      expect(root.contentSubtype, VideoSubtype.tv);
      final movie = VideoAsset.fromJson({
        'id': 'm',
        'collectionId': 'tv',
        'uri': 'content://movie',
        'filename': 'Example.S01E01.mp4',
        'contentSubtype': 'movies',
      }, VideoSubtype.cinema);
      expect(movie.mediaSubtype, VideoSubtype.movies);
      expect(movie.metadata.containsKey('season'), false);
    },
  );
  testWidgets('video space has its own feed, search, and real resume filter', (
    tester,
  ) async {
    final service = MemoryLibrary();
    service.collections.add(
      const VideoCollection(
        id: 'c',
        name: 'Personal',
        subtype: VideoSubtype.videos,
      ).toJson(),
    );
    for (final title in ['Holiday', 'Walk']) {
      service.assets.add(
        VideoAsset(
          id: title,
          collectionId: 'c',
          uri: 'content://$title',
          filename: '$title.mp4',
          metadata: {'title': title},
          addedAt: 42,
          durationMs: 120000,
          positionMs: title == 'Holiday' ? 30000 : 0,
        ).toJson(),
      );
    }
    final library = createLibraryController(
      service,
      metadataWorkflow: () => historicalVideo(createLibraryController(service)),
    );
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
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('Collection actions'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Manage collection'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Enter Multiplexr video space'));
    await tester.pumpAndSettle();
    expect(find.byType(MultiplexrVideoSpace), findsOneWidget);
    expect(find.byType(VideoFeedCard), findsWidgets);
    await openSpaceControls(tester);
    await tester.tap(find.text('Continue watching'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoFeedCard), findsOneWidget);
    expect(find.text('Holiday'), findsOneWidget);
    await openSpaceControls(tester);
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(find.byType(MultiplexrVideoSpace), findsNothing);
    await openSpaceControls(tester);
    await tester.enterText(find.byType(TextField).first, 'Walk');
    await tester.pumpAndSettle();
    expect(find.text('Walk'), findsNWidgets(2));
    expect(find.text('Holiday'), findsNothing);
    expect(find.text('Filters'), findsOneWidget);
  });
  test('TMDB matching keeps landscape artwork separate from posters', () async {
    final asset = VideoAsset.fromJson({
      'id': 'a',
      'collectionId': 'c',
      'uri': 'content://a',
      'filename': 'Arrival.2016.mp4',
      'positionMs': 2500,
      'addedAt': 42,
    }, VideoSubtype.movies);
    final matched = await matchedAsset(
      MatchingLibrary(),
      asset,
      VideoSubtype.movies,
      {'id': 1, 'poster_path': '/portrait.jpg'},
    );
    expect(matched.backdrop, 'https://image.tmdb.org/t/p/w1280/landscape.jpg');
    expect(matched.poster, 'https://image.tmdb.org/t/p/w342/portrait.jpg');
    expect(matched.metadata['runtimeMinutes'], '116');
    expect(matched.metadata['cast'], 'Actor One');
    expect(matched.positionMs, 2500);
    expect(matched.addedAt, 42);
    expect(
      VideoAsset.fromJson(matched.toJson(), VideoSubtype.movies).backdrop,
      matched.backdrop,
    );
  });
  testWidgets('cinema title taps show artwork and metadata without playing', (
    tester,
  ) async {
    final service = MemoryLibrary();
    service.collections.add(
      const VideoCollection(
        id: 'c',
        name: 'Movies',
        subtype: VideoSubtype.movies,
      ).toJson(),
    );
    service.assets.add(
      const VideoAsset(
        id: 'a',
        collectionId: 'c',
        uri: 'content://a',
        filename: 'Arrival.mp4',
        metadata: {
          'title': 'Arrival',
          'description': 'Movie overview',
          'year': '2016',
        },
      ).toJson(),
    );
    final library = createLibraryController(
      service,
      metadataWorkflow: () => historicalVideo(createLibraryController(service)),
    );
    await library.load();
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MultiplexrCinema(
          library: library,
          collectionId: 'c',
          collectionName: 'Movies',
          play: (_, _) async {
            plays++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Arrival').first);
    await tester.pumpAndSettle();
    expect(plays, 0);
    expect(find.text('Movie overview'), findsOneWidget);
    expect(find.text('2016'), findsOneWidget);
    await openSpaceControls(tester);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(plays, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Arrival')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Arrival'));
    await tester.pumpAndSettle();
    expect(plays, 1);
    expect(find.text('Movie overview'), findsOneWidget);
  });
  test(
    'Netflix rows exclude completed videos and sort actual indexing dates',
    () {
      VideoAsset asset(String id, int added, int position) => VideoAsset(
        id: id,
        collectionId: 'c',
        uri: 'content://$id',
        filename: '$id.mp4',
        metadata: {'title': id},
        addedAt: added,
        positionMs: position,
        durationMs: 100,
      );
      final items = [
        asset('old', 10, 30),
        asset('new', 20, 0),
        asset('complete', 0, 100),
      ];
      expect(continuingVideos(items).map((a) => a.id), ['old']);
      expect(recentlyAddedVideos(items).map((a) => a.id), ['new', 'old']);
      expect(
        VideoAsset.fromJson(items.first.toJson(), VideoSubtype.movies).addedAt,
        10,
      );
    },
  );
  testWidgets(
    'shared layouts persist and Overview supports search and details',
    (tester) async {
      final service = MemoryLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Films',
          subtype: VideoSubtype.movies,
        ).toJson(),
      );
      service.assets.add(
        const VideoAsset(
          id: 'a',
          collectionId: 'c',
          uri: 'content://a',
          filename: 'Arrival.2016.mp4',
          metadata: {'title': 'Arrival', 'description': 'A real overview'},
          addedAt: 20,
          durationMs: 10000,
          positionMs: 2000,
        ).toJson(),
      );
      final library = createLibraryController(
        service,
        metadataWorkflow: () =>
            historicalVideo(createLibraryController(service)),
      );
      await library.load();
      Widget screen() => MaterialApp(
        home: CollectionCatalog(
          library: library,
          collectionId: 'c',
          notifications: LibraryDevice(),
        ),
      );
      await tester.pumpWidget(screen());
      for (final mode in [
        CatalogView.grid,
        CatalogView.list,
        CatalogView.compact,
      ]) {
        await openSpaceControls(tester);
        await tester.tap(find.byTooltip('Collection settings'));
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<CatalogView>),
        );
        await openSpaceControls(tester);
        await tester.tap(find.byType(DropdownButtonFormField<CatalogView>));
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.tap(find.text(mode.label).last);
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.ensureVisible(find.text('Save collection'));
        await openSpaceControls(tester);
        await tester.tap(find.text('Save collection'));
        await tester.pumpAndSettle();
        expect(service.collections.single['view'], mode.name);
      }
      await openSpaceControls(tester);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.byType(MultiplexrCinema), findsOneWidget);
      await openSpaceControls(tester);
      await openSpaceControls(tester);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Filters'), findsNothing);
      expect(service.collections.single['view'], 'compact');
      expect(find.text('Resume'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A real overview'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextField).first, 'No match');
      await tester.pumpAndSettle();
      expect(find.text('No matching videos'), findsOneWidget);
      expect(find.byType(MultiplexrCinema), findsNothing);
      expect(find.text('Filters'), findsOneWidget);
      expect(service.collections.single['view'], 'compact');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.byType(MultiplexrCinema), findsOneWidget);
    },
  );
  testWidgets(
    'bulk fetch covers the collection and preserves existing metadata',
    (tester) async {
      final service = MatchingLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Films',
          subtype: VideoSubtype.movies,
        ).toJson(),
      );
      for (final entry in {
        'Arrival.2016.mp4': 'filename',
        'Unknown.2020.mp4': 'filename',
        'Manual.2020.mp4': 'manual',
        'Matched.2020.mp4': 'tmdb',
      }.entries) {
        service.assets.add(
          VideoAsset.fromJson({
            'id': entry.key,
            'collectionId': 'c',
            'uri': 'content://${entry.key}',
            'filename': entry.key,
            'metadataSource': entry.value,
          }, VideoSubtype.movies).toJson(),
        );
      }
      final library = createLibraryController(
        service,
        metadataWorkflow: () =>
            historicalVideo(createLibraryController(service)),
      );
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
      await openSpaceControls(tester);
      await tester.enterText(find.byType(TextField).first, 'Arrival');
      await tester.pump();
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection actions'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Manage collection'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Fetch missing metadata (2)'));
      await tester.pumpAndSettle();
      expect(service.queries, ['Arrival', 'Unknown']);
      expect(
        library
            .items('c')
            .firstWhere((a) => a.id == 'Arrival.2016.mp4')
            .metadata['description'],
        'Fetched summary',
      );
      expect(
        library
            .items('c')
            .firstWhere((a) => a.id == 'Manual.2020.mp4')
            .metadataSource,
        'manual',
      );
      expect(
        find.text('1 matched · 1 need review · 0 failed · 0 remaining'),
        findsOneWidget,
      );
      expect(find.text('Fetch missing metadata (1)'), findsNothing);
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('Collection actions'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Manage collection'));
      await tester.pumpAndSettle();
      expect(find.text('Fetch missing metadata (0)'), findsOneWidget);
    },
  );
  testWidgets('bulk fetch supports generic Videos collections', (tester) async {
    final service = MatchingLibrary();
    service.collections.add(
      VideoCollection(
        id: 'c',
        name: 'Films',
        subtype: VideoSubtype.videos,
      ).toJson(),
    );
    for (final entry in {
      'Arrival.2016.mp4': 'filename',
      'Unknown.2020.mp4': 'filename',
      'Manual.2020.mp4': 'manual',
      'Matched.2020.mp4': 'tmdb',
    }.entries) {
      service.assets.add(
        VideoAsset.fromJson({
          'id': entry.key,
          'collectionId': 'c',
          'uri': 'content://${entry.key}',
          'filename': entry.key,
          'metadataSource': entry.value,
        }, VideoSubtype.videos).toJson(),
      );
    }
    final library = createLibraryController(
      service,
      metadataWorkflow: () => historicalVideo(createLibraryController(service)),
    );
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
    await openSpaceControls(tester);
    await tester.enterText(find.byType(TextField).first, 'Arrival');
    await tester.pump();
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('Collection actions'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Manage collection'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Fetch missing metadata (2)'));
    await tester.pumpAndSettle();
    expect(service.queries, ['Arrival', 'Unknown']);
    expect(
      library
          .items('c')
          .firstWhere((a) => a.id == 'Arrival.2016.mp4')
          .metadata['description'],
      'Fetched summary',
    );
    expect(
      library
          .items('c')
          .firstWhere((a) => a.id == 'Manual.2020.mp4')
          .metadataSource,
      'manual',
    );
    expect(
      find.text('1 matched · 1 need review · 0 failed · 0 remaining'),
      findsOneWidget,
    );
    expect(find.text('Fetch missing metadata (1)'), findsNothing);
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('Collection actions'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Manage collection'));
    await tester.pumpAndSettle();
    expect(find.text('Fetch missing metadata (0)'), findsOneWidget);
  });
  test(
    'collection config and subtype-specific metadata survive serialization',
    () {
      const collection = VideoCollection(
        id: 'c',
        name: 'Movies',
        subtype: VideoSubtype.movies,
        view: CatalogView.list,
        player: PlaybackTarget.external,
        roots: [LibraryRoot('content://folder', 'Films')],
        extensions: ['mp4', 'mkv'],
      );
      final restored = VideoCollection.fromJson(collection.toJson());
      expect(restored.view, CatalogView.list);
      expect(restored.player, PlaybackTarget.external);
      expect(restored.roots.single.name, 'Films');
      expect(metadataFields[VideoSubtype.movies], contains('director'));
      expect(metadataFields[VideoSubtype.tv], contains('season'));
      expect(metadataFields[VideoSubtype.videos], isNot(contains('season')));
      final asset = VideoAsset.fromJson({
        'id': 'a',
        'collectionId': 'c',
        'uri': 'content://video',
        'filename': 'Arrival.2016.1080p.mkv',
        'positionMs': 2500,
      }, VideoSubtype.movies);
      expect(asset.metadata, {'title': 'Arrival', 'year': '2016'});
      expect(
        VideoAsset.fromJson(asset.toJson(), VideoSubtype.movies).positionMs,
        2500,
      );
    },
  );
  test(
    'filename inference parses TV numbering without inventing movie metadata',
    () {
      expect(
        inferMetadata('Example.Show.S02E03.Episode.Title.mkv', VideoSubtype.tv),
        {
          'title': 'Episode Title',
          'series': 'Example Show',
          'season': '2',
          'episode': '3',
        },
      );
      expect(inferMetadata('Holiday.2024.mp4', VideoSubtype.videos), {
        'title': 'Holiday 2024',
      });
    },
  );
  test(
    'automatic matches require exact titles, a movie year, and no ambiguity',
    () {
      final asset = VideoAsset.fromJson({
        'id': 'a',
        'collectionId': 'c',
        'uri': 'content://video',
        'filename': 'Arrival.2016.mkv',
      }, VideoSubtype.movies);
      final correct = {
        'id': 1,
        'title': 'Arrival',
        'release_date': '2016-11-10',
      };
      final wrongYear = {
        'id': 2,
        'title': 'Arrival',
        'release_date': '2020-01-01',
      };
      expect(
        confidentMatch(asset, VideoSubtype.movies, [correct, wrongYear]),
        correct,
      );
      expect(
        confidentMatch(asset, VideoSubtype.movies, [
          correct,
          {...correct, 'id': 3},
        ]),
        isNull,
      );
      expect(
        confidentMatch(
          VideoAsset.fromJson({
            ...asset.toJson(),
            'metadata': {'title': 'Arrival'},
            'metadataSource': 'manual',
          }, VideoSubtype.movies),
          VideoSubtype.movies,
          [correct],
        ),
        isNull,
      );
      final episode = VideoAsset.fromJson({
        'id': 'e',
        'collectionId': 'c',
        'uri': 'content://episode',
        'filename': 'Example.Show.S01E02.mkv',
      }, VideoSubtype.tv);
      expect(
        confidentMatch(episode, VideoSubtype.tv, [
          {'id': 1, 'name': 'Example Show'},
        ]),
        isNotNull,
      );
      expect(
        confidentMatch(episode, VideoSubtype.tv, [
          {'id': 1, 'name': 'Similar Show'},
        ]),
        isNull,
      );
    },
  );
  test('failed persistence never creates an in-memory collection', () async {
    final service = MemoryLibrary()..failSave = true;
    final library = createLibraryController(
      service,
      metadataWorkflow: () => historicalVideo(createLibraryController(service)),
    );
    await library.load();
    await expectLater(
      library.save(
        const VideoCollection(
          id: 'c',
          name: 'Test',
          subtype: VideoSubtype.videos,
        ),
      ),
      throwsException,
    );
    expect(library.collections, isEmpty);
  });
  testWidgets(
    'header plus opens video creation and saves a real empty collection',
    (tester) async {
      final service = MemoryLibrary();
      await tester.pumpWidget(
        MultiplexrApp(platform: LibraryDevice(), libraryService: service),
      );
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('LIBRARY').first);
      final add = tester.getRect(find.byTooltip('New collection'));
      expect((title.center.dy - add.center.dy).abs(), lessThan(1));
      await openSpaceControls(tester);
      await tester.tap(find.byTooltip('New collection'));
      await tester.pumpAndSettle();
      expect(find.text('New collection'), findsOneWidget);
      expect(find.text('Root folders'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Personal videos',
      );
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Create collection').hitTestable(),
        250,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await openSpaceControls(tester);
      await tester.ensureVisible(find.text('Create collection'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Create collection'));
      await tester.pumpAndSettle();
      expect(service.collections.single['name'], 'Personal videos');
      expect(find.text('Personal videos'), findsOneWidget);
      expect(find.text('No videos in this view'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Personal videos'), findsOneWidget);
    },
  );
  testWidgets('app lock covers the collection modal as well as the library', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiplexrApp(
        platform: LibraryDevice(lock: true),
        libraryService: MemoryLibrary(),
      ),
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('New collection'));
    await tester.pumpAndSettle();
    expect(find.text('New collection'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.text('Multiplexr is locked'), findsOneWidget);
    expect(find.text('New collection'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('New collection'), findsOneWidget);
  });
}
