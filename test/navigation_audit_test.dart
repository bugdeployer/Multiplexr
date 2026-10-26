import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/library/video_space.dart';

import 'global_cinema_test.dart' show cinemaLibrary;
import 'global_videos_test.dart' show videosLibrary, VideosStorage;

class ExternalAuditStorage extends VideosStorage {
  VideoAsset? opened;
  @override
  Future<void> external(VideoAsset asset) async {
    opened = asset;
  }
}

Future<void> visible(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'explicit Cinema Details never plays even when title taps play immediately',
    (tester) async {
      final library = await cinemaLibrary();
      final owner = library.collections.firstWhere((c) => c.id == 'a');
      await library.save(
        VideoCollection.fromJson({...owner.toJson(), 'openAction': 'play'}),
      );
      var played = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiplexrCinema(
            library: library,
            collectionId: 'a',
            play: (_, _) async {
              played++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await visible(tester, find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(played, 0);
      expect(find.byType(VideoTitleDetails), findsOneWidget);
    },
  );
  testWidgets('Videos details honors the explicit external-player action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    final store = ExternalAuditStorage();
    final library = await videosLibrary(storage: store);
    final owner = library.collections.firstWhere((c) => c.id == 'a');
    await library.save(
      VideoCollection.fromJson({...owner.toJson(), 'openAction': 'details'}),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MultiplexrVideoSpace(library: library, collectionId: 'a'),
      ),
    );
    await tester.pumpAndSettle();
    await visible(tester, find.text('A old clip'));
    await tester.tap(find.text('A old clip'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoTitleDetails), findsOneWidget);
    await visible(tester, find.text('Open in external player'));
    await tester.tap(find.text('Open in external player'));
    await tester.pumpAndSettle();
    expect(store.opened?.collectionId, 'a');
    expect(store.opened?.id, 'same');
  });
}
