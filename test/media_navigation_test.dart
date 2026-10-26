import 'support/space_controls.dart';
import 'fixtures/legacy_library_assembly.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/audiobook_details.dart';
import 'package:multiplexr/src/media/audiobook_management.dart';
import 'package:multiplexr/src/media/audiobook_space.dart';
import 'package:multiplexr/src/media/navigation_settings.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/storage.dart';
import 'package:multiplexr/main.dart';
import 'package:app_shell/app_shell.dart';

import 'widget_test.dart' show TestDevice;

import 'media_foundation_test.dart' show SharedStore;
import 'grouped_media_test.dart' show audiobook;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  testWidgets('exiting an audiobook space preserves the Spaces destination', (
    tester,
  ) async {
    final service = SharedStore();
    service.collections.add(
      const VideoCollection(
        id: 'a',
        name: 'Audio',
        subtype: VideoSubtype.videos,
        kind: MediaKind.audiobook,
      ).toJson(),
    );
    await createAudioLibrary(service).save([audiobook('Sample')]);
    await tester.pumpWidget(
      MultiplexrApp(platform: TestDevice(), libraryService: service),
    );
    await tester.pumpAndSettle();
    await openSpaceControls(tester);
    await tester.tap(find.text('SPACES').last);
    await tester.pumpAndSettle();
    for (
      var i = 0;
      i < 12 && find.text('Open Audiobooks').hitTestable().evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await openSpaceControls(tester);
    await tester.tap(find.text('Open Audiobooks'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Exit Audiobooks?'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });
  testWidgets(
    'audiobook browsing hides finished titles and honors its starting tab',
    (tester) async {
      final service = SharedStore();
      service.collections.add(
        const VideoCollection(
          id: 'a',
          name: 'Audio',
          subtype: VideoSubtype.videos,
          kind: MediaKind.audiobook,
        ).toJson(),
      );
      final done = audiobook('Finished');
      final ongoing = audiobook('Listening');
      await createAudioLibrary(service).save([done, ongoing]);
      await MediaStorage(service).write(
        AudiobookProgress(
          done.id,
          chapterId: done.chapterMarkers.first.id,
          positionMs: 60000,
          finished: true,
        ),
      );
      await MediaStorage(service).write(
        AudiobookProgress(
          ongoing.id,
          chapterId: ongoing.chapterMarkers.first.id,
          positionMs: 1200,
          finished: false,
        ),
      );
      await service.writeState('spaces:display', {
        'audiobooks': {'startTab': 2, 'hideWatched': true},
      });
      final library = createLibraryController(service);
      await library.load();
      await tester.pumpWidget(
        MaterialApp(home: AudiobookSpace(library: library)),
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      expect(
        tester
            .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
            .selected,
        {true},
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Finished'), findsNothing);
      expect(find.bySemanticsLabel('Listening'), findsOneWidget);
      await openSpaceControls(tester);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsOneWidget);
      expect(find.bySemanticsLabel('Listening'), findsWidgets);
      expect(find.bySemanticsLabel('Finished'), findsNothing);
    },
  );

  test('opening preference preserves old video behavior and explicitly overrides every subtype', () {
    for (final kind in [MediaKind.video, MediaKind.audiobook]) {
      final old = VideoCollection(
        id: 'c',
        name: 'Collection',
        subtype: VideoSubtype.videos,
        kind: kind,
      );
      expect(old.opensDetails(legacy: false), false);
      expect(old.opensDetails(legacy: true), true);
      for (final action in ['details', 'play']) {
        final changed = VideoCollection.fromJson({
          ...old.toJson(),
          'openAction': action,
          'audioRate': 1.5,
        });
        expect(changed.opensDetails(legacy: false), action == 'details');
        expect(changed.opensDetails(legacy: true), action == 'details');
        expect(changed.toJson()['openAction'], action);
        expect(changed.audioRate, 1.5);
      }
    }
  });
  test('every audiobook has a stable series including standalone titles', () {
    final first = audiobook('Standalone');
    final second = audiobook('Other');
    final groups = audiobookSeries([first, second]);
    expect(groups.length, 2);
    expect(groups.every((g) => g.children.length == 1), true);
    final before = audiobookSeries([first]).single.id;
    expect(
      audiobookSeries([
        first.withMetadata({'title': 'Renamed'}),
      ]).single.id,
      before,
    );
  });
  testWidgets(
    'title opening and speed inherit collection then series then audiobook',
    (tester) async {
      final service = SharedStore();
      final book = audiobook('First', series: 'Saga');
      final library = createAudioLibrary(service);
      await library.save([book]);
      const collection = VideoCollection(
        id: 'a',
        name: 'Audio',
        subtype: VideoSubtype.videos,
        kind: MediaKind.audiobook,
        openAction: 'details',
        audioRate: 1.25,
      );
      final seriesKey = MediaNavigationSettings.key(
        'a',
        'series:${audiobookSeries([book]).single.id}',
      );
      final titleKey = MediaNavigationSettings.key('a', book.id.key);
      var played = 0;
      double? speed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openAudiobookTitle(
                  context,
                  library,
                  collection,
                  book,
                  (rate) async {
                    played++;
                    speed = rate;
                  },
                  () async {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AudiobookDetailsPage), findsOneWidget);
      expect(played, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await service.writeState(
        seriesKey,
        const MediaNavigationSettings(openAction: 'play', rate: 1.5).toJson(),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(played, 1);
      expect(speed, 1.5);
      await service.writeState(
        titleKey,
        const MediaNavigationSettings(openAction: 'play', rate: 2).toJson(),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(played, 2);
      expect(speed, 2);
      await service.writeState(
        titleKey,
        const MediaNavigationSettings().toJson(),
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(played, 3);
      expect(speed, 1.5);
    },
  );
  testWidgets(
    'audiobook space has consistent destinations and excludes private collections',
    (tester) async {
      final service = SharedStore();
      service.collections.addAll([
        const VideoCollection(
          id: 'a',
          name: 'Public',
          subtype: VideoSubtype.videos,
          kind: MediaKind.audiobook,
        ).toJson(),
        const VideoCollection(
          id: 'b',
          name: 'Private',
          subtype: VideoSubtype.videos,
          kind: MediaKind.audiobook,
          locked: true,
        ).toJson(),
      ]);
      final library = createLibraryController(service);
      await library.load();
      await createAudioLibrary(service)
          .save([audiobook('Visible'), audiobook('Hidden', collection: 'b')]);
      await tester.pumpWidget(
        MaterialApp(home: AudiobookSpace(library: library)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
      await openSpaceControls(tester);
      await openSpaceControls(tester);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.bySemanticsLabel('Hidden'), findsNothing);
      await openSpaceControls(tester);
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Search collection'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
