import 'dart:async';

/// Framework-independent job projection subscriptions. Flutter adapters only
/// declare Listenable; job execution and state do not depend on ChangeNotifier.
class JobNotifications {
  final _listeners = <void Function()>[];
  bool _notificationsDisposed = false;
  bool _notifying = false;
  void addListener(void Function() listener) {
    if (_notificationsDisposed) throw StateError('Job was disposed');
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
  void notifyListeners() {
    if (_notificationsDisposed || _notifying) return;
    _notifying = true;
    try {
      for (final listener in List.of(_listeners)) {
        if (!_listeners.contains(listener)) continue;
        try {
          listener();
        } catch (error, stack) {
          Zone.current.handleUncaughtError(error, stack);
        }
      }
    } finally {
      _notifying = false;
    }
  }

  void dispose() {
    _notificationsDisposed = true;
    _listeners.clear();
  }
}
