import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/features/catalog/application/catalog_commands.dart';
import 'package:multiplexr/src/features/catalog/application/catalog_queries.dart';
import 'package:multiplexr/src/features/sources/application/reading_scan_workflow.dart';
import 'package:multiplexr/src/features/sources/application/reading_scan_plan.dart';
import 'package:multiplexr/src/features/sources/application/reading_source_ports.dart';
import 'package:multiplexr/src/features/sources/application/scan_collections.dart';
import 'package:multiplexr/src/features/sources/application/source_ports.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_repository.dart';
import 'package:multiplexr/src/media/contracts.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'rx_composition_test.dart' show FixedClock;

class FakeSources implements CollectionSources {
  final events = StreamController<ScanProgressEvent>.broadcast(sync: true);
  final result = Completer<List<String>>();
  final entered = Completer<void>();
  String? request;
  final cancelled = <String>[];
  @override
  Stream<ScanProgressEvent> get progress => events.stream;
  @override
  Future<List<String>> scan(
    VideoCollection collection, {
    required String requestId,
    required bool Function() authorized,
    required bool Function() cancelled,
  }) {
    request = requestId;
    expect(authorized(), true);
    entered.complete();
    return result.future;
  }

  @override
  Future<void> cancel(String collectionId) async => cancelled.add(collectionId);
  @override
  Future<LibraryRoot?> pickRoot() async =>
      const LibraryRoot('content://root', 'Root');
  @override
  Future<void> releaseRoots(List<String> uris) async {}
}

