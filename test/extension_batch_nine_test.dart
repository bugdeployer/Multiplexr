import 'package:multiplexr/src/metadata/metadata_failures.dart';
import 'package:multiplexr/src/core/application/mutations.dart';

import 'fixtures/legacy_provider_adapters.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/catalog/domain/group_repository.dart';
import 'package:multiplexr/src/experience/actions/media_actions.dart';
import 'package:multiplexr/src/experience/navigation/opening_policy.dart';
import 'package:multiplexr/src/features/catalog/application/space_queries.dart';
import 'package:multiplexr/src/features/metadata/application/artwork_service.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_work_runner.dart';
import 'package:multiplexr/src/settings/domain/collection_settings_schema.dart';
import 'package:multiplexr/src/settings/domain/media_settings.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';

import 'library_test.dart' show MemoryLibrary;
import 'media_foundation_test.dart' show SharedStore;
import 'support/extension_fixture.dart';

void main() {
  final fixtures = extensionFixtures();
  test('R1 typed reading records reuse shared browsing, scope and opening contracts', () {
    final catalog = readingExtensionFixture();
    for (final subtype in [MediaSubtype.ebook, MediaSubtype.comics]) {
      final collection = catalog.collections.singleWhere(
        (c) => c.subtype == subtype,
      );
      final titles = catalog.titles
          .where((t) => t.catalog.subtype == subtype)
          .toList();
      final controller = SpaceController<ReadingTitle, CatalogIdentity>(
        identity: (t) => t.catalog.id,
      )..replace(titles);
      addTearDown(controller.dispose);
      controller.query = titles.first.catalog.metadata.title;
      expect(
        controller.browse(
          matches: (t) => t.catalog.metadata.title.contains(controller.query),
        ),
        [titles.first],
      );
      controller.toggle(titles.first);
      controller.replace(titles.reversed);
      expect(controller.selected, {titles.first.catalog.id});
      expect(
        SpaceScope(subtype).includes(collection, authorized: false),
        false,
      );
      final locked = CatalogCollection(
        id: collection.id,
        name: collection.name,
        subtype: subtype,
        access: const CatalogAccess(locked: true, includeInGlobal: false),
        roots: collection.roots,
      );
      expect(SpaceScope(subtype).includes(locked, authorized: true), false);
      expect(
        SpaceScope(
          subtype,
          collectionId: locked.id,
        ).includes(locked, authorized: true),
        true,
      );
      expect(
        const OpeningPolicy().resolve(
          group: true,
          action: TitleOpenAction.play,
        ),
        OpeningDestination.contents,
      );
      expect(
        const OpeningPolicy().resolve(
          group: false,
          action: TitleOpenAction.details,
        ),
        OpeningDestination.details,
      );
      expect(appSubtypes.requireEnabled(subtype).id, subtype);
    }
  });
  test('extension fixtures do not enable unfinished subtypes; Music now has production routes', () {
    expect(fixtures.map((f) => f.subtype).toSet(), {
      MediaSubtype.music,
      MediaSubtype.ebook,
      MediaSubtype.comics,
      MediaSubtype.photo,
      MediaSubtype.gif,
    });
    expect(appSubtypes.enabled.map((s) => s.id).toSet(), {
      MediaSubtype.moviesTv,
      MediaSubtype.videos,
      MediaSubtype.audiobooks,
      MediaSubtype.music,
      MediaSubtype.ebook,
      MediaSubtype.comics,
    });
    for (final fixture in fixtures) {
      if ({
        MediaSubtype.music,
        MediaSubtype.ebook,
        MediaSubtype.comics,
      }.contains(fixture.subtype)) {
        expect(appSubtypes.requireEnabled(fixture.subtype).id, fixture.subtype);
        expect(fixture.registry.enabled, isEmpty);
        continue;
      }
      expect(
        () => appSubtypes.requireEnabled(fixture.subtype),
        throwsUnsupportedError,
      );
      expect(fixture.registry.enabled, isEmpty);
      expect(
        () => appSubtypes.validateBindings(
          collectionRoutes: {fixture.subtype},
          engines: {fixture.registry.definition(fixture.subtype).engine},
        ),
        throwsUnsupportedError,
      );
    }
  });

  for (final fixture in fixtures) {
    group(fixture.subtype.label, () {
      test('neutral records retain sources and typed metadata without audio/video IDs', () {
        final titles = fixture.titles;
        expect(fixture.collection().roots, hasLength(2));
        expect(titles.first.subtype, fixture.subtype);
        expect(titles.first.metadata['creator'], startsWith('Fixture'));
        expect(titles.last.sources.single.available, false);
        expect(titles.every((t) => t.segments.isEmpty), true);
        expect(titles.first.id, fixture.titles.first.id);
        expect(
          () => titles.first.metadata['creator'] = 'Mutated',
          throwsUnsupportedError,
        );
        expect(
          () => fixture.collection().roots.clear(),
          throwsUnsupportedError,
        );
      });

      test('uses shared settings inheritance and subtype field applicability', () {
        final layers = [
          SettingsLayer(SettingsScope.app, 'app', {
            'opening': const SettingOverride.value(TitleOpenAction.play),
          }),
          SettingsLayer(SettingsScope.collection, fixture.collectionId, {
            'opening': const SettingOverride.value(TitleOpenAction.details),
          }),
          SettingsLayer(SettingsScope.group, 'primary', {
            'opening': const SettingOverride.inherit(),
          }),
        ];
        final value = const SettingsResolver().resolve(
          MediaSettings.opening,
          layers,
        );
        expect(value.value, TitleOpenAction.details);
        expect(value.sourceId, fixture.collectionId);
        final audioField = CollectionSettingsSchema.fields.firstWhere(
          (f) => f.id == 'audioRate',
        );
        expect(
          audioField.appliesTo(fixture.subtype.type),
          fixture.subtype.type == MediaType.audio,
        );
        // A reader-specific preference uses the same resolver, without putting
        // reading locations into the legacy time-based playback contract.
        final textSize = SettingDefinition<int>('readerTextSize', 18, {
          SettingsScope.collection,
          SettingsScope.title,
        }, (v) => v is int && v >= 12 && v <= 40);
        expect(
          const SettingsResolver().resolve(textSize, [
            SettingsLayer(SettingsScope.title, 'title-1', {
              'readerTextSize': const SettingOverride.value(22),
            }),
          ]).value,
          22,
        );
      });

      test('shared browsing filters metadata, retains selection, and preserves scopes', () {
        final titles = fixture.titles;
        final controller =
            SpaceController<
                CatalogTitle<Map<String, dynamic>>,
                CatalogIdentity
              >(identity: (t) => t.id)
              ..replace(titles)
              ..query = 'example'
              ..tag = 'keep';
        addTearDown(controller.dispose);
        for (final layout in CatalogLayout.values) {
          controller.layout = layout;
          final result = controller.browse(
            matches: (t) =>
                t.title.toLowerCase().contains(controller.query) &&
                (t.metadata['tags'] as List).contains(controller.tag) &&
                t.metadata['rating'] >= 1,
          );
          expect(result.map((t) => t.id), [titles.first.id]);
        }
        controller.toggle(titles.first);
        controller.replace(fixture.titles.reversed);
        expect(controller.selected, {titles.first.id});
        expect(controller.query, 'example');
        expect(
          controller.showcase(titles, [
            titles.last.id,
            titles.first.id,
            titles.last.id,
          ], pinned: true),
          [titles.last, titles.first],
        );
        expect(
          controller.browsing(
            titles,
            hideCompleted: true,
            completed: (t) => t.id == titles.first.id,
          ),
          [titles.last],
        );
        expect(controller.items, hasLength(2));
        final excluded = fixture.collection(locked: true, global: false);
        expect(
          SpaceScope(fixture.subtype).includes(excluded, authorized: true),
          false,
        );
        expect(
          SpaceScope(
            fixture.subtype,
            collectionId: excluded.id,
          ).includes(excluded, authorized: true),
          true,
        );
        expect(
          SpaceScope(
            fixture.subtype,
            collectionId: excluded.id,
          ).includes(excluded, authorized: false),
          false,
        );
        expect(
          SpaceScope(MediaSubtype.videos)
              .includes(fixture.collection(), authorized: true),
          false,
        );
      });

      test('declared groups share validation and ordering; playlists do not reparent', () {
        final graph = fixture.graph();
        final group = graph.groups.first;
        final before = graph.children(group.id);
        final order = graph.order(group.id, before.reversed.toList());
        expect(order[before.last], 0);
        expect(
          () => graph.order(group.id, before.take(1).toList()),
          throwsStateError,
        );
        expect(
          () => fixture.graph(
            memberships: [...graph.memberships, graph.memberships.first],
          ),
          throwsStateError,
        );
        expect(
          () => fixture.graph(
            memberships: [
              ...graph.memberships,
              GroupMembership(
                parent: group.id,
                child: fixture.identity('missing', CatalogEntityKind.title),
                kind: MembershipKind.structural,
                order: 9,
              ),
            ],
          ),
          throwsStateError,
        );
        if (fixture.subtype == MediaSubtype.music) {
          final playlist = graph.groups.last;
          expect(graph.children(playlist.id).toSet(), before.toSet());
          expect(graph.children(group.id), before);
          expect(fixture.titles, hasLength(2));
        }
        expect(
          const OpeningPolicy().resolve(
            group: true,
            action: TitleOpenAction.play,
          ),
          OpeningDestination.contents,
        );
        expect(
          const OpeningPolicy().resolve(
            group: false,
            action: TitleOpenAction.details,
          ),
          OpeningDestination.details,
        );
        expect(
          const OpeningPolicy().resolve(
            group: false,
            action: TitleOpenAction.play,
            available: false,
          ),
          OpeningDestination.unavailable,
        );
      });

      test('metadata single and bulk paths reuse review, conflict and job services', () async {
        final store = SharedStore();
        final coordinator = MetadataWorkflow([
          FixtureProvider(fixture.entity),
        ], mutations: const OwnerApplicationMutations());
        final request = MetadataSearchRequest(
          provider: 'extension-fixture',
          entity: fixture.entity,
          title: fixture.titles.first.title,
        );
        final token = MetadataCancellation();
        final first = await coordinator.search(request, token);
        expect(first.nextPage, 2);
        expect(
          (await coordinator.search(request.atPage(2), token)).nextPage,
          isNull,
        );
        final targets = [
          for (final title in fixture.titles)
            FixtureTarget(
              store,
              fixture.entity,
              'fixture:${fixture.subtype.name}:${title.id.entityId}',
            ),
        ];
        for (final target in targets) {
          await store.writeState(target.key, {
            'fields': {'title': 'Local title', 'creator': 'Manual creator'},
          });
        }
        final reviews = [
          for (final target in targets)
            await coordinator.review(target, first.candidates.single, token),
        ];
        expect(reviews.first.defaults, isNot(contains('creator')));
        var done = 0, checkpoints = 0;
        expect(
          await MetadataWorkRunner(classify: metadataFailure).run(
            owner: store.persistenceOwner,
            key: fixture.collectionId,
            work: List.generate(targets.length, (i) => i),
            cancellation: token,
            checkpoint: () async {
              checkpoints++;
            },
            process: (i) => coordinator.apply(
              targets[i],
              reviews[i],
              reviews[i].defaults,
              token,
            ),
            completed: (_) async {
              done++;
            },
          ),
          true,
        );
        expect(done, 2);
        expect(checkpoints, 3);
        for (final target in targets) {
          final current = await target.read();
          expect(current.fields['creator'], 'Manual creator');
          expect(current.fields['description'], 'Provider description');
        }
        final review = await coordinator.review(
          targets.first,
          first.candidates.single,
          token,
        );
        await store.writeState(targets.first.key, {
          'fields': {...review.before.fields, 'description': 'New local edit'},
        });
        await expectLater(
          coordinator.apply(targets.first, review, {'description'}, token),
          throwsA(
            isA<MetadataFailure>().having(
              (e) => e.kind,
              'kind',
              MetadataFailureKind.conflict,
            ),
          ),
        );
        targets.last.authorized = false;
        await expectLater(
          coordinator.review(targets.last, first.candidates.single, token),
          throwsA(
            isA<MetadataFailure>().having(
              (e) => e.kind,
              'kind',
              MetadataFailureKind.permission,
            ),
          ),
        );
      });

      test(
        'artwork and standard actions reuse shared policy with access checks',
        () async {
          final service = ArtworkService(), token = MetadataCancellation();
          final role = switch (fixture.subtype.type) {
            MediaType.ebook => ArtworkRole.poster,
            MediaType.photo => ArtworkRole.thumbnail,
            _ => ArtworkRole.cover,
          };
          final owner = fixture.titles.first.id.entityId;
          final candidates = await service.candidates(
            () async => [
              'https://example.test/cover.png',
              'https://example.test/cover.png',
              '',
            ],
            ownerId: owner,
            role: role,
            provider: 'fixture',
            cancellation: token,
          );
          expect(candidates, hasLength(1));
          expect(candidates.single.aspectRatio, switch (fixture.subtype.type) {
            MediaType.ebook => 2 / 3,
            MediaType.photo => 16 / 9,
            _ => 1,
          });
          expect(
            await service.select(
              candidates.single,
              token,
              download: (_) async => 'content://fixture/saved-cover',
            ),
            'content://fixture/saved-cover',
          );
          for (final source in [ArtworkSource.device, ArtworkSource.child]) {
            expect(
              await service.select(
                ArtworkCandidate(
                  location: 'content://fixture/image',
                  role: ArtworkRole.cover,
                  source: source,
                  ownerId: owner,
                ),
                token,
              ),
              'content://fixture/image',
            );
          }
          var authorized = true, called = 0;
          MediaActionContext context() => MediaActionContext(
            authorized: authorized,
            capabilities: fixture.registry
                .definition(fixture.subtype)
                .capabilities,
            hasSettings: true,
          );
          for (final action in MediaActionRegistry.definitions) {
            expect(MediaActionRegistry.permitted(action.id, context()), true);
          }
          await MediaActionRegistry.execute(
            MediaActionId.chooseArtwork,
            context,
            () async {
              called++;
            },
          );
          authorized = false;
          await expectLater(
            MediaActionRegistry.execute(
              MediaActionId.chooseArtwork,
              context,
              () async {
                called++;
              },
            ),
            throwsStateError,
          );
          expect(called, 1);
        },
      );
    });
  }
  test('existing providers reject future entities rather than treating them as movies/books', () async {
    final token = MetadataSearchRequest(
      provider: 'tmdb',
      entity: MetadataEntityType.musicTrack,
      title: 'Example',
    );
    for (final provider in [
      TmdbMetadataProvider(MemoryLibrary()),
      const AudiobookMetadataProvider('audible'),
    ]) {
      await expectLater(
        provider.search(token),
        throwsA(
          isA<MetadataFailure>().having(
            (e) => e.kind,
            'kind',
            MetadataFailureKind.unavailable,
          ),
        ),
      );
    }
  });
  test(
    'hierarchy declarations reject undeclared edges and curated non-playlists',
    () {
      expect(
        () => HierarchyDefinition(
          groups: [CatalogGroupKind.album],
          structuralTitleParents: [CatalogGroupKind.series],
        ),
        throwsArgumentError,
      );
      expect(
        () => HierarchyDefinition(
          groups: [CatalogGroupKind.album],
          curatedParents: [CatalogGroupKind.album],
        ),
        throwsArgumentError,
      );
      final fixture = fixtures.first;
      final graph = fixture.graph();
      // Music now declares albums/playlists, while its route remains disabled.
      final declared = GroupSnapshot(
        groups: graph.groups,
        titles: graph.titles,
        memberships: graph.memberships,
      );
      expect(declared.groups, hasLength(graph.groups.length));
      expect(
        () => GroupSnapshot(
          groups: [
            CatalogGroup(
              id: graph.groups.first.id,
              subtype: MediaSubtype.music,
              kind: CatalogGroupKind.season,
              metadata: null,
            ),
          ],
          titles: graph.titles,
          memberships: [],
        ),
        throwsStateError,
      );
    },
  );
}
