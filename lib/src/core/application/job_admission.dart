import 'dart:async';

enum JobOutcome { running, completed, cancelled, failed, interrupted }

class JobReceipt {
  JobReceipt(this.key, Iterable<String> collections, this.outcome)
    : collections = List.unmodifiable(collections) {
    if (key.isEmpty ||
        key.length > 512 ||
        this.collections.length > 1000 ||
        this.collections.toSet().length != this.collections.length ||
        this.collections.any((id) => id.isEmpty || id.length > 2048)) {
      throw const FormatException('Invalid job receipt');
    }
  }
  final String key;

  /// Empty means library-wide work, which conflicts with every collection.
  final List<String> collections;
  final JobOutcome outcome;
}

abstract interface class JobReceiptStore {
  Future<List<JobReceipt>> read();
  Future<void> write(List<JobReceipt> receipts);
}

class JobAdmissionBusy implements Exception {
  const JobAdmissionBusy();
  @override
  String toString() =>
      'Another job is using this collection. Retry after it finishes.';
}

/// One admission/status ledger per maintenance owner, shared by scans and every
/// metadata family. Recovery marks interrupted work; it never replays commands.
class JobAdmission {
  final _active =
      <String, ({List<String> collections, Future<Object?> work})>{};
  final _receipts = <String, JobReceipt>{};
  JobReceiptStore? _store;
  Future<void>? _ready;
  Future<void> _saving = Future.value();
  bool get running => _active.isNotEmpty;

  void configure(JobReceiptStore store) {
    if (_store != null) {
      return; // A second facade cannot replace the owner's ledger.
    }
    if (running) {
      throw StateError('Configure job persistence before admitting work');
    }
    _store = store;
  }

  Future<void> _ensureReady() {
    if (_store == null) return Future.value();
    if (_ready != null) return _ready!;
    late final Future<void> pending;
    pending = _recover(_store!).catchError((Object error, StackTrace stack) {
      if (identical(_ready, pending)) _ready = null;
      Error.throwWithStackTrace(error, stack);
    });
    _ready = pending;
    return pending;
  }

  Future<void> _recover(JobReceiptStore store) async {
    for (final receipt in await store.read()) {
      _receipts[receipt.key] = JobReceipt(
        receipt.key,
        receipt.collections,
        receipt.outcome == JobOutcome.running
            ? JobOutcome.interrupted
            : receipt.outcome,
      );
    }
    await _save();
  }

  Future<List<JobReceipt>> status(bool Function(String) authorized) async {
    await _ensureReady();
    return List.unmodifiable(
      _receipts.values.where(
        (receipt) =>
            receipt.collections.isNotEmpty &&
            receipt.collections.every(authorized),
      ),
    );
  }

  Future<T> run<T>(
    String key,
    Iterable<String> collections,
    Future<T> Function() operation, {
    bool Function()? cancelled,
    T Function()? cancelledResult,
    void Function()? admitted,
  }) {
    final scopes = collections.toSet().toList()..sort();
    if (key.isEmpty || key.length > 512 || scopes.any((id) => id.isEmpty)) {
      throw ArgumentError('Invalid job identity');
    }
    JobReceipt(
      key,
      scopes,
      JobOutcome.running,
    ); // Validate before reserving scope.
    final previous = _active[key];
    if (previous != null) {
      if (previous.collections.length != scopes.length ||
          !previous.collections.every(scopes.contains)) {
        throw ArgumentError('Job identity belongs to another scope');
      }
      return previous.work.then((value) => value as T);
    }
    if (_active.values.any(
      (other) =>
          scopes.isEmpty ||
          other.collections.isEmpty ||
          other.collections.any(scopes.contains),
    )) {
      return Future.error(const JobAdmissionBusy());
    }
    final result = Completer<T>();
    _active[key] = (collections: scopes, work: result.future);
    try {
      admitted?.call();
    } catch (_) {
      _active.remove(key);
      rethrow;
    }
    unawaited(() async {
      try {
        await _ensureReady();
        _receipts[key] = JobReceipt(key, scopes, JobOutcome.running);
        await _save(); // No side effects before durable admission succeeds.
        final value = cancelled?.call() == true && cancelledResult != null
            ? cancelledResult()
            : await operation();
        _receipts[key] = JobReceipt(
          key,
          scopes,
          cancelled?.call() == true
              ? JobOutcome.cancelled
              : JobOutcome.completed,
        );
        await _save();
        result.complete(value);
      } catch (error, stack) {
        _receipts[key] = JobReceipt(
          key,
          scopes,
          cancelled?.call() == true ? JobOutcome.cancelled : JobOutcome.failed,
        );
        try {
          await _save();
        } catch (_) {
          /* Original failure remains actionable. */
        }
        result.completeError(error, stack);
      } finally {
        _active.remove(key);
      }
    }());
    return result.future;
  }

  Future<void> _save() {
    final store = _store;
    if (store == null) return Future.value();
    // Bounded history, always retaining live receipts.
    final finished = _receipts.values
        .where((r) => !_active.containsKey(r.key))
        .toList();
    for (final old in finished.take(
      (finished.length - 100).clamp(0, finished.length),
    )) {
      _receipts.remove(old.key);
    }
    final snapshot = List<JobReceipt>.unmodifiable(_receipts.values);
    final work = _saving.then((_) => store.write(snapshot));
    _saving = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work;
  }
}
