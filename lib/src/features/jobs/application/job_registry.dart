import '../../catalog/application/collection_presenter.dart' show CollectionJob;
import '../../../core/application/maintenance.dart';

abstract interface class PreparingJob {
  bool get preparing;
}

/// Host-owned jobs outlive route subscribers. Keys identify one runner per scope;
/// durable journals remain in existing adapters and are never auto-started here.
class ApplicationJobs {
  ApplicationJobs({this.maintenance});
  final Maintenance? maintenance;
  final _jobs = <String, CollectionJob>{};
  final _access = <String, bool Function()>{};
  final _revoked = <String>{};
  bool _disposed = false;
  T obtain<T extends CollectionJob>(
    String key,
    T Function() create, {
    required bool Function() authorized,
  }) {
    if (_disposed) throw StateError('Application jobs were disposed');
    maintenance?.checkAdmission();
    _access[key] = authorized;
    final existing = _jobs[key];
    if (existing != null) {
      if (existing is! T) throw StateError('Job key belongs to another kind');
      return existing;
    }
    final job = create();
    _jobs[key] = job;
    return job;
  }

  bool get running => _jobs.values.any(
    (job) =>
        job.running || job is PreparingJob && (job as PreparingJob).preparing,
  );
  List<CollectionJob> get visible => List.unmodifiable([
    for (final entry in _jobs.entries)
      if (_access[entry.key]!()) entry.value,
  ]);
  void refreshAccess() {
    for (final entry in _jobs.entries) {
      if (_access[entry.key]!()) {
        _revoked.remove(entry.key);
      } else if (_revoked.add(entry.key)) {
        entry.value.cancel();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _jobs.values) {
      job.cancel();
      job.dispose();
    }
    _jobs.clear();
    _access.clear();
    _revoked.clear();
  }
}
