import 'dart:async';

import 'plugin_failure.dart';

class _Invocation {
  _Invocation(this.plugin, this.background, this.expires, this.action);
  final String plugin;
  final bool background;
  final DateTime expires;
  final Future<Object?> Function() action;
  final result = Completer<Object?>();
}

/// One interpreter at a time, bounded waiting, user work before automation.
class PluginScheduler {
  PluginScheduler(this.now);
  final DateTime Function() now;
  final _pending = <_Invocation>[];
  bool _active = false;
  Future<Object?> run(
    String plugin,
    Future<Object?> Function() action, {
    bool background = false,
  }) {
    if (_pending.length >= 16) {
      return Future.error(const PluginDenied('resource_limit'));
    }
    final request = _Invocation(
      plugin,
      background,
      now().add(const Duration(seconds: 30)),
      action,
    );
    _pending.add(request);
    _drain();
    return request.result.future;
  }

  void revoke([String? plugin]) {
    for (final request
        in _pending
            .where((q) => plugin == null || q.plugin == plugin)
            .toList()) {
      _pending.remove(request);
      request.result.completeError(const PluginDenied('cancelled'));
    }
  }

  Future<void> _drain() async {
    if (_active) {
      return;
    }
    _active = true;
    try {
      while (_pending.isNotEmpty) {
        final request =
            _pending.where((q) => !q.background).firstOrNull ?? _pending.first;
        _pending.remove(request);
        if (!now().isBefore(request.expires)) {
          request.result.completeError(const PluginDenied('deadline_exceeded'));
          continue;
        }
        try {
          request.result.complete(await request.action());
        } catch (error, stack) {
          request.result.completeError(error, stack);
        }
      }
    } finally {
      _active = false;
    }
  }
}
