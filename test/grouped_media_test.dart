import 'support/space_controls.dart';

import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import 'fixtures/legacy_library_assembly.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/audiobook_management.dart';
import 'package:multiplexr/src/media/audiobook_cover.dart';
import 'package:multiplexr/src/media/audiobook_metadata.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/storage.dart';
import 'package:multiplexr/src/media/grouping.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/series.dart';
import 'package:multiplexr/src/library/series_management.dart';
import 'package:multiplexr/src/library/video_space.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/space_preferences.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'global_videos_test.dart' show videosLibrary;
import 'global_cinema_test.dart' show cinemaLibrary;

Audiobook audiobook(
  String item, {
  String collection = 'a',
  String series = '',
  double order = 0,
}) => Audiobook(
  id: MediaId(MediaKind.audiobook, collection, item),
  metadata: AudiobookMetadata(title: item, series: series, seriesOrder: order),
  files: [
    AudioFile(
      id: item,
      uri: 'content://audio/$item',
      filename: '$item.m4b',
      durationMs: 60000,
    ),
  ],
);

void main() {
  testWidgets(
    'metadata review preserves manual grouping, covers and audiobook progress',
    (tester) async {
      final store = SharedStore();
      final original = audiobook('Local', series: 'Manual series').withMetadata(
        {
          'coverSource': 'manual',
          'tags': ['Keep'],
        },
      );
      final library = createAudioLibrary(store);
      await library.save([original]);
      await MediaStorage(store).write(
        AudiobookProgress(
          original.id,
          chapterId: original.chapterMarkers.first.id,
          positionMs: 1200,
          finished: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookMetadataReviewPage(
            workflow: MetadataWorkflow(
              [],
              mutations: const OwnerApplicationMutations(),
            ),
            library: library,
            book: original,
            match: const {
              'providerId': '0008433844',
              'title': 'Matched title',
              'author': 'Author',
              'narrator': 'Narrator',
              'series': 'Provider series',
              'seriesId': 'audible:series',
              'seriesOrder': 2,
              'coverUrl': '',
              'description': 'Description',
              'publisher': 'Publisher',
              'publicationDate': '2020-01-01',
              'language': 'English',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Apply selected metadata'),
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Apply selected metadata'));
      await tester.pumpAndSettle();
      final updated = (await library.books()).single;
      expect(updated.metadata.title, 'Matched title');
      expect(updated.metadata.narrator, 'Narrator');
      expect(updated.metadata.series, 'Manual series');
      expect(updated.metadata.coverSource, 'manual');
      expect(updated.metadata.tags, ['Keep']);
      expect(updated.id, original.id);
      expect(updated.chapterMarkers.first.id, original.chapterMarkers.first.id);
      expect(
        (await MediaStorage(
          store,
        ).read(original.id) as AudiobookProgress).positionMs,
        1200,
      );
    },
  );

  testWidgets(
    'series metadata contains square artwork grid and opens whole audiobooks',
    (tester) async {
      final store = SharedStore();
      final first = audiobook('First', series: 'Saga', order: 1);
      final second = audiobook('Second', series: 'Saga', order: 2);
      final library = createAudioLibrary(store);
      await library.save([first, second]);
      final group = audiobookSeries([first, second]).single;
      await library.saveSeriesMetadata(
        AudiobookSeriesMetadata(
          id: group.id,
          collectionId: 'a',
          title: 'Saga',
          description: 'Series description',
        ),
      );
      Audiobook? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: AudiobookSeriesPage(
            group: group,
            library: library,
            openBook: (b) async {
              opened = b;
            },
            editBook: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final hero = tester.getSize(find.byType(AudiobookCover).first);
      expect(hero.width, 800);
      expect(hero.height, hero.width);
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Series description'), findsOneWidget);
      expect(find.byType(AudiobookArtworkTile), findsNWidgets(2));
      expect(find.textContaining('chapters'), findsNothing);
      for (final tile in find.byType(AudiobookArtworkTile).evaluate()) {
        final size = tester.getSize(find.byWidget(tile.widget));
        expect(size.width, size.height);
      }
      await openSpaceControls(tester);
      await tester.ensureVisible(find.byType(AudiobookArtworkTile).last);
      await openSpaceControls(tester);
      await tester.tap(find.byType(AudiobookArtworkTile).last);
      await tester.pumpAndSettle();
      expect(opened?.id, second.id);
      expect(opened?.files.single.filename, 'Second.m4b');
      final persisted = await library.seriesMetadata(group.id);
      expect(persisted?.description, 'Series description');
    },
  );

  test('legacy audiobook collection upgrades classification without changing its identity', () {
    final collection = VideoCollection.fromJson({
      'id': 'old',
      'name': 'Old books',
      'type': 'audiobook',
      'subtype': 'videos',
      'roots': [],
      'extensions': ['m4b'],
      'view': 'list',
      'player': 'internal',
      'locked': true,
      'includeInGlobalAudio': false,
    });
    final upgraded = collection.toJson();
    expect(upgraded['type'], 'audio');
    expect(upgraded['subtype'], 'audiobooks');
    expect(collection.id, 'old');
    expect(collection.mediaType, MediaType.audio);
    expect(VideoCollection.fromJson(upgraded).kind, MediaKind.audiobook);
    expect(VideoCollection.fromJson(upgraded).locked, true);
    expect(VideoCollection.fromJson(upgraded).includeInGlobalAudio, false);
  });

  test('chapter order can change without changing ranges or losing resume and bookmark identities', () async {
    final original = audiobook('long');
    final reordered = Audiobook(
      id: original.id,
      metadata: original.metadata,
      files: original.files,
      chapters: const [
        AudiobookChapterMarker(
          id: 'later',
          fileId: 'long',
          title: 'Later',
          startMs: 30000,
          endMs: 60000,
        ),
        AudiobookChapterMarker(
          id: 'first',
          fileId: 'long',
          title: 'First',
          startMs: 0,
          endMs: 30000,
        ),
      ],
    );
    final progress = AudiobookProgress(
      original.id,
      chapterId: 'first',
      positionMs: 1200,
      finished: false,
      bookmarks: const [AudiobookBookmark('first', 1000, 'Here')],
    );
    final request = AudioPlaybackRequest.audiobook(reordered, progress);
    expect(request.index, 1);
    expect(request.positionMs, 1200);
    expect(request.files.first.startMs, 30000);
    final store = SharedStore();
    await MediaStorage(store).write(progress);
    await createAudioLibrary(store).save([reordered]);
    final restored =
        await MediaStorage(store).read(original.id) as AudiobookProgress;
    expect(restored.bookmarks.single.chapterId, 'first');
    expect(restored.chapterId, 'first');
  });

  test('audiobook series are collection scoped and have ordered books with separate progress', () async {
    final first = audiobook('First', series: 'Trilogy', order: 1);
    final second = audiobook('Second', series: 'Trilogy', order: 2);
    final other = audiobook(
      'Other',
      collection: 'b',
      series: 'Trilogy',
      order: 1,
    );
    final groups = audiobookSeries([second, other, first]);
    expect(groups.length, 2);
    expect(
      groups
          .firstWhere((g) => g.children.length == 2)
          .children
          .map((b) => b.metadata.title),
      ['First', 'Second'],
    );
    final store = SharedStore();
    final library = createAudioLibrary(store);
    await library.save([first, second]);
    await MediaStorage(store).write(
      AudiobookProgress(
        first.id,
        chapterId: first.files.single.id,
        positionMs: 15000,
        finished: false,
      ),
    );
    await updateAudiobookSelection(
      library,
      [first, second],
      (b, _) => b.withMetadata({
        'series': 'Renamed',
        'seriesId': 'renamed',
        'tags': ['Fiction'],
        'cover': 'data:image/png;base64,cover',
        'coverSource': 'manual',
      }),
    );
    expect((await library.books()).first.metadata.coverSource, 'manual');
    expect((await library.books()).first.metadata.tags, ['Fiction']);
    expect(
      (await MediaStorage(
        store,
      ).read(first.id) as AudiobookProgress).positionMs,
      15000,
    );
    expect(await MediaStorage(store).read(second.id), isNull);
  });

  test('manual TV grouping overrides provider grouping and preserves asset history', () {
    VideoAsset asset(String id, String group, int order) =>
        VideoAsset.fromJson({
          'id': id,
          'collectionId': 'tv',
          'filename': '$id.mp4',
          'uri': 'content://$id',
          'seriesId': 42,
          'metadataSource': 'tmdb',
          'contentSubtype': 'tv',
          'positionMs': 10000,
          'metadata': {
            'title': id,
            'series': group,
            'season': '1',
            'episode': id == 'one' ? '1' : '2',
            'groupId': group.toLowerCase(),
            'groupOrder': '$order',
          },
        }, VideoSubtype.tv);
    final one = asset('one', 'Corrected', 1),
        two = asset('two', 'Corrected', 0);
    expect(buildSeries([one, two]).single.episodes.first.asset.id, 'two');
    expect(buildSeries([one, asset('two', 'Separate', 0)]).length, 2);
    expect(one.positionMs, 10000);
    expect(one.seriesId, 42);
  });

  testWidgets(
    'TV corrections save selected episode grouping and keep playback history',
    (tester) async {
      final library = await cinemaLibrary();
      final episode = library
          .items('a')
          .firstWhere((a) => a.mediaSubtype == VideoSubtype.tv);
      await tester.pumpWidget(
        MaterialApp(
          home: SeriesGroupingPage(
            library: library,
            collectionId: 'a',
            initial: episode.id,
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'My corrected series',
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Apply grouping'));
      await tester.pumpAndSettle();
      final updated = library.items('a').firstWhere((a) => a.id == episode.id);
      expect(updated.metadata['groupId'], 'my corrected series');
      expect(updated.positionMs, episode.positionMs);
      expect(updated.favorite, episode.favorite);
    },
  );

  testWidgets('shared order editor supports moving an item without dragging', (
    tester,
  ) async {
    List<String>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: GroupOrderPage<String>(
          title: 'Order',
          items: const ['one', 'two'],
          identity: (v) => v,
          label: (v) => v,
          save: (values) async {
            saved = [...values];
          },
        ),
      ),
    );
    await openSpaceControls(tester);
    await tester.tap(find.byTooltip('Move up').last);
    await tester.pump();
    await openSpaceControls(tester);
    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();
    expect(saved, ['two', 'one']);
  });

  testWidgets('spaces open to Overview with legacy starting-tab preferences', (
    tester,
  ) async {
    final library = await videosLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiplexrVideoSpace(
          library: library,
          display: SpaceDisplay()..startTab = 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .selected,
      {true},
    );
    await tester.pumpWidget(const SizedBox());
    final cinema = await cinemaLibrary();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiplexrCinema(
          library: cinema,
          play: (_, _) async {},
          display: SpaceDisplay()..startTab = 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
          .selected,
      {true},
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Hide watched removes browsing titles while retaining Favorites',
    (tester) async {
      final library = await cinemaLibrary();
      final movie = library
          .items('a')
          .firstWhere((a) => a.mediaSubtype == VideoSubtype.movies);
      await library.flags([movie], 'favorite', true);
      await library.flags([movie], 'watched', true);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(
            library: library,
            play: (_, _) async {},
            display: SpaceDisplay()
              ..startTab = 2
              ..hideWatched = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      expect(find.text('Movie a'), findsNothing);
      expect(find.text('Movie b'), findsWidgets);
      await openSpaceControls(tester);
      await tester.tap(find.text('Overview').last);
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Favorites'),
        300,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('Movie a'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Hide watched handles a fully watched cinema without a null hero',
    (tester) async {
      final library = await cinemaLibrary();
      await library.flags(library.assets, 'watched', true);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(
            library: library,
            play: (_, _) async {},
            display: SpaceDisplay()..hideWatched = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