class FakeReadingSources implements ReadingSources {
  Completer<void>? gate;
  int commits = 0;
  @override
  Future<void> commit(
    ReadingScanPreview preview, {
    required void Function() checkAccess,
  }) async {
    await gate?.future;
    checkAccess();
    commits++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const collection = VideoCollection(
    id: 'c',
    name: 'Collection',
    subtype: VideoSubtype.videos,
  );

  test(
    'catalog command waiting for mutation owner rechecks revoked access',
    () async {
      final service = SharedStore();
      var allowed = true;
      final repository = LegacyLibraryRepository(
        service,
        authorized: (_) => allowed,
      );
      final entered = Completer<void>(), release = Completer<void>();
      final lock = MutationCoordinator.forOwner(service.persistenceOwner)
          .run('catalog:commands', () async {
            entered.complete();
            await release.future;
          });
      await entered.future;
      final commands = CatalogCommands(
        repository,
        authorized: (_) => allowed,
        collections: () => [collection],
        assets: () => [],
      );
      final save = commands.save(collection);
      final rejected = expectLater(save, throwsStateError);
      allowed = false;
      release.complete();
      await lock;
      await rejected;
      expect(service.collections, isEmpty);
    },
  );

  test(
    'application catalog queries preserve global exclusions and live access',
    () {
      var allowed = true;
      final local = VideoCollection.fromJson({
        ...collection.toJson(),
        'includeInGlobalVideos': false,
      });
      final query = CatalogQueries(
        collections: () => [local],
        assets: () => [],
        authorized: (_) => allowed,
      );
      expect(query.scoped(MediaSubtype.videos), isEmpty);
      expect(query.scoped(MediaSubtype.videos, collectionId: 'c'), [local]);
      allowed = false;
      expect(query.scoped(MediaSubtype.videos, collectionId: 'c'), isEmpty);
    },
  );

  for (final owner in [
    collection,
    VideoCollection.fromJson({...collection.toJson(), 'subtype': 'cinema'}),
    VideoCollection.fromJson({
      ...collection.toJson(),
      'type': 'audio',
      'subtype': 'audiobooks',
    }),
    VideoCollection.fromJson({
      ...collection.toJson(),
      'type': 'audio',
      'subtype': 'music',
    }),
  ]) {
    test(
      '${owner.mediaLabel} CRUD and appearance use the shared application path',
      () async {
        final service = SharedStore();
        final library = createLibraryController(service);
        await library.save(owner);
        expect(library.collections.single.id, owner.id);
        await library.saveBrowsing(owner.id, {
          'view': 'compact',
          'cardSize': 144.0,
        });
        final saved = library.collections.single;
        expect(saved.view, CatalogView.compact);
        expect(saved.cardSize, 144.0);
        expect(saved.kind, owner.kind);
        expect(saved.subtype, owner.subtype);
        await library.remove(owner.id);
        expect(library.collections, isEmpty);
        library.dispose();
      },
    );
  }

  for (final kind in [MediaKind.video, MediaKind.audiobook, MediaKind.music]) {
    test(
      '$kind scan cancellation drops progress and late completion effects',
      () async {
        final source = FakeSources();
        var reloads = 0, saves = 0;
        final owner = VideoCollection.fromJson({
          ...collection.toJson(),
          'type': kind == MediaKind.video ? 'video' : 'audio',
          'subtype': kind == MediaKind.music
              ? 'music'
              : kind == MediaKind.audiobook
              ? 'audiobooks'
              : 'videos',
        });
        final scan = ScanCollections(
          source,
          clock: FixedClock(),
          collection: (_) => owner,
          authorized: (_) => true,
          save: (_) async {
            saves++;
          },
          reload: () async {
            reloads++;
          },
          changed: () {},
        );
        final work = scan.scan('c');
        await source.entered.future;
        await scan.cancel('c');
        source.events.add(
          ScanProgressEvent(
            collectionId: 'c',
            found: 999,
            folder: 'Late',
            requestId: source.request,
          ),
        );
        expect(scan.progress['c']?['found'], 0);
        source.result.complete(['Late warning']);
        await work;
        expect(reloads, 0);
        expect(saves, 0);
        expect(scan.warnings, isEmpty);
        expect(scan.running, isEmpty);
        expect(source.cancelled, ['c']);
        scan.dispose();
        await source.events.close();
      },
    );
  }

  test(
    'revocation during a scan cancels native work and hides source details',
    () async {
      final source = FakeSources();
      var allowed = true;
      final scan = ScanCollections(
        source,
        clock: FixedClock(),
        collection: (_) => collection,
        authorized: (_) => allowed,
        save: (_) async {},
        reload: () async {},
        changed: () {},
      );
      final work = scan.scan('c');
      await source.entered.future;
      source.events.add(
        ScanProgressEvent(
          collectionId: 'c',
          found: 1,
          folder: 'Private folder',
          requestId: source.request,
        ),
      );
      allowed = false;
      scan.revokeInaccessible();
      expect(source.cancelled, ['c']);
      expect(scan.progress, isEmpty);
      source.result.complete(['Private warning']);
      await work;
      expect(scan.warnings, isEmpty);
      await expectLater(scan.scan('c'), throwsStateError);
      scan.dispose();
      await source.events.close();
    },
  );

  test(
    'disposed scan coordinator cannot refresh after late completion',
    () async {
      final source = FakeSources();
      var effects = 0;
      final scan = ScanCollections(
        source,
        clock: FixedClock(),
        collection: (_) => collection,
        authorized: (_) => true,
        save: (_) async {
          effects++;
        },
        reload: () async {
          effects++;
        },
        changed: () {},
      );
      final work = scan.scan('c');
      await source.entered.future;
      scan.dispose();
      source.result.complete([]);
      await work;
      expect(effects, 0);
      expect(scan.running, isEmpty);
      await source.events.close();
    },
  );

  for (final subtype in ['ebook', 'comics']) {
    test(
      '$subtype incomplete scan is rejected through the application source port',
      () async {
        final source = FakeReadingSources();
        final workflow = ReadingScanWorkflow(
          source,
          authorized: (_) => true,
          clock: FixedClock(),
        );
        final preview = ReadingScanPreview(
          collectionId: 'c',
          requestId: 'test',
          complete: false,
          added: 0,
          relinked: 0,
          missing: 0,
        );
        await expectLater(workflow.apply('c', preview), throwsStateError);
        expect(source.commits, 0);
      },
    );
  }

  test(
    'reading apply rechecks authorization after waiting for commit ownership',
    () async {
      final source = FakeReadingSources()..gate = Completer<void>();
      var allowed = true;
      final workflow = ReadingScanWorkflow(
        source,
        authorized: (_) => allowed,
        clock: FixedClock(),
      );
      final preview = ReadingScanPreview(
        collectionId: 'c',
        requestId: 'test',
        complete: true,
        added: 1,
        relinked: 0,
        missing: 0,
      );
      final work = workflow.apply('c', preview);
      final rejected = expectLater(work, throwsStateError);
      allowed = false;
      source.gate!.complete();
      await rejected;
      expect(source.commits, 0);
    },
  );

  test(
    'shared controller cancels a scan when its collection session relocks',
    () async {
      final source = FakeSources(), store = SharedStore();
      final locked = VideoCollection.fromJson({
        ...collection.toJson(),
        'locked': true,
      });
      store.collections.add(locked.toJson());
      final controller = createLibraryController(store, sources: source);
      await controller.load();
      controller.beginCollectionSession('c');
      controller.authorizeCollection('c');
      final work = controller.scan('c');
      await source.entered.future;
      controller.endCollectionSession();
      expect(source.cancelled, ['c']);
      source.result.complete([]);
      await work;
      expect(controller.canAccessCollection('c'), false);
      controller.dispose();
      await source.events.close();
    },
  );
}
