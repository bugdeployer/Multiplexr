import '../../../library/library_models.dart';
import '../../../library/series.dart' show withSelectedArtwork;
import '../../../core/application/maintenance.dart';

abstract interface class VideoArtworkPort {
  Future<List<String>> candidates(VideoAsset asset, String kind);
  Future<void> apply(VideoAsset before, VideoAsset after, Set<String> fields);
}

class VideoArtwork {
  VideoArtwork(
    this.port, {
    required this.maintenance,
    required this.authorized,
    required this.items,
    required this.reload,
  });
  final VideoArtworkPort port;
  final Maintenance maintenance;
  final bool Function(String) authorized;
  final List<VideoAsset> Function(String) items;
  final Future<void> Function() reload;
  void _access(String id) {
    if (!authorized(id)) throw StateError('Collection access is required.');
  }

  Future<List<String>> candidates(VideoAsset asset, String kind) async {
    _access(asset.collectionId);
    final result = await port.candidates(asset, kind);
    _access(asset.collectionId);
    return result;
  }

  Future<void> select(
    Iterable<VideoAsset> targets,
    String kind,
    String location, {
    required bool series,
    required bool Function() cancelled,
  }) => maintenance.activity(() async {
    for (final target in targets) {
      if (cancelled()) return;
      _access(target.collectionId);
      final latest = items(target.collectionId)
          .where((a) => a.id == target.id)
          .firstOrNull;
      if (latest == null) continue;
      final updated = withSelectedArtwork(
        latest,
        kind,
        location,
        series: series,
      );
      final fields = <String>{
        for (final e in updated.metadata.entries)
          if (e.value != latest.metadata[e.key]) e.key,
        for (final key in ['poster', 'backdrop', 'seriesBackdrop'])
          if (updated.toJson()[key] != latest.toJson()[key]) key,
      };
      await port.apply(latest, updated, fields);
    }
    await reload();
  });
}
