import 'support/space_controls.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/cinema_view.dart';

import 'global_cinema_test.dart' show cinemaLibrary;
import 'phase_two_test.dart' show episode;

void main() {
  test(
    'genres are metadata-derived, deduplicated, and preserve compound names',
    () {
      VideoAsset tagged(String id, String genres) => VideoAsset.fromJson({
        ...episode(id, 1, 1).toJson(),
        'metadata': {'genres': genres},
      }, VideoSubtype.tv);
      expect(
        cinemaGenres([
          tagged('a', 'Drama, Sci-Fi & Fantasy'),
          tagged('b', 'drama; Action | Comedy'),
        ]),
        ['Action', 'Comedy', 'Drama', 'Sci-Fi & Fantasy'],
      );
      expect(cinemaGenres([episode('empty', 1, 1)]), isEmpty);
    },
  );
  test('series genre matches retain untagged episodes without including another collection', () {
    final tagged = VideoAsset.fromJson({
      ...episode('a', 1, 1).toJson(),
      'metadata': {...episode('a', 1, 1).metadata, 'genres': 'Drama'},
    }, VideoSubtype.tv);
    final untagged = episode('b', 1, 2);
    final other = VideoAsset.fromJson({
      ...episode('b', 1, 2).toJson(),
      'collectionId': 'other',
    }, VideoSubtype.tv);
    final filtered = filterCinemaItems(
      [tagged, untagged, other],
      category: 'series',
      genre: 'drama',
    );
    expect(filtered.map((a) => a.id), ['a', 'b']);
    expect(filtered.every((a) => a.collectionId == 'c'), true);
  });
  for (final global in [false, true]) {
    testWidgets(
      '${global ? 'global' : 'local'} cinema filters categories and genres across pages',
      (tester) async {
        final library = await cinemaLibrary();
        await tester.pumpWidget(
          MaterialApp(
            home: MultiplexrCinema(
              library: library,
              collectionId: global ? null : 'a',
              collectionName: 'Collection a',
              play: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Series'));
        await tester.pumpAndSettle();
        final navLabel = 'Browse';
        await openSpaceControls(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<bool>),
            matching: find.text(navLabel),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('The Show'), findsNWidgets(global ? 2 : 1));
        expect(find.text('Movie a'), findsNothing);
        await openSpaceControls(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Movies'));
        await tester.pumpAndSettle();
        expect(find.text('The Show'), findsNothing);
        expect(find.text('Movie a'), findsOneWidget);
        await openSpaceControls(tester);
        await tester.tap(find.byTooltip('Filter genres'));
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<String>, 'Action'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Movie a'), findsOneWidget);
        expect(find.text('Movie b'), findsNothing);
        await openSpaceControls(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<bool>),
            matching: find.text('Browse'),
          ),
        );
        await tester.pumpAndSettle();
        await openSpaceControls(tester);
        await tester.enterText(find.byType(TextField), 'Movie b');
        await tester.pumpAndSettle();
        expect(find.text('No matching titles'), findsOneWidget);
        await openSpaceControls(tester);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('Movie a'), findsOneWidget);
        await openSpaceControls(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await tester.pumpAndSettle();
        expect(find.text('Genres'), findsOneWidget);
        expect(find.text('The Show'), findsNWidgets(global ? 2 : 1));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
