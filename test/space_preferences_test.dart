import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/space_preferences.dart';

import 'media_foundation_test.dart' show SharedStore;

void main() {
  test('space preferences persist independently', () async {
    final store = SharedStore();
    final prefs = SpacePreferences();
    prefs.cinema.source = 'pinned';
    prefs.cinema.pins = ['one', 'two', 'three', 'four'];
    prefs.cinema.hideWatched = true;
    prefs.cinema.startTab = 2;
    prefs.cinema.artwork = false;
    prefs.videos.counts = false;
    prefs.videos.confirmExit = false;
    await prefs.save(store.userPreferences);
    final restored = SpacePreferences();
    await restored.load(store.userPreferences);
    expect(restored.cinema.source, 'pinned');
    expect(restored.cinema.pins, ['one', 'two', 'three']);
    expect(restored.cinema.hideWatched, true);
    expect(restored.cinema.startTab, 2);
    expect(restored.cinema.artwork, false);
    expect(restored.cinema.confirmExit, true);
    expect(restored.videos.source, 'recent');
    expect(restored.videos.counts, false);
    expect(restored.videos.confirmExit, false);
  });

  testWidgets('system back returns directly to the previous route', (
    tester,
  ) async {
    final prefs = SpacePreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SpaceExitGuard(
                    preferences: prefs,
                    videos: true,
                    child: const Scaffold(body: Text('Video feed')),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Exit Videos?'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Video feed'), findsNothing);
  });
}
