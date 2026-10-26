import 'fixtures/legacy_video_details.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/library/series.dart';
import 'package:multiplexr/src/library/series_view.dart';
import 'package:multiplexr/src/library/catalog.dart';
import 'package:multiplexr/src/features/catalog/application/video_queries.dart';
import 'package:multiplexr/src/library/watch_details.dart';
import 'package:multiplexr/src/library/cinema_view.dart';

import 'library_test.dart' show MemoryLibrary, LibraryDevice;

VideoAsset episode(
  String id,
  int season,
  int number, {
  int? provider = 10,
  String root = 'root',
  bool watched = false,
  bool available = true,
  int position = 0,
  int lastPlayed = 0,
  bool favorite = false,
}) => VideoAsset.fromJson({
  'id': id,
  'collectionId': 'c',
  'uri': 'content://$id',
  'filename':
      'Show.S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}.$id.mp4',
  'rootUri': root,
  'relativePath': 'Show/Season $season/$id.mp4',
  'contentSubtype': 'tv',
  'metadataSource': provider == null ? 'filename' : 'tmdb',
  'providerId': provider,
  'seriesId': provider,
  'metadata': {
    'title': 'Episode $number',
    'series': 'The Show',
    'season': '$season',
    'episode': '$number',
    'description': 'Real episode summary',
  },
  'watched': watched,
  'available': available,
  'positionMs': position,
  'durationMs': 10000,
  'lastPlayedAt': lastPlayed,
  'favorite': favorite,
}, VideoSubtype.tv);
Future<LibraryController> libraryOf(
  MemoryLibrary service,
  List<VideoAsset> assets, {
  VideoSubtype subtype = VideoSubtype.cinema,
}) async {
  service.collections.add(
    VideoCollection(
      id: 'c',
      name: 'Collection',
      subtype: subtype,
      view: CatalogView.list,
    ).toJson(),
  );
  service.assets.addAll(assets.map((a) => a.toJson()));
  final library = createLibraryController(service);
  await library.load();
  return library;
}

class QueueStorage extends MemoryLibrary {
  bool failQueue = false;
  @override
  Future<void> saveQueue(List<String> queue) async {
    if (failQueue) throw StateError('full');
    await super.saveQueue(queue);
  }

  @override
  Future<Map<String, dynamic>> load() async => {
    ...await super.load(),
    'queue': savedQueue,
  };
}

class DelayedQueueStorage extends QueueStorage {
  Completer<void>? writeGate;
  Completer<void>? loadGate;
  @override
  Future<void> saveQueue(List<String> queue) async {
    await writeGate?.future;
    await super.saveQueue(queue);
  }

  @override
  Future<Map<String, dynamic>> load() async {
    final snapshot = await super.load();
    snapshot['queue'] = List<String>.from(snapshot['queue']);
    await loadGate?.future;
    return snapshot;
  }
}

class IndexedLibrary extends MemoryLibrary {
  Map<String, dynamic>? index;
  @override
  Future<Map<String, dynamic>> load() async => {
    ...await super.load(),
    'seriesIndexSupported': true,
  };
  @override
  Future<void> saveSeriesIndex(Map<String, dynamic> value) async {
    index = value;
  }
}

class TvMetadata extends MemoryLibrary {
  @override
  Future<Map<String, dynamic>> details(
    String type,
    int id, {
    int? season,
    int? episode,
  }) async => {
    'id': 1002,
    'name': 'Pilot',
    'episode_number': episode,
    'overview': 'Episode overview',
    'still_path': '/episode.jpg',
    'series': {
      'name': 'The Show',
      'overview': 'Series overview',
      'backdrop_path': '/series.jpg',
      'poster_path': '/poster.jpg',
      'genres': [
        {'name': 'Drama'},
      ],
    },
  };
}

