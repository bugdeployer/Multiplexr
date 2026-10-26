import 'fixtures/legacy_library_assembly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/main.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/collection_form.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/library/video_scope.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audiobooks_page.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:app_shell/app_shell.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'widget_test.dart' show TestDevice;

const audioCollection = VideoCollection(
  id: 'books',
  name: 'My books',
  subtype: VideoSubtype.videos,
  kind: MediaKind.audiobook,
  roots: [LibraryRoot('content://root', 'Books')],
  extensions: ['mp3', 'm4b'],
  view: CatalogView.list,
  locked: true,
  includeInGlobalAudio: false,
);
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test('audio collections round trip shared preferences independently from video subtype', () {
    final restored = VideoCollection.fromJson(audioCollection.toJson());
    expect(restored.kind, MediaKind.audiobook);
    expect(restored.locked, true);
    expect(restored.includeInGlobalAudio, false);
    expect(restored.roots.single.contentSubtype, null);
    expect(restored.extensions, ['mp3', 'm4b']);
    expect(restored.mediaLabel, 'Audiobooks');
  });
  test(
    'audio collection loads in Library but never leaks into Cinema or Videos',
    () async {
      final service = SharedStore();
      service.collections.add(audioCollection.toJson());
      final controller = createLibraryController(service);
      await controller.load();
      expect(controller.collections.single.isAudio, true);
      expect(globalVideoCollections(controller), isEmpty);
      expect(cinemaCollections(controller), isEmpty);
      expect(controller.canAccessCollection('books'), false);
      controller.beginCollectionSession('books');
      controller.authorizeCollection('books');
      expect(controller.canAccessCollection('books'), true);
      controller.relockCollections();
      expect(controller.canAccessCollection('books'), false);
      controller.dispose();
    },
  );
  test(
    'saving one audiobook collection preserves books in other collections',
    () async {
      final service = SharedStore();
      final a = createAudioLibrary(service, collectionId: 'a'),
          b = createAudioLibrary(service, collectionId: 'b');
      await a.add(const AudiobookMetadata(title: 'First'), const [
        AudioFile(uri: 'content://a', filename: 'First.mp3'),
      ]);
      final other = await b.add(
        const AudiobookMetadata(title: 'Second'),
        const [AudioFile(uri: 'content://b', filename: 'Second.mp3')],
      );
      expect((await a.books()).single.id.collectionId, 'a');
      await a.save([]);
      expect((await createAudioLibrary(service).books()).single.id, other.id);
    },
  );
  testWidgets(
    'New collection offers Audiobooks with shared settings and no video-specific fields',
    (tester) async {
      final controller = createLibraryController(SharedStore());
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CollectionForm(library: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<MediaType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Audio').last);
      await tester.pumpAndSettle();
      expect(find.text('Subtype'), findsOneWidget);
      expect(find.text('Audiobooks'), findsOneWidget);
      expect(find.text('Collection lock'), findsOneWidget);
      expect(find.text('Include in global Audiobooks'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Add root folder'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Default player'), findsOneWidget);
      expect(find.text('Autoplay next episode'), findsNothing);
      expect(find.text('.m4b'), findsOneWidget);
      expect(find.text('.mp4'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'Library lists audiobook collections, not a standalone Audiobooks entry',
    (tester) async {
      final service = SharedStore();
      service.collections.add(
        VideoCollection.fromJson({...audioCollection.toJson(), 'locked': false})
            .toJson(),
      );
      await tester.pumpWidget(
        MultiplexrApp(platform: TestDevice(), libraryService: service),
      );
      await tester.pumpAndSettle();
      expect(find.text('My books'), findsOneWidget);
      expect(find.text('Audiobooks'), findsNothing);
      await tester.tap(find.text('My books'));
      await tester.pumpAndSettle();
      expect(find.byType(AudiobooksPage), findsOneWidget);
      expect(find.byTooltip('Collection settings'), findsOneWidget);
      expect(find.byTooltip('Import book'), findsNothing);
      await tester.tap(find.byTooltip('Collection actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage collection'));
      await tester.pumpAndSettle();
      expect(find.text('Scan folders'), findsOneWidget);
      expect(find.text('Manage tags'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('global Audiobooks excludes locked and opted-out collections', (
    tester,
  ) async {
    final service = SharedStore();
    for (final entry in [
      ('public', false, true),
      ('locked', true, true),
      ('excluded', false, false),
    ]) {
      service.collections.add(
        VideoCollection(
          id: entry.$1,
          name: entry.$1,
          kind: MediaKind.audiobook,
          subtype: VideoSubtype.videos,
          locked: entry.$2,
          includeInGlobalAudio: entry.$3,
        ).toJson(),
      );
      await createAudioLibrary(service, collectionId: entry.$1).add(
        AudiobookMetadata(title: '${entry.$1} book'),
        [AudioFile(uri: 'content://${entry.$1}', filename: 'Chapter.mp3')],
      );
    }
    final controller = createLibraryController(service);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: AudiobooksPage(
          catalog: controller.audiobookCatalog(),
          libraryController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('public book'), findsOneWidget);
    expect(find.text('locked book'), findsNothing);
    expect(find.text('excluded book'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
