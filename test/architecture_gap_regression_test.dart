import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/bootstrap/settings_assembly.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/catalog/domain/group_repository.dart';
import 'package:multiplexr/src/features/catalog/application/collection_presenter.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/settings/domain/collection_settings_schema.dart';
import 'package:app_shell/app_shell.dart';

import 'collection_space_batch_six_test.dart' show TestCollectionJob;
import 'media_foundation_test.dart' show SharedStore;
import 'support/extension_fixture.dart' show FixtureTarget;
import 'widget_test.dart' show TestDevice;

class HeldThemeDevice extends TestDevice {
  final entered = Completer<void>(), release = Completer<void>();
  bool hold = false;
  int writes = 0;
  @override
  Future<void> save(Map<String, dynamic> data) async {
    if (hold && ++writes == 1) {
      entered.complete();
      await release.future;
    }
    await super.save(data);
  }
}

class PageProvider implements MetadataProvider {
  PageProvider(this.response);
  final MetadataSearchPage Function(MetadataSearchRequest) response;
  @override
  String get id => 'fixture';
  @override
  Set<MetadataEntityType> get entities => {MetadataEntityType.ebook};
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async =>
      response(request);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test('overlapping theme imports keep both installed definitions on disk and in memory', () async {
    final device = HeldThemeDevice();
    final settings = createSettingsController(device);
    addTearDown(settings.dispose);
    await settings.load();
    device.hold = true;
    String theme(String id) => jsonEncode({
      ...AppThemeDefinition.bundled!['retro']!.toJson(),
      'id': id,
      'name': id,
    });
    final first = settings.importTheme(theme('first'));
    await device.entered.future;
    final second = settings.importTheme(theme('second'));
    await Future<void>.delayed(Duration.zero);
    expect(device.writes, 1);
    device.release.complete();
    await Future.wait([first, second]);
    expect(settings.themes.keys, containsAll(['first', 'second']));
    final saved = jsonDecode(device.values['themeState']);
    expect(
      (saved['custom'] as List).map((t) => t['id']),
      containsAll(['first', 'second']),
    );
    expect(saved['selected'], 'second');
    expect(settings.selectedTheme!.id, 'second');
  });
  test('queued theme operations recover after a failed save without changing palette', () async {
    final device = TestDevice();
    final settings = createSettingsController(device);
    addTearDown(settings.dispose);
    await settings.load();
    final original = settings.selectedTheme!.id;
    final palette = (
      settings.darkBase,
      settings.darkAccent,
      settings.themeOverrides,
    );
    device.failSave = true;
    await expectLater(settings.selectTheme('modern'), throwsException);
    expect(settings.selectedTheme!.id, original);
    device.failSave = false;
    await settings.selectTheme('modern');
    expect(settings.selectedTheme!.id, 'modern');
    expect((
      settings.darkBase,
      settings.darkAccent,
      settings.themeOverrides,
    ), palette);
  });
  test(
    'metadata snapshots and reviews cannot be changed through nested aliases',
    () {
      final nested = <String, dynamic>{
        'tags': ['original'],
        'edition': {'language': 'en'},
      };
      final manual = {'title'};
      final before = MetadataSnapshot(nested, manualFields: manual);
      (nested['tags'] as List).add('injected');
      manual.clear();
      expect(before.fields['tags'], ['original']);
      expect(before.manualFields, {'title'});
      expect(
        () => (before.fields['edition'] as Map)['language'] = 'changed',
        throwsUnsupportedError,
      );
      final candidate = MetadataCandidate(
        provider: 'fixture',
        id: 'one',
        entity: MetadataEntityType.ebook,
        values: nested,
        attribution: 'Fixture',
      );
      final review = MetadataReview(
        candidate: candidate,
        targetKey: 't',
        owner: Object(),
        before: before,
        proposed: nested,
      );
      (nested['tags'] as List).clear();
      expect(review.proposed['tags'], ['original', 'injected']);
      expect(
        () => (review.proposed['tags'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'nested metadata uses structural equality for apply and detects real edits',
    () async {
      final store = SharedStore();
      final target = FixtureTarget(store, MetadataEntityType.ebook, 'nested');
      await store.writeState(target.key, {
        'fields': {
          'tags': ['old'],
          'edition': {'language': 'en', 'year': 2020},
        },
      });
      final candidate = MetadataCandidate(
        provider: 'fixture',
        id: 'one',
        entity: target.entity,
        values: {
          'tags': ['new'],
          'edition': {'year': 2020, 'language': 'en'},
        },
        attribution: 'Fixture',
      );
      final coordinator = MetadataWorkflow(
            [],
            mutations: const OwnerApplicationMutations(),
          ),
          token = MetadataCancellation();
      final review = await coordinator.review(target, candidate, token);
      await coordinator.apply(target, review, {'tags', 'edition'}, token);
      expect((await target.read()).fields['tags'], ['new']);
      final next = await coordinator.review(target, candidate, token);
      await store.writeState(target.key, {
        'fields': {
          'tags': ['manual change'],
        },
      });
      await expectLater(
        coordinator.apply(target, next, {'tags'}, token),
        throwsA(
          isA<MetadataFailure>().having(
            (e) => e.kind,
            'kind',
            MetadataFailureKind.conflict,
          ),
        ),
      );
    },
  );
  for (final bad in [
    'query',
    'entity',
    'provider',
    'emptyId',
    'continuation',
  ]) {
    test(
      'metadata boundary rejects malformed $bad result before publishing it',
      () async {
        final provider = PageProvider(
          (request) => MetadataSearchPage(
            request: bad == 'query'
                ? MetadataSearchRequest(
                    provider: 'fixture',
                    entity: request.entity,
                    title: 'Other',
                  )
                : request,
            nextPage: bad == 'continuation' ? request.page : null,
            attribution: 'Fixture',
            candidates: [
              MetadataCandidate(
                provider: bad == 'provider' ? 'other' : 'fixture',
                id: bad == 'emptyId' ? ' ' : 'one',
                entity: bad == 'entity'
                    ? MetadataEntityType.audiobook
                    : request.entity,
                values: {'title': 'Title'},
                attribution: 'Fixture',
              ),
            ],
          ),
        );
        await expectLater(
          MetadataWorkflow([
            provider,
          ], mutations: const OwnerApplicationMutations()).search(
            const MetadataSearchRequest(
              provider: 'fixture',
              entity: MetadataEntityType.ebook,
              title: 'Title',
            ),
            MetadataCancellation(),
          ),
          throwsA(
            isA<MetadataFailure>().having(
              (e) => e.kind,
              'kind',
              MetadataFailureKind.invalidResponse,
            ),
          ),
        );
      },
    );
  }
  test('disposed collections perform no new reads and cancel duplicate job ownership once', () async {
    final controller = CollectionController<String, String>(identity: (s) => s);
    final job = TestCollectionJob();
    controller.ownJob(job);
    controller.ownJob(job);
    final gate = Completer<List<String>>();
    final load = controller.load(() => gate.future, failure: 'Failed');
    controller.dispose();
    expect(controller.loading, false);
    var reads = 0;
    expect(
      await controller.load(() async {
        reads++;
        return ['new'];
      }, failure: 'Failed'),
      false,
    );
    expect(reads, 0);
    expect(job.cancellations, 1);
    expect(job.disposals, 1);
    gate.complete(['old']);
    expect(await load, false);
  });
  test('required series membership is enforced even when no groups exist', () {
    final id = CatalogIdentity('c', 'title', CatalogEntityKind.title);
    expect(
      () => GroupSnapshot(
        groups: [],
        titles: [id],
        titleSubtypes: {id: MediaSubtype.audiobooks},
        memberships: [],
      ),
      throwsStateError,
    );
    expect(
      () => HierarchyDefinition(
        groups: [CatalogGroupKind.series],
        titleRequiresGroup: true,
      ),
      throwsArgumentError,
    );
    expect(
      () => GroupSnapshot(
        groups: [],
        titles: [CatalogIdentity('c', 'wrong-kind', CatalogEntityKind.group)],
        memberships: [],
      ),
      throwsStateError,
    );
  });
  test(
    'neutral title contract rejects empty source identities and locations',
    () {
      for (final source in [
        const CatalogSource(id: '', uri: 'content://file', name: 'File'),
        const CatalogSource(id: 'file', uri: '', name: 'File'),
      ]) {
        expect(
          () => CatalogTitle(
            id: CatalogIdentity('c', 'title', CatalogEntityKind.title),
            subtype: MediaSubtype.ebook,
            title: 'Title',
            metadata: const {},
            sources: [source],
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'collection card sizes use the same bounds as native backup validation',
    () {
      for (final size in [99, 301, double.infinity, double.nan]) {
        expect(
          () => CollectionSettingsSchema.validate({'cardSize': size}),
          throwsArgumentError,
        );
      }
      for (final size in [100, 180.5, 300]) {
        CollectionSettingsSchema.validate({'cardSize': size});
      }
    },
  );
  test('theme asset bytes are detached from caller-owned mutable buffers', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final asset = ThemeAsset(
      'assets/icon.png',
      'image/png',
      'digest',
      'MIT',
      'Fixture',
      bytes,
    );
    bytes[0] = 9;
    expect(asset.bytes, [1, 2, 3]);
    expect(() => asset.bytes[0] = 8, throwsUnsupportedError);
  });
}
