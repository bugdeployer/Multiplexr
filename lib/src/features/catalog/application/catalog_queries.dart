import '../../../library/library_models.dart';
import '../../../catalog/domain/classification.dart';
import '../../../media/video_projections.dart';
import 'space_queries.dart';

class CatalogQueries {
  CatalogQueries({
    required this.collections,
    required this.assets,
    required this.authorized,
  });
  final List<VideoCollection> Function() collections;
  final List<VideoAsset> Function() assets;
  final bool Function(String) authorized;
  List<VideoCollection> scoped(MediaSubtype subtype, {String? collectionId}) {
    final scope = SpaceScope(subtype, collectionId: collectionId);
    return collections()
        .where(
          (c) =>
              scope.includes(c.catalogCollection, authorized: authorized(c.id)),
        )
        .toList();
  }

  List<VideoAsset>? _indexedSource;
  final _byCollection = <String, List<VideoAsset>>{};
  List<VideoAsset> items(String id) => authorized(id) ? indexed(id) : [];
  List<VideoAsset> indexed(String id) {
    final owner = collections().where((c) => c.id == id).firstOrNull;
    if (owner == null) return [];
    final current = assets();
    if (!identical(current, _indexedSource)) {
      _indexedSource = current;
      _byCollection.clear();
      for (final asset in current) {
        (_byCollection[asset.collectionId] ??= []).add(asset);
      }
    }
    return (_byCollection[id] ?? const <VideoAsset>[])
        .where(
          (a) => owner.extensions.contains(
            a.filename.split('.').last.toLowerCase(),
          ),
        )
        .toList();
  }
}
