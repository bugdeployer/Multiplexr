import '../../../library/library_models.dart';

/// Existing wire snapshot decoded once at the repository boundary.
class LibrarySnapshot {
  LibrarySnapshot({
    required Iterable<VideoCollection> collections,
    required Iterable<VideoAsset> assets,
    required Map<String, int> audioCounts,
    required Iterable<String>? queue,
    required this.seriesIndexSupported,
  }) : collections = List.unmodifiable(collections),
       assets = List.unmodifiable(assets),
       audioCounts = Map.unmodifiable(audioCounts),
       queue = queue == null ? null : List.unmodifiable(queue);
  final List<VideoCollection> collections;
  final List<VideoAsset> assets;
  final Map<String, int> audioCounts;

  /// Null means the legacy adapter did not supply queue state.
  final List<String>? queue;
  final bool seriesIndexSupported;
}

abstract interface class LibraryRepository {
  Future<LibrarySnapshot> load();
  Future<void> saveCollection(VideoCollection collection);
  Future<void> removeCollection(String id);
  Future<void> saveBrowsing(String id, Map<String, dynamic> values);
  Future<void> editTags(
    List<VideoAsset> assets, {
    required String operation,
    required List<String> tags,
    String? target,
    String? collectionId,
  });
  Future<void> saveAsset(VideoAsset asset);
  Future<void> saveGrouping(List<VideoAsset> assets);
  Future<void> updateFlags(List<VideoAsset> assets, String action, bool value);
  Future<void> watchState(VideoAsset asset, String action);
  Future<void> saveQueue(List<String> queue);
  Future<List<String>> editQueue(
    void Function(List<String>) edit, {
    List<String> fallback = const [],
  });
  Future<void> saveSeriesIndex(Map<String, dynamic> index);
  Future<List<String>> scan(String id, {String? requestId});
}
