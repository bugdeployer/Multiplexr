import 'fixtures/legacy_library_assembly.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/catalog/domain/group_repository.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/series.dart';
import 'package:multiplexr/src/features/catalog/application/series_groups.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audiobook_group_repository.dart';

import 'grouped_media_test.dart' show audiobook;
import 'media_foundation_test.dart' show SharedStore;

VideoAsset episode(String id, int season, int number, {String root = 'root'}) =>
    VideoAsset.fromJson({
      'id': id,
      'collectionId': 'tv',
      'uri': 'content://$id',
      'filename': '$id.mp4',
      'rootUri': root,
      'relativePath': 'Show/Season $season/$id.mp4',
      'contentSubtype': 'tv',
      'positionMs': 4321,
      'metadata': {
        'title': id,
        'series': 'Show',
        'season': '$season',
        'episode': '$number',
      },
    }, VideoSubtype.tv);

void main() {
  test(
    'TV graph retains specials, versions and isolates equal names across roots',
    () {
      final assets = [
        episode('a', 1, 1),
        episode('version', 1, 1),
        episode('special', 0, 1),
        episode('other', 1, 1, root: 'other'),
      ];
      final graph = seriesGroupSnapshot(assets);
      expect(
        graph.groups.where((g) => g.kind == CatalogGroupKind.series),
        hasLength(2),
      );
      expect(graph.titles, hasLength(3));
      expect(
        buildSeries(assets).first.episodes.expand((e) => e.versions),
        isNotEmpty,
      );
    },
  );

  test(
    'TV repeated order retains source IDs, versions, season and progress',
    () async {
      var assets = [
        episode('a', 1, 1),
        episode('version', 1, 1),
        episode('b', 1, 2),
      ];
      final repository = SeriesGroupRepository(
        read: () async => assets,
        save: (changes) async {
          validateSeriesCorrections(assets, changes);
          assets = changes;
        },
      );
      final series = buildSeries(assets).single;
      final order = series.episodes.reversed.map(episodeTitleIdentity).toList();
      await repository.reorderSeries(seriesGroupIdentity(series), order);
      final first = assets.map((a) => a.toJson()).toList();
      await repository.reorderSeries(seriesGroupIdentity(series), order);
      expect(assets.map((a) => a.toJson()).toList(), first);
      expect(assets.map((a) => a.id).toSet(), {'a', 'version', 'b'});
      expect(assets.every((a) => a.positionMs == 4321), isTrue);
      expect(buildSeries(assets).single.episodes.last.versions, hasLength(2));
      await expectLater(
        repository.reorderSeries(
          seriesGroupIdentity(series),
          order.take(1).toList(),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'audiobook order is idempotent and stale orders cannot omit a new title',
    () async {
      final library = createAudioLibrary(SharedStore());
      final original = audiobook('one', series: 'Saga');
      final books = [
        Audiobook(
          id: original.id,
          metadata: original.metadata,
          files: [
            ...original.files,
            const AudioFile(
              id: 'part2',
              uri: 'content://audio/part2',
              filename: 'part2.mp3',
              durationMs: 60000,
            ),
          ],
        ),
        audiobook('two', series: 'Saga'),
        audiobook('standalone'),
      ];
      await library.save(books);
      final repository = AudiobookGroupRepository(library);
      final graph = await repository.snapshot();
      expect(graph.groups, hasLength(2));
      final group = graph.groups.firstWhere(
        (g) => graph.children(g.id).length == 2,
      );
      final order = graph.children(group.id).reversed.toList();
      await repository.reorder(group.id, order);
      final first = (await library.books()).map((b) => b.toJson()).toList();
      await repository.reorder(group.id, order);
      expect((await library.books()).map((b) => b.toJson()).toList(), first);
      await library.update(
        (current) => [...current, audiobook('new', series: 'Saga')],
      );
      await expectLater(repository.reorder(group.id, order), throwsStateError);
      expect(await library.books(), hasLength(4));
    },
  );

  test('graph rejects dangling and multiple structural owners', () {
    final title = CatalogIdentity('c', 'title', CatalogEntityKind.title);
    final groups = [
      for (final name in ['a', 'b'])
        CatalogGroup<Object?>(
          id: CatalogIdentity('c', name, CatalogEntityKind.group),
          subtype: MediaSubtype.audiobooks,
          kind: CatalogGroupKind.series,
          metadata: null,
        ),
    ];
    final edges = [
      for (final group in groups)
        GroupMembership(
          parent: group.id,
          child: title,
          kind: MembershipKind.structural,
          order: 0,
        ),
    ];
    expect(
      () => GroupSnapshot(groups: groups, titles: [title], memberships: edges),
      throwsStateError,
    );
    expect(
      () =>
          GroupSnapshot(groups: groups, titles: [], memberships: edges.take(1)),
      throwsStateError,
    );
  });

  test('provider display changes do not change frozen ownership; manual correction wins', () {
    final original = episode('a', 1, 1);
    final anchor = seriesIdentity(original);
    final updated = VideoAsset.fromJson({
      ...original.toJson(),
      'seriesId': 99,
      'metadata': {
        ...original.metadata,
        'series': 'Online title',
        'structuralSeriesId': anchor,
      },
    }, VideoSubtype.tv);
    expect(seriesIdentity(updated), anchor);
    final corrected = VideoAsset.fromJson({
      ...updated.toJson(),
      'metadata': {...updated.metadata, 'groupId': 'manual'},
    }, VideoSubtype.tv);
    expect(seriesIdentity(corrected), 'manual:manual');
  });
}
