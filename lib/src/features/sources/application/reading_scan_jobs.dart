import '../../../core/application/maintenance.dart';

import 'dart:async';

import 'reading_scan_workflow.dart';

/// Automatic indexing is host-owned; manual repair previews remain explicit.
class ReadingScanJobs {
  ReadingScanJobs(
    this.create, {
    required this.authorized,
    required this.changed,
    this.maintenance,
  });
  final Maintenance? maintenance;
  final ReadingScanTask Function() create;
  final bool Function(String) authorized;
  final void Function() changed;
  final _tasks = <String, ReadingScanTask>{};
  final _work = <String, Future<bool>>{};
  final _cancelled = <String>{};
  bool _disposed = false;
  Set<String> get running => Set.unmodifiable(_work.keys);
  Future<bool> run(String id) => maintenance == null
      ? _admit(id)
      : maintenance!.activity(
          () => maintenance!.jobs.run(
            'scan:reading:$id',
            [id],
            () => _admit(id),
            cancelled: () => _cancelled.contains(id),
          ),
        );

  Future<bool> _admit(String id) {
    if (_disposed) throw StateError('Reading scans were disposed');
    if (_work[id] case final pending?) return pending;
    if (!authorized(id)) throw StateError('Reading collection is unavailable');
    final task = create();
    _tasks[id] = task;
    _cancelled.remove(id);
    final pending = Future<bool>.microtask(() => _run(id, task));
    _work[id] = pending;
    changed();
    return pending;
  }

  Future<bool> _run(String id, ReadingScanTask task) async {
    try {
      if (_disposed || _cancelled.contains(id) || !authorized(id)) {
        throw StateError('Reading scan cancelled');
      }
      final preview = await task.preview(id);
      if (_disposed || _cancelled.contains(id) || !authorized(id)) {
        throw StateError('Reading scan cancelled');
      }
      if (!preview.canApply) return false;
      await task.apply(id, preview);
      return true;
    } finally {
      _work.remove(id);
      _tasks.remove(id);
      if (!_disposed) changed();
    }
  }

  Future<void> cancel(String id) async {
    if (!_cancelled.add(id)) return;
    await _tasks[id]?.cancel();
  }

  void refreshAccess() {
    for (final id in running) {
      if (!authorized(id)) unawaited(cancel(id).catchError((Object _) {}));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in running) {
      unawaited(cancel(id).catchError((Object _) {}));
    }
  }
}
