import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/bootstrap/app_composition.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/library/series_view.dart';
import 'package:multiplexr/src/shell.dart';

import 'library_test.dart' show MemoryLibrary;
import 'phase_two_test.dart' show episode;
import 'widget_test.dart' show TestDevice;

Future<LibraryController> cinemaLibrary() async {
  final service = MemoryLibrary();
  for (final id in ['a', 'b', 'videos']) {
    service.collections.add(
      VideoCollection(
        id: id,
        name: 'Collection $id',
        subtype: id == 'videos' ? VideoSubtype.videos : VideoSubtype.cinema,
      ).toJson(),
    );
    service.assets.add(
      VideoAsset.fromJson({
        'id': 'same',
        'collectionId': id,
        'uri': 'content://$id/movie',
        'filename': 'Movie $id.mp4',
        'contentSubtype': id == 'videos' ? 'videos' : 'movies',
        'metadata': {
          'title': 'Movie $id',
          'genres': id == 'a' ? 'Action, Drama' : 'Comedy',
        },
        'addedAt': 1,
      }, id == 'videos' ? VideoSubtype.videos : VideoSubtype.movies).toJson(),
    );
    if (id != 'videos') {
      service.assets.add(
        VideoAsset.fromJson({
          ...episode('episode', 1, 1).toJson(),
          'collectionId': id,
          'metadata': {
            ...episode('episode', 1, 1).metadata,
            'genres': 'Drama, Sci-Fi & Fantasy',
          },
        }, VideoSubtype.tv).toJson(),
      );
    }
  }
  final library = createLibraryController(service);
  await library.load();
  return library;
}

Future<void> titlesPage(WidgetTester tester) async {
  if (find.text('Overview & filters').evaluate().isNotEmpty) {
    await tester.tap(find.text('Overview & filters'));
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.descendant(
      of: find.byType(SegmentedButton<bool>),
      matching: find.text('Browse'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  testWidgets(
    'global cinema updates automatically when collections are removed',
    (tester) async {
      final library = await cinemaLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(library: library, play: (_, _) async {}),
        ),
      );
      await tester.pumpAndSettle();
      await titlesPage(tester);
      expect(find.byTooltip('Filter collections'), findsNothing);
      await library.remove('b');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Movie a'), findsOneWidget);
      expect(find.text('Movie b'), findsNothing);
      await library.remove('a');
      await tester.pumpAndSettle();
      expect(find.text('No matching titles'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('global scope excludes Videos and respects file extensions', () async {
    final library = await cinemaLibrary();
    expect(cinemaCollections(library).map((c) => c.id), ['a', 'b']);
    expect(cinemaItems(library), hasLength(4));
    expect(
      cinemaItems(
        library,
        collectionId: 'b',
      ).every((a) => a.collectionId == 'b'),
      true,
    );
    expect(cinemaItems(library, collectionId: 'videos'), isEmpty);
    library.collections[0] = VideoCollection(
      id: 'a',
      name: 'A',
      subtype: VideoSubtype.cinema,
      extensions: ['mkv'],
    );
    expect(cinemaItems(library), hasLength(2));
  });
  testWidgets(
    'global cinema always combines eligible collections without changing ownership',
    (tester) async {
      final library = await cinemaLibrary();
      String? playedCollection;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(
            library: library,
            play: (a, _) async {
              playedCollection = a.collectionId;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await titlesPage(tester);
      expect(find.text('Movie a'), findsOneWidget);
      expect(find.text('Movie b'), findsOneWidget);
      expect(find.text('Movie videos'), findsNothing);
      expect(find.byTooltip('Filter collections'), findsNothing);
      expect(find.text('Movie a'), findsOneWidget);
      expect(find.text('Movie b'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('Movie b')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movie b'));
      await tester.pumpAndSettle();
      expect(playedCollection, isNull);
      await tester.ensureVisible(find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(playedCollection, 'b');
      expect(library.items('a').first.collectionId, 'a');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'global series details stay scoped to the selected source collection',
    (tester) async {
      final library = await cinemaLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(library: library, play: (_, _) async {}),
        ),
      );
      await tester.pumpAndSettle();
      await titlesPage(tester);
      expect(find.text('The Show'), findsNWidgets(2));
      await Scrollable.ensureVisible(
        tester.element(find.text('The Show').last),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('The Show').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SeriesDetails>(find.byType(SeriesDetails))
            .series
            .assets
            .single
            .collectionId,
        'b',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Spaces opens global cinema while Library retains collection entry points',
    (tester) async {
      final library = await cinemaLibrary();
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
      expect(find.text('Open Cinema'), findsNothing);
      await tester.tap(find.text('SPACES'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Cinema'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MultiplexrCinema>(find.byType(MultiplexrCinema))
            .collectionId,
        isNull,
      );
      await tester.tap(find.byTooltip('Exit cinema'));
      await tester.pumpAndSettle();
      expect(find.text('Exit Cinema?'), findsNothing);
      expect(find.text('SPACES'), findsWidgets);
      await tester.tap(find.text('LIBRARY'));
      await tester.pumpAndSettle();
      expect(find.text('Collection a'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    },
  );
}
