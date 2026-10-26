import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audio_player_components.dart';

void main() {
  testWidgets(
    'player control pairs keep a divider and remain usable at narrow large-text sizes',
    (tester) async {
      var taps = 0;
      for (final width in [400.0, 240.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(width < 280 ? 2 : 1),
                    ),
                    child: AudioControlPair(
                      first: TextButton(
                        onPressed: () => taps++,
                        child: const Text('Bookmark'),
                      ),
                      second: TextButton(
                        onPressed: () => taps++,
                        child: const Text('Bookmarks'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(VerticalDivider),
          width >= 280 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Bookmark'));
        await tester.tap(find.text('Bookmarks'));
      }
      expect(taps, 4);
    },
  );
  testWidgets(
    'chapter rows expose current selection, retain borders and handle long titles without overflow',
    (tester) async {
      var selected = 0;
      for (final active in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 260,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.8),
                      ),
                      child: AudioChapterTile(
                        number: 28,
                        title: 'A long chapter title that must wrap without colliding with chapter number or current chapter indicator',
                        duration: '12:51',
                        selected: active,
                        playing: active,
                        onTap: () => selected++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = tester.widget<Card>(find.byType(Card));
        expect((card.shape as OutlinedBorder).side.width, active ? 2 : 1);
        expect(tester.widget<ListTile>(find.byType(ListTile)).selected, active);
        await tester.ensureVisible(find.text('12:51'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('12:51'));
      }
      expect(selected, 2);
    },
  );
}
