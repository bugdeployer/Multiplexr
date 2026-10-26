import 'dart:async';

import 'job_admission.dart';

class MaintenanceBusy implements Exception {
  const MaintenanceBusy();
  @override
  String toString() => 'Library maintenance requires idle application work.';
}

/// One admission boundary per persistence owner. Exclusive work fails fast
/// rather than waiting behind an engine/job whose completion needs the UI.
class Maintenance {
  Maintenance({this.queryDrainTimeout = const Duration(seconds: 2)});
  final Duration queryDrainTimeout;
  int _queries = 0;
  Completer<void>? _queriesIdle;

  /// Bounded native snapshot reads may finish after authentication resumes.
  /// Restore closes admission, invalidates their consumers, then drains them.
  Future<T> query<T>(Future<T> Function() operation) async {
    checkAdmission();
    if (_queries++ == 0) _queriesIdle = Completer<void>();
    try {
      return await operation();
    } finally {
      if (--_queries == 0) {
        _queriesIdle?.complete();
        _queriesIdle = null;
      }
    }
  }

  final jobs = JobAdmission();
  static final _owners = Expando<Maintenance>();
  static Maintenance forOwner(Object owner) => _owners[owner] ??= Maintenance();

  final Object _zoneKey = Object();
  int _active = 0;
  Object? _exclusive;
  int _generation = 0;
  int get generation => _generation;
  final _invalidations = <Object, void Function()>{};
  final _drains = <Object, Future<void> Function()>{};

  /// Invalidations run synchronously before any asynchronous session drain.
  /// A failed drain aborts maintenance; the old generation stays revoked.
  void Function() register({
    void Function()? invalidate,
    Future<void> Function()? drain,
  }) {
    checkAdmission();
    final key = Object();
    if (invalidate != null) _invalidations[key] = invalidate;
    if (drain != null) _drains[key] = drain;
    return () {
      _invalidations.remove(key);
      _drains.remove(key);
    };
  }

  bool isCurrent(int generation) =>
      generation == _generation && (!exclusive || _ownsExclusive);
  bool get exclusive => _exclusive != null;
  bool get active => _active != 0;
  bool get _ownsExclusive =>
      _exclusive != null && identical(Zone.current[_zoneKey], _exclusive);

  void checkAdmission() {
    if (exclusive && !_ownsExclusive) throw const MaintenanceBusy();
  }

  Future<T> activity<T>(Future<T> Function() operation) async {
    checkAdmission();
    _active++;
    try {
      return await operation();
    } finally {
      _active--;
    }
  }

  Future<T> exclusively<T>(Future<T> Function() operation) async {
    if (exclusive || active) throw const MaintenanceBusy();
    final token = Object();
    _exclusive = token;
    try {
      return await runZoned(() async {
        _generation++;
        final invalidations = List.of(_invalidations.values);
        final drains = List.of(_drains.values);
        Object? failure;
        StackTrace? failureStack;
        for (final invalidate in invalidations) {
          try {
            invalidate();
          } catch (error, stack) {
            failure ??= error;
            failureStack ??= stack;
          }
        }
        // Do not restore after even one native resource failed to drain.
        // Await every drain so one failure cannot strand later participants.
        try {
          await Future.wait(drains.map((drain) => Future.sync(drain)));
        } catch (error, stack) {
          failure ??= error;
          failureStack ??= stack;
        }
        if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
        try {
          await _queriesIdle?.future.timeout(queryDrainTimeout);
        } on TimeoutException {
          throw const MaintenanceBusy();
        }
        return await operation();
      }, zoneValues: {_zoneKey: token});
    } finally {
      _exclusive = null;
    }
  }
}
