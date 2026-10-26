import '../../../library/library_models.dart';

/// A read-only projection of existing scan state and durable metadata journals.
/// It never creates another runner or takes ownership from collection screens.
class CollectionJobStatus {
  const CollectionJobStatus(
    this.collection,
    this.summary, {
    this.metadata = false,
    this.remaining = 0,
  });
  final VideoCollection collection;
  final String summary;
  final bool metadata;
  final int remaining;
}

abstract interface class ActivitySource {
  Future<Map<String, dynamic>?> journal(VideoCollection collection);
  Future<Set<String>> eligibleAudioIds(VideoCollection collection);
}

class ActivityQueries {
  const ActivityQueries(
    this.source, {
    required this.collections,
    required this.authorized,
    required this.scanning,
    required this.found,
    required this.indexed,
  });
  final ActivitySource source;
  final List<VideoCollection> Function() collections;
  final bool Function(String) authorized, scanning;
  final Object? Function(String) found;
  final List<VideoAsset> Function(String) indexed;
  Future<List<CollectionJobStatus>> read() async {
    final result = <CollectionJobStatus>[];
    for (final collection in List.of(collections())) {
      if (!authorized(collection.id)) continue;
      if (scanning(collection.id)) {
        final found = this.found(collection.id);
        result.add(
          CollectionJobStatus(
            collection,
            found is int ? 'Scanning · $found found' : 'Scanning',
          ),
        );
      }
      final state = await source.journal(collection);
      if (!authorized(collection.id) ||
          !collections().any((c) => c.id == collection.id)) {
        continue;
      }
      if (state == null) continue;
      final remaining = state['remaining'] is List
          ? (state['remaining'] as List).length
          : 0;
      var review = 0, failed = 0;
      if (collection.isAudio && state['entries'] is Map) {
        final ids = await source.eligibleAudioIds(collection);
        for (final item in (state['entries'] as Map).entries) {
          if (!ids.contains(item.key) || item.value is! Map) continue;
          final entry = item.value as Map;
          if (entry['status'] == 'review') review++;
          if (entry['status'] == 'failed') failed++;
        }
      } else if (!collection.isAudio) {
        // Journal totals describe the finished batch, not outstanding reviews.
        // Manual reviews can resolve those records after the job checkpoint.
        final items = indexed(collection.id);
        review = items.where((a) => a.metadataStatus == 'review').length;
        failed = items.where((a) => a.metadataStatus == 'failed').length;
      }
      if (!authorized(collection.id)) continue;
      if (remaining > 0 || review > 0 || failed > 0) {
        result.add(
          CollectionJobStatus(
            collection,
            'Metadata · $remaining remaining · $review to review · $failed failed${state['pausedReason'] == null ? '' : ' · Paused: ${state['pausedReason']}'}',
            metadata: true,
            remaining: remaining,
          ),
        );
      }
    }
    return result
        .where(
          (status) =>
              authorized(status.collection.id) &&
              collections().any((c) => c.id == status.collection.id),
        )
        .toList();
  }
}
