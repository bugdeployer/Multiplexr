import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/library/cinema_view.dart';
import 'package:multiplexr/src/library/collection_form.dart';
import 'package:multiplexr/src/library/collection_lock_layer.dart';
import 'package:multiplexr/src/platform_service.dart';

import 'global_cinema_test.dart' show cinemaLibrary;

import 'package:multiplexr/main.dart';

import 'widget_test.dart' show TestDevice;
import 'phase_two_test.dart' show IndexedLibrary, episode;

class CollectionDevice extends PlatformService {
  bool authenticated = false;
  final protections = <bool>[];
  @override
  Future<bool> authenticate() async => authenticated;
  @override
  Future<void> collectionPrivacy(bool enabled) async {
    protections.add(enabled);
  }
}

Future<void> lockCollection(
  LibraryController library,
  String id, {
  bool locked = true,
  bool included = true,
}) => library.save(
  VideoCollection.fromJson({
    ...library.collections.firstWhere((c) => c.id == id).toJson(),
    'locked': locked,
    'includeInGlobalCinema': included,
  }),
);

class RootCollectionDevice extends TestDevice {
  @override
  Future<void> collectionPrivacy(bool enabled) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test(
    'locked collections keep their derived series index while content is gated',
    () async {
      final service = IndexedLibrary();
      service.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Private',
          subtype: VideoSubtype.cinema,
          locked: true,
        ).toJson(),
      );
      service.assets.add(episode('a', 1, 1).toJson());
      final library = createLibraryController(service);
      await library.load();
      expect(library.items('c'), isEmpty);
      expect(service.index!['series'], hasLength(1));
      expect(service.index!['episodes'], hasLength(1));
    },
  );
  testWidgets(
    'locked collection is gated above real navigation and reauthenticates on reopen',
    (tester) async {
      final seeded = await cinemaLibrary();
      await lockCollection(seeded, 'a');
      final device = RootCollectionDevice();
      await tester.pumpWidget(
        MultiplexrApp(platform: device, libraryService: seeded.service),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collection a'));
      await tester.pumpAndSettle();
      expect(find.text('LOCKED COLLECTION'), findsOneWidget);
      expect(find.text('Movie a'), findsNothing);
      await tester.tap(find.text('Unlock collection'));
      await tester.pumpAndSettle();
      expect(find.text('Movie a'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collection a'));
      await tester.pumpAndSettle();
      expect(find.text('LOCKED COLLECTION'), findsOneWidget);
      await tester.tap(find.text('Back to library'));
      await tester.pumpAndSettle();
      expect(find.text('LOCKED COLLECTION'), findsNothing);
      expect(find.text('Collection a'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('privacy fields migrate safely and survive persistence', () async {
    final library = await cinemaLibrary();
    final original = library.collections.first;
    expect(original.locked, false);
    expect(original.includeInGlobalCinema, true);
    await lockCollection(library, 'a', included: false);
    await library.load();
    final saved = library.collections.firstWhere((c) => c.id == 'a');
    expect(saved.locked, true);
    expect(saved.includeInGlobalCinema, false);
    expect(library.items('a'), isEmpty);
    expect(library.indexedItems('a'), hasLength(2));
  });
  test('opt-out only removes global membership while locks gate local access and queue', () async {
    final library = await cinemaLibrary();
    final asset = library.items('a').first;
    await library.enqueue(asset);
    await lockCollection(library, 'a', locked: false, included: false);
    expect(cinemaItems(library).every((a) => a.collectionId == 'b'), true);
    expect(cinemaItems(library, collectionId: 'a'), hasLength(2));
    await lockCollection(library, 'a');
    expect(library.queuedVideos, isEmpty);
    library.beginCollectionSession('a');
    library.authorizeCollection('a');
    expect(library.items('a'), hasLength(2));
    expect(library.queuedVideos.single.collectionId, 'a');
    expect(cinemaCollections(library).map((c) => c.id), ['b']);
    library.endCollectionSession();
    expect(library.items('a'), isEmpty);
    library.beginCollectionSession('a');
    expect(library.canAccessCollection('a'), false);
  });
  testWidgets(
    'collection gate protects content, rejects cancelled auth and relocks after background',
    (tester) async {
      final library = await cinemaLibrary();
      await lockCollection(library, 'a');
      library.beginCollectionSession('a');
      final device = CollectionDevice();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => CollectionLockLayer(
            library: library,
            platform: device,
            onClose: library.endCollectionSession,
            child: child!,
          ),
          home: const Scaffold(body: Text('PRIVATE TITLE')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE TITLE'), findsNothing);
      await tester.tap(find.text('Unlock collection'));
      await tester.pumpAndSettle();
      expect(find.text('Not unlocked. Try again.'), findsOneWidget);
      device.authenticated = true;
      await tester.tap(find.text('Unlock collection'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE TITLE'), findsOneWidget);
      expect(device.protections, contains(true));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE TITLE'), findsNothing);
      expect(library.canAccessCollection('a'), false);
      await tester.tap(find.text('Back to library'));
      await tester.pumpAndSettle();
      expect(device.protections.last, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'settings save global opt-out and require authentication for lock changes',
    (tester) async {
      final library = await cinemaLibrary();
      bool allowed = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        PlatformService.channel,
        (call) async => call.method == 'authenticate' ? allowed : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(PlatformService.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionForm(
            library: library,
            existing: library.collections.firstWhere((c) => c.id == 'a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Collection lock'));
      await tester.tap(find.text('Collection lock'));
      await tester.ensureVisible(find.text('Include in global cinema'));
      await tester.tap(find.text('Include in global cinema'));
      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      expect(library.collections.firstWhere((c) => c.id == 'a').locked, false);
      expect(
        find.text('Authentication cancelled. Collection lock was not changed.'),
        findsOneWidget,
      );
      allowed = true;
      await tester.ensureVisible(find.text('Save collection'));
      await tester.tap(find.text('Save collection'));
      await tester.pumpAndSettle();
      final saved = library.collections.firstWhere((c) => c.id == 'a');
      expect(saved.locked, true);
      expect(saved.includeInGlobalCinema, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
