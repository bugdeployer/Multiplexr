import '../../../catalog/domain/classification.dart';

abstract interface class CollectionJob {
  bool get running;
  int get done;
  int get total;
  void cancel();
  void dispose();
}

/// Presentation state independent of subtype widgets and persisted wire formats.
class CollectionController<T, K> {
  CollectionController({required this.identity});
  final K Function(T) identity;
  List<T> _items = const [];
  List<T> get items => List.unmodifiable(_items);
  String query = '', folder = '', tag = '', filter = 'all', sort = 'title';
  CatalogLayout layout = CatalogLayout.grid;
  bool selecting = false, loading = false, descending = false;
  String? error;
  final Set<K> selected = {};
  int _generation = 0;
  bool _disposed = false;
  final List<CollectionJob> _jobs = [];
  List<CollectionJob> get jobs => List.unmodifiable(_jobs);
  J ownJob<J extends CollectionJob>(J job) {
    if (_disposed) throw StateError('Collection controller was disposed.');
    if (!_jobs.any((current) => identical(current, job))) _jobs.add(job);
    return job;
  }

  void replace(Iterable<T> values) {
    _items = List.of(values);
    selected.retainAll(_items.map(identity).toSet());
  }

  void toggle(T item) {
    final key = identity(item);
    if (!selected.add(key)) selected.remove(key);
  }

  void endSelection() {
    selecting = false;
    selected.clear();
  }

  List<T> browse({
    required bool Function(T) matches,
    int Function(T, T)? compare,
  }) {
    final result = _items.where(matches).toList();
    if (compare != null) result.sort(compare);
    return descending ? result.reversed.toList() : result;
  }

  /// Late loads cannot replace a newer query/refresh or resurrect disposed state.
  Future<bool> load(
    Future<List<T>> Function() read, {
    required String failure,
  }) async {
    if (_disposed) return false;
    final generation = ++_generation;
    loading = true;
    try {
      final result = await read();
      if (_disposed || generation != _generation) return false;
      replace(result);
      error = null;
      return true;
    } catch (_) {
      if (!_disposed && generation == _generation) error = failure;
      return false;
    } finally {
      if (!_disposed && generation == _generation) loading = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    loading = false;
    _generation++;
    for (final job in _jobs) {
      job.cancel();
      job.dispose();
    }
    _jobs.clear();
  }
}
