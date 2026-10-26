import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/settings/application/user_preferences.dart';

import 'package:app_shell/app_shell.dart';

import 'navigation_origin.dart';

/// Local UI state only: excluded from backups and never grants collection access.
/// Hosts retain their existing query/filter controllers and navigation routes.
class BrowseMemory with WidgetsBindingObserver {
  BrowseMemory({
    required this.preferences,
    required this.capture,
    required this.apply,
    required this.alive,
    required this.query,
    required this.scroll,
    required this.defaults,
    this.onReset,
    this.contentReady,
  }) {
    _initial = jsonEncode(capture().toJson());
    query.addListener(changed);
    scroll.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
  }
  final Future<void> Function()? onReset;
  final bool Function()? contentReady;
  final UserPreferences preferences;
  final NavigationOrigin Function() capture, defaults;
  final ValueChanged<NavigationOrigin> apply;
  final bool Function() alive;
  final TextEditingController query;
  final ScrollController scroll;
  late String _initial;
  String? _saved;
  Timer? _timer;
  bool _ready = false, _disposed = false, _edited = false, _applying = false;
  bool _started = false;
  double? _offset;
  Future<void> restore() async {
    _started = true;
    _initial = jsonEncode(capture().toJson());
    try {
      final data = await preferences.browsing(
        capture().routeId,
        capture().collectionId,
      );
      if (_disposed || !alive()) return;
      // A slow disk read must not undo something the user just typed.
      if (!_edited && data != null) {
        final defaultTab = defaults().tab;
        final origin = NavigationOrigin.fromJson({
          ...data,
          if (data['defaultTab'] is int && data['defaultTab'] != defaultTab)
            'tab': defaultTab,
        });
        final current = capture();
        if (origin.routeId == current.routeId &&
            origin.collectionId == current.collectionId) {
          _applying = true;
          query.text = origin.query;
          apply(origin);
          _offset = origin.scrollOffset;
          _applying = false;
          _saved = jsonEncode(origin.toJson());
        }
      }
    } catch (_) {
      // Invalid or unavailable UI state never blocks the underlying collection.
    } finally {
      _applying = false;
      if (!_disposed) {
        _ready = true;
        changed();
      }
    }
  }

  /// Call from build as well: filters/tabs are host fields, not text listeners.
  void changed() {
    if (_disposed || _applying) return;
    if (!_ready) {
      if (_started && jsonEncode(capture().toJson()) != _initial) {
        _edited = true;
      }
      return;
    }
    if (_offset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !alive() || !scroll.hasClients || _offset == null) {
          return;
        }
        if (contentReady?.call() == false) return;
        final offset = _offset!;
        _offset = null;
        scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
      });
      return;
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () => unawaited(flush()));
  }

  Future<void> flush() async {
    if (!_ready || _offset != null) return;
    final snapshot = {...capture().toJson(), 'defaultTab': defaults().tab};
    final encoded = jsonEncode(snapshot);
    if (encoded == _saved) return;
    try {
      await preferences.saveBrowsing(
        capture().routeId,
        capture().collectionId,
        snapshot,
      );
      _saved = encoded;
    } catch (_) {
      /* Best-effort UI preference; media data is unaffected. */
    }
  }

  Future<void> reset() async {
    _timer?.cancel();
    _offset = null;
    _edited = true;
    await onReset?.call();
    if (_disposed || !alive()) return;
    final origin = defaults();
    _applying = true;
    query.text = origin.query;
    apply(origin);
    if (scroll.hasClients) scroll.jumpTo(0);
    _applying = false;
    _ready = true;
    _saved = null;
    await flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _timer?.cancel();
      unawaited(flush());
    }
  }

  void dispose() {
    if (_disposed) return;
    _timer?.cancel();
    unawaited(flush());
    _disposed = true;
    query.removeListener(changed);
    scroll.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
  }
}

class BrowseResetButton extends StatelessWidget {
  const BrowseResetButton({super.key, required this.memory});
  final BrowseMemory memory;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Reset browsing',
    icon: const AppIcon(AppIconRole.refresh),
    onPressed: () => confirmBrowseReset(context, memory),
  );
}

Future<void> confirmBrowseReset(
  BuildContext context,
  BrowseMemory memory,
) async {
  final reset = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Reset browsing?'),
      content: const Text(
        'Clear search and browsing filters and return to the top. Media, progress and collection settings are kept.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (reset == true && context.mounted) await memory.reset();
}