void main() {
  test('large series snapshots reuse derived episodes and seasons', () {
    final assets = [
      for (var n = 1; n <= 2000; n++)
        episode('e$n', (n - 1) ~/ 20 + 1, (n - 1) % 20 + 1),
    ];
    final series = buildSeries(assets).single;
    expect(series.episodes.length, 2000);
    expect(series.seasons.length, 100);
    expect(identical(series.episodes, series.episodes), true);
    expect(identical(series.seasons, series.seasons), true);
    expect(identical(series.card, series.card), true);
    expect(nextEpisode(assets[19], assets)!.id, 'e21');
  });

  test('choosing series art preserves episode metadata and its still', () {
    final original = VideoAsset.fromJson({
      ...episode('a', 1, 1).toJson(),
      'backdrop': 'still.jpg',
      'localBackdrop': '/still.jpg',
      'seriesBackdrop': 'old.jpg',
      'localSeriesBackdrop': '/old.jpg',
    }, VideoSubtype.tv);
    final updated = withSelectedArtwork(
      original,
      'backdrops',
      'new.jpg',
      series: true,
    );
    expect(updated.title, original.title);
    expect(updated.metadata, {
      ...original.metadata,
      'seriesBackdropSource': 'manual',
    });
    expect(updated.backdrop, 'still.jpg');
    expect(updated.localBackdrop, '/still.jpg');
    expect(updated.seriesBackdrop, 'new.jpg');
    expect(updated.localSeriesBackdrop, isNull);
  });

  test(
    'a load started during a queue write cannot restore its old snapshot',
    () async {
      final service = DelayedQueueStorage();
      final a = episode('a', 1, 1);
      final library = await libraryOf(service, [a]);
      service.writeGate = Completer<void>();
      final write = library.enqueue(a);
      await Future<void>.delayed(Duration.zero);
      service.loadGate = Completer<void>();
      final load = library.load();
      await Future<void>.delayed(Duration.zero);
      service.writeGate!.complete();
      await write;
      service.loadGate!.complete();
      await load;
      expect(library.queuedVideos.single.id, 'a');
    },
  );
  testWidgets('series menu hides every episode from Continue watching', (
    tester,
  ) async {
    final service = MemoryLibrary();
    final library = await libraryOf(service, [
      episode('a', 1, 1),
      episode('b', 1, 2, position: 3000, lastPlayed: 100),
    ]);
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
    await tester.tap(find.byTooltip('Options for The Show'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an episode'), findsOneWidget);
    await tester.tap(find.text('Remove from Continue watching'));
    await tester.pumpAndSettle();
    expect(library.items('c').every((a) => a.hiddenFromContinue), isTrue);
    expect(seriesContinuation(library.items('c')), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('series lookup scopes duplicate file IDs to their collection', () {
    final first = episode('same', 1, 1);
    final other = VideoAsset.fromJson({
      ...first.toJson(),
      'collectionId': 'other',
      'seriesId': 20,
    }, VideoSubtype.tv);
    final next = VideoAsset.fromJson({
      ...episode('next', 1, 2).toJson(),
      'collectionId': 'other',
      'seriesId': 20,
    }, VideoSubtype.tv);
    expect(seriesFor(other, [first, other, next])!.assets.length, 2);
    expect(nextEpisode(other, [first, other, next])!.id, 'next');
  });
  test(
    'series artwork uses cached show backdrop without changing episode still',
    () {
      final original = VideoAsset.fromJson({
        ...episode('a', 1, 1).toJson(),
        'backdrop': 'episode.jpg',
        'localBackdrop': '/episode.jpg',
        'seriesBackdrop': 'show.jpg',
        'localSeriesBackdrop': '/show.jpg',
      }, VideoSubtype.tv);
      final series = buildSeries([original]).single;
      expect(series.artwork.backdrop, 'show.jpg');
      expect(series.card.localBackdrop, '/show.jpg');
      expect(original.backdrop, 'episode.jpg');
      expect(original.localBackdrop, '/episode.jpg');
    },
  );

  test('matched series spans roots while local series stay scoped to roots and folders', () {
    expect(
      buildSeries([
        episode('a', 1, 1, root: 'one'),
        episode('b', 2, 1, root: 'two'),
      ]),
      hasLength(1),
    );
    expect(
      buildSeries([
        episode('a', 1, 1, provider: null, root: 'one'),
        episode('b', 2, 1, provider: null, root: 'two'),
      ]),
      hasLength(2),
    );
    expect(
      buildSeries([
        episode('a', 1, 1, provider: null),
        episode('b', 2, 1, provider: null),
      ]).single.seasons,
      hasLength(2),
    );
  });
  test(
    'duplicate files are versions of one episode and preserve each source',
    () {
      final series = buildSeries([episode('a', 1, 1), episode('b', 1, 1)])
          .single;
      expect(series.episodes, hasLength(1));
      expect(series.episodes.single.versions.map((a) => a.uri), [
        'content://a',
        'content://b',
      ]);
      expect(series.episodes.single.toJson()['assetIds'], ['a', 'b']);
    },
  );
  test('next episode skips missing files and Specials across seasons', () {
    final a = episode('a', 1, 1);
    final b = episode('b', 1, 2, available: false);
    final c = episode('c', 2, 1);
    final special = episode('special', 0, 1);
    expect(nextEpisode(a, [special, a, b, c])?.id, 'c');
    expect(nextEpisode(special, [special, a, c]), isNull);
  });
  test(
    'invalid episode numbers never create fake seasons or autoplay candidates',
    () {
      final bad = episode('bad', -1, 0);
      final series = buildSeries([bad]).single;
      expect(series.seasons, isEmpty);
      expect(series.episodes.single.number, isNull);
      expect(series.resume, isNull);
      expect(seriesContinuation([bad]), isEmpty);
    },
  );
  test('autoplay never chooses among duplicate versions', () {
    final a = episode('a', 1, 1);
    final copies = [episode('b', 1, 2), episode('c', 1, 2)];
    expect(nextEpisode(a, [a, ...copies]), isNull);
    expect(nextEpisodeRecord(a, [a, ...copies])!.versions, hasLength(2));
  });
  test('series continuation is one item and advances completed episodes', () {
    final a = episode('a', 1, 1, watched: true, lastPlayed: 100);
    final b = episode('b', 1, 2);
    final continuing = seriesContinuation([a, b]);
    expect(continuing.single.id, 'b');
    expect(continuing.single.lastPlayedAt, 100);
    expect(
      seriesContinuation([
        episode('a', 1, 1, position: 2000, lastPlayed: 100),
        episode('b', 1, 2, position: 4000, lastPlayed: 200),
      ]).single.id,
      'b',
    );
  });
  test(
    'unknown episode numbers are isolated instead of merged by guessed titles',
    () {
      final a = VideoAsset.fromJson({
        ...episode('a', 1, 1, provider: null).toJson(),
        'filename': 'unidentified.mp4',
        'relativePath': 'Unknown/unidentified.mp4',
        'metadata': {'title': 'unknown'},
      }, VideoSubtype.tv);
      expect(buildSeries([a]).single.needsIdentification, true);
      expect(buildSeries([a]).single.resume, isNull);
    },
  );
  test('folder-based numbering and alternate names parse without guessing multi-episode files', () {
    final inferred = inferMetadata(
      '02 - Pilot.mp4',
      VideoSubtype.tv,
      relativePath: 'Show/Season 3/02 - Pilot.mp4',
      rootUri: 'root',
    );
    expect(inferred['series'], 'Show');
    expect(inferred['season'], '3');
    expect(inferred['episode'], '2');
    expect(inferMetadata('Show.1x03.mp4', VideoSubtype.tv)['episode'], '3');
    expect(
      inferMetadata(
        'Show.S01E01-E02.mp4',
        VideoSubtype.tv,
      ).containsKey('episode'),
      false,
    );
  });
  test('TV matching separates series artwork and episode identity', () async {
    final result = await matchedAsset(
      TvMetadata(),
      episode('a', 1, 2),
      VideoSubtype.tv,
      {'id': 10, 'name': 'The Show'},
    );
    expect(result.seriesId, 10);
    expect(result.episodeId, 1002);
    expect(result.metadata['description'], 'Episode overview');
    expect(result.metadata['seriesOverview'], 'Series overview');
    expect(result.seriesBackdrop, contains('/series.jpg'));
    expect(result.backdrop, contains('/episode.jpg'));
  });
  test('Favorites and Watch later persist independently without modifying metadata or progress', () async {
    final service = MemoryLibrary();
    final library = await libraryOf(service, [
      episode('a', 1, 1, position: 2000),
    ]);
    await library.flags(library.items('c'), 'favorite', true);
    await library.flags(library.items('c'), 'watchLater', true);
    final a = library.items('c').single;
    expect(a.favorite, true);
    expect(a.watchLater, true);
    expect(a.positionMs, 2000);
    expect(a.metadataSource, 'tmdb');
    expect(browseVideos([a], filter: 'favorite'), hasLength(1));
    await library.flags([a], 'favorite', false);
    expect(library.items('c').single.watchLater, true);
  });
  test('saved queue deduplicates, reorders, survives reload and rolls back storage failure', () async {
    final service = QueueStorage();
    final library = await libraryOf(service, [
      episode('a', 1, 1),
      episode('b', 1, 2),
    ], subtype: VideoSubtype.videos);
    final a = library.assets[0], b = library.assets[1];
    await library.enqueue(a);
    await library.enqueue(b);
    await library.enqueue(b, next: true);
    expect(library.queuedVideos.map((a) => a.id), ['b', 'a']);
    await library.load();
    expect(library.queuedVideos.map((a) => a.id), ['b', 'a']);
    service.failQueue = true;
    await expectLater(library.removeQueued(b), throwsStateError);
    expect(library.queuedVideos.map((a) => a.id), ['b', 'a']);
    service.failQueue = false;
    await library.removeQueued(b);
    expect(library.queuedVideos.single.id, 'a');
  });
  test('series cards aggregate flags across episodes', () {
    final series = buildSeries([
      episode('a', 1, 1),
      episode('b', 1, 2, favorite: true),
    ]).single;
    expect(series.card.favorite, true);
  });
  test('series materialization links records to original files without changing progress', () async {
    final service = IndexedLibrary();
    final library = await libraryOf(service, [
      episode('a', 1, 1, position: 2000),
      episode('b', 1, 1),
      episode('c', 2, 1),
    ]);
    expect(service.index!['series'], hasLength(1));
    expect(service.index!['seasons'], hasLength(2));
    expect(service.index!['episodes'], hasLength(2));
    expect((service.index!['episodes'] as List).first['assetIds'], ['a', 'b']);
    expect(library.items('c').first.positionMs, 2000);
  });
  test('legacy filename metadata gains folder numbering without replacing custom fields', () {
    final a = VideoAsset.fromJson({
      'id': 'a',
      'collectionId': 'c',
      'uri': 'content://a',
      'filename': '02 - Pilot.mp4',
      'rootUri': 'root',
      'relativePath': 'Show/Season 2/02 - Pilot.mp4',
      'contentSubtype': 'tv',
      'metadataSource': 'filename',
      'metadata': {'title': 'Kept title'},
    }, VideoSubtype.tv);
    expect(a.metadata['title'], 'Kept title');
    expect(a.metadata['season'], '2');
    expect(a.metadata['episode'], '2');
    expect(a.metadata['series'], 'Show');
    expect(
      const VideoCollection(
        id: 'c',
        name: 'C',
        subtype: VideoSubtype.cinema,
      ).autoplayNext,
      false,
    );
  });
  test(
    'continuation remains visible when the next episode has multiple versions',
    () {
      final first = episode('a', 1, 1, watched: true, lastPlayed: 100);
      final all = [first, episode('b', 1, 3), episode('c', 1, 3)];
      expect(seriesContinuation(all).single.id, 'b');
      expect(nextEpisode(first, all), isNull);
    },
  );
  testWidgets('bulk selection marks every selected file watched', (
    tester,
  ) async {
    final service = MemoryLibrary();
    final a = VideoAsset.fromJson({
      ...episode('a', 1, 1).toJson(),
      'contentSubtype': 'movies',
      'metadata': {'title': 'Movie A'},
    }, VideoSubtype.movies);
    final b = VideoAsset.fromJson({
      ...episode('b', 1, 2).toJson(),
      'contentSubtype': 'movies',
      'metadata': {'title': 'Movie B'},
    }, VideoSubtype.movies);
    final library = await libraryOf(service, [a, b]);
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
    await tester.longPress(find.text('Movie A'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Selection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark watched'));
    await tester.pumpAndSettle();
    expect(library.items('c').every((a) => a.watched), true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'normal catalog opens one series page without starting playback',
    (tester) async {
      final library = await libraryOf(MemoryLibrary(), [
        episode('a', 1, 1),
        episode('b', 2, 1),
      ]);
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
      expect(find.text('The Show'), findsOneWidget);
      expect(find.text('Episode 1'), findsNothing);
      await tester.tap(find.text('The Show'));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesDetails), findsOneWidget);
      expect(find.byType(AndroidView), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'season dropdown includes Specials and lists only locally indexed episodes',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = await libraryOf(MemoryLibrary(), [
        episode('special', 0, 1),
        episode('a', 1, 1),
        episode('c', 1, 3),
        episode('b', 2, 1),
      ]);
      final played = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SeriesDetails(
            library: library,
            series: buildSeries(library.assets).single,
            play: (a, external) async {
              played.add(a.id);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.textContaining('Not on this device: E2'), findsOneWidget);
      expect(played, isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Specials').last);
      await tester.pumpAndSettle();
      expect(find.text('1. Episode 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'episode playback with multiple versions requires a file choice',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = await libraryOf(MemoryLibrary(), [
        episode('a', 1, 1),
        episode('b', 1, 1),
      ]);
      final played = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SeriesDetails(
            library: library,
            series: buildSeries(library.assets).single,
            play: (a, e) async {
              played.add(a.id);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play S1 · E1'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a version'), findsOneWidget);
      expect(played, isEmpty);
      await tester.tap(find.text(library.assets[1].filename));
      await tester.pumpAndSettle();
      expect(played, ['b']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('Videos descriptions expand and collapse', (tester) async {
    final a = VideoAsset.fromJson({
      ...episode('a', 1, 1).toJson(),
      'metadata': {'title': 'Video', 'description': 'A long description ' * 30},
    }, VideoSubtype.videos);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WatchDetails(asset: a, related: const [], onSelect: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
  });
  testWidgets(
    'cinema groups a series across its shelves and opens series details',
    (tester) async {
      final library = await libraryOf(MemoryLibrary(), [
        episode('a', 1, 1),
        episode('b', 1, 2),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(
            library: library,
            collectionId: 'c',
            collectionName: 'Shows',
            play: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesDetails), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
