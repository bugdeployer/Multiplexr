import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/media/contracts.dart' show MediaKind;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/core/platform/library_events.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/experience/actions/catalog_actions.dart';
import 'package:multiplexr/src/experience/actions/media_actions.dart';
import 'package:multiplexr/src/experience/navigation/navigation_origin.dart';
import 'package:multiplexr/src/experience/navigation/navigation_coordinator.dart';
import 'package:multiplexr/src/settings/domain/collection_settings_schema.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';

import 'media_foundation_test.dart' show SharedStore;

class ScanStore extends SharedStore {
  ScanStore(this.hub);
  final LibraryEventHub hub;
  final requests = <String>[];
  final pending = <Completer<List<String>>>[];
  @override
  Stream<ScanProgressEvent> get scanEvents => hub.scanProgress;
  @override
  Future<List<String>> scan(String id, {String? requestId}) {
    requests.add(requestId!);
    final gate = Completer<List<String>>();
    pending.add(gate);
    return gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'tracked scans reject old and tokenless events during a newer generation',
    (tester) async {
      const channel = MethodChannel('multiplexr/scan-generation-test');
      final store = ScanStore(LibraryEventHub(channel));
      store.collections.add(
        VideoCollection(
          id: 'c',
          name: 'Scan collection',
          subtype: VideoSubtype.videos,
        ).toJson(),
      );
      final controller = createLibraryController(store);
      addTearDown(controller.dispose);
      await controller.load();
      Future<void> event(String? token, int found) async {
        final done = Completer<void>();
        tester.binding.channelBuffers.push(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('scanProgress', {
              'id': 'c',
              'found': found,
              'folder': 'Root',
              'requestId': ?token,
            }),
          ),
          (_) => done.complete(),
        );
        await done.future;
        await tester.pump();
      }

      final first = controller.scan('c');
      await tester.pump(); // Durable admission precedes source discovery.
      final old = store.requests.single;
      await event(old, 2);
      expect(controller.scanProgress['c']!['found'], 2);
      store.pending.first.complete([]);
      await first;
      final second = controller.scan('c');
      await tester.pump();
      final current = store.requests.last;
      expect(current, isNot(old));
      await event(old, 999);
      await event(null, 888);
      expect(controller.scanProgress['c']!['found'], 0);
      await event(current, 3);
      expect(controller.scanProgress['c']!['found'], 3);
      store.pending.last.complete([]);
      await second;
    },
  );
  testWidgets(
    'scan transport retains legacy calls and validates tracked result identity',
    (tester) async {
      const channel = MethodChannel('multiplexr/tracked-scan-wire');
      final service = LibraryService(transport: ChannelTransport(channel));
      Object? seen;
      var bad = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        seen = call.arguments;
        if (seen is String) return ['legacy'];
        return {
          'requestId': bad ? 'old' : (seen as Map)['requestId'],
          'warnings': ['tracked'],
        };
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      expect(await service.scan('c'), ['legacy']);
      expect(seen, 'c');
      expect(await service.scan('c', requestId: 'r2'), ['tracked']);
      expect(seen, {'id': 'c', 'requestId': 'r2'});
      bad = true;
      await expectLater(
        service.scan('c', requestId: 'r3'),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'facades for one channel share a storage owner while separate channels and fake stores do not',
    (tester) async {
      final a = LibraryService(
        transport: ChannelTransport(
          const MethodChannel('multiplexr/same-store'),
        ),
      );
      final b = LibraryService(
        transport: ChannelTransport(
          const MethodChannel('multiplexr/same-store'),
        ),
      );
      final c = LibraryService(
        transport: ChannelTransport(
          const MethodChannel('multiplexr/other-store'),
        ),
      );
      expect(a.persistenceOwner, same(b.persistenceOwner));
      expect(c.persistenceOwner, isNot(same(a.persistenceOwner)));
      expect(
        JsonStateRepository(a).mutations,
        same(JsonStateRepository(b).mutations),
      );
      expect(
        SharedStore().persistenceOwner,
        isNot(same(SharedStore().persistenceOwner)),
      );
    },
  );
  test('every persisted collection field has ownership defaults scopes and validation', () {
    for (final kind in MediaKind.values) {
      final collection = VideoCollection(
        id: 'c',
        name: 'Collection',
        subtype: VideoSubtype.cinema,
        kind: kind,
      );
      final values = collection.toJson();
      CollectionSettingsSchema.validate(values);
      expect(
        values.keys.toSet().difference(
          CollectionSettingsSchema.fields.map((f) => f.id).toSet(),
        ),
        isEmpty,
      );
      for (final key in values.keys) {
        expect(CollectionSettingsSchema.defaults.containsKey(key), true);
      }
    }
    expect(
      () => CollectionSettingsSchema.validate({'unknown': true}),
      throwsArgumentError,
    );
    expect(
      () => CollectionSettingsSchema.validate({'audioRate': double.nan}),
      throwsArgumentError,
    );
    expect(
      () => CollectionSettingsSchema.validate({
        'locked': true,
      }, browsingOnly: true),
      throwsArgumentError,
    );
    expect(CollectionSettingsSchema.field('locked').resettable, false);
    expect(
      CollectionSettingsSchema.field('audioRate').appliesTo(MediaType.photo),
      false,
    );
  });
  test('all catalog command families are registered per scope and access is enforced', () {
    final context = MediaActionContext(
      authorized: true,
      capabilities: appSubtypes.definition(MediaSubtype.moviesTv).capabilities,
    );
    for (final key in [
      'settings',
      'tags',
      'playerSettings',
      'cinemaSpace',
      'select',
      'groupSeries',
      'scan',
      'match',
      'retry',
      'review',
      'metadataStatus',
      'health',
    ]) {
      expect(
        CatalogActionRegistry.permitted(
          CatalogActionScope.collection,
          key,
          context,
        ),
        true,
        reason: key,
      );
    }
    for (final key in [
      'tags',
      'watched',
      'unwatched',
      'favorite',
      'watchLater',
      'unfavorite',
      'unwatchLater',
      'clearMatches',
      'metadata',
    ]) {
      expect(
        CatalogActionRegistry.permitted(
          CatalogActionScope.selection,
          key,
          context,
        ),
        true,
        reason: key,
      );
    }
    expect(
      CatalogActionRegistry.permitted(
        CatalogActionScope.title,
        'remove',
        const MediaActionContext(authorized: false, capabilities: {}),
      ),
      false,
    );
    expect(
      CatalogActionRegistry.definition(
        CatalogActionScope.title,
        'remove',
      )!.destructive,
      true,
    );
    expect(
      CatalogActionRegistry.permitted(
        CatalogActionScope.collection,
        'new-unregistered',
        context,
      ),
      false,
    );
  });
  test('navigation origin round trips all view state and is restored after route completion', () async {
    const source = NavigationOrigin(
      routeId: 'videos',
      collectionId: 'c',
      query: 'search',
      sort: 'title',
      filter: '2',
      folder: 'Folder',
      tag: 'tag',
      tab: 2,
      scrollOffset: 123,
      layout: 'grid',
    );
    final restored = NavigationOrigin.fromJson(source.toJson());
    expect(restored.toJson(), source.toJson());
    NavigationOrigin? returned;
    await NavigationCoordinator().run(
      'route',
      () async {},
      origin: source,
      restore: (origin) {
        returned = origin;
      },
    );
    expect(returned, same(source));
    expect(
      () => NavigationOrigin.fromJson({
        ...source.toJson(),
        'scrollOffset': double.infinity,
      }),
      throwsFormatException,
    );
  });
}
