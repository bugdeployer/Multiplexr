import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/classification.dart';
import '../../../catalog/domain/group_repository.dart';
import '../../../library/library_models.dart';
import '../../../library/series.dart';

CatalogIdentity seriesGroupIdentity(SeriesRecord series) => CatalogIdentity(
  series.assets.first.collectionId,
  series.id,
  CatalogEntityKind.group,
);
CatalogIdentity episodeTitleIdentity(EpisodeRecord episode) => CatalogIdentity(
  episode.asset.collectionId,
  episode.id,
  CatalogEntityKind.title,
);

/// Versions remain sources of one logical episode; specials retain season zero.
GroupSnapshot seriesGroupSnapshot(List<VideoAsset> assets) {
  final series = buildSeries(assets);
  return GroupSnapshot(
    groups: [
      for (final item in series) ...[
        CatalogGroup<Object?>(
          id: seriesGroupIdentity(item),
          subtype: MediaSubtype.moviesTv,
          kind: CatalogGroupKind.series,
          metadata: item,
        ),
        for (final season in item.seasons)
          CatalogGroup<Object?>(
            id: CatalogIdentity(
              item.assets.first.collectionId,
              season.id,
              CatalogEntityKind.group,
            ),
            subtype: MediaSubtype.moviesTv,
            kind: CatalogGroupKind.season,
            metadata: season,
          ),
      ],
    ],
    titles: [
      for (final item in series)
        for (final episode in item.episodes) episodeTitleIdentity(episode),
    ],
    memberships: [
      for (final item in series) ...[
        for (var i = 0; i < item.seasons.length; i++)
          GroupMembership(
            parent: seriesGroupIdentity(item),
            child: CatalogIdentity(
              item.assets.first.collectionId,
              item.seasons[i].id,
              CatalogEntityKind.group,
            ),
            kind: MembershipKind.structural,
            order: i,
          ),
        for (final season in item.seasons)
          for (var i = 0; i < season.episodes.length; i++)
            GroupMembership(
              parent: CatalogIdentity(
                item.assets.first.collectionId,
                season.id,
                CatalogEntityKind.group,
              ),
              child: episodeTitleIdentity(season.episodes[i]),
              kind: MembershipKind.structural,
              order: i,
            ),
      ],
    ],
  );
}

/// Validates correction proposals against the complete current graph.
void validateSeriesCorrections(
  List<VideoAsset> current,
  List<VideoAsset> changes,
) {
  final byId = {
    for (final asset in current) (asset.collectionId, asset.id): asset,
  };
  final seen = <(String, String)>{};
  for (final asset in changes) {
    final key = (asset.collectionId, asset.id);
    if (!seen.add(key) || !byId.containsKey(key)) {
      throw StateError(
        'Series contents changed. Reopen the correction screen.',
      );
    }
    byId[key] = asset;
  }
  seriesGroupSnapshot(byId.values.toList());
}

class SeriesGroupRepository implements GroupRepository {
  const SeriesGroupRepository({required this.read, required this.save});
  final Future<List<VideoAsset>> Function() read;
  final Future<void> Function(List<VideoAsset>) save;

  @override
  Future<GroupSnapshot> snapshot() async => seriesGroupSnapshot(await read());

  Future<void> reorderSeries(
    CatalogIdentity parent,
    List<CatalogIdentity> children,
  ) async {
    final assets = await read();
    final matches = buildSeries(assets)
        .where((s) => seriesGroupIdentity(s) == parent);
    if (matches.length != 1) throw StateError('Series no longer exists.');
    final series = matches.single;
    final episodes = {
      for (final e in series.episodes) episodeTitleIdentity(e): e,
    };
    if (children.length != episodes.length ||
        children.toSet().length != children.length ||
        !episodes.keys.toSet().containsAll(children)) {
      throw StateError('Series contents changed. Reopen the ordering screen.');
    }
    await save([
      for (var i = 0; i < children.length; i++)
        for (final asset in episodes[children[i]]!.versions)
          VideoAsset.fromJson({
            ...asset.toJson(),
            'metadata': {...asset.metadata, 'groupOrder': '$i'},
            'metadataSource': 'manual',
          }, VideoSubtype.tv),
    ]);
  }

  @override
  Future<void> reorder(
    CatalogIdentity parent,
    List<CatalogIdentity> children,
  ) async {
    final assets = await read();
    final graph = seriesGroupSnapshot(assets);
    final order = graph.order(parent, children);
    // Season order is intrinsic (including Specials); only episodes are sortable.
    if (children.any((child) => child.kind != CatalogEntityKind.title)) {
      throw StateError('Seasons use their season numbers.');
    }
    await save([
      for (final series in buildSeries(assets))
        for (final episode in series.episodes)
          if (order.containsKey(episodeTitleIdentity(episode)))
            for (final asset in episode.versions)
              VideoAsset.fromJson({
                ...asset.toJson(),
                'metadata': {
                  ...asset.metadata,
                  'groupOrder': '${order[episodeTitleIdentity(episode)]}',
                },
                'metadataSource': 'manual',
              }, VideoSubtype.tv),
    ]);
  }
}
