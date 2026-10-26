import 'dart:async';

import '../../../core/application/clock.dart';
import '../../../library/library_models.dart';
import '../../../media/contracts.dart';
import 'source_ports.dart';

/// Application-owned scan lifetime, shared by video, cinema and audio screens.
class ScanCollections {
  ScanCollections(
    this.sources, {
    required this.clock,
    required this.collection,
    required this.authorized,
    required this.save,
    required this.reload,
    required this.changed,
  }) {
    _events = sources.progress.listen((event) {
      if (_disposed ||
          !running.contains(event.collectionId) ||
          _cancelled.contains(event.collectionId) ||
          !authorized(event.collectionId) ||
          event.requestId != _requests[event.collectionId]) {
        return;
      }
      progress[event.collectionId] = event.toLegacyMap();
      changed();
    });
  }
  final CollectionSources sources;
  final Clock clock;
  final VideoCollection? Function(String) collection;
  final bool Function(String) authorized;
  final Future<void> Function(VideoCollection) save;
  final Future<void> Function() reload;
  final void Function() changed;
  late final StreamSubscription<ScanProgressEvent> _events;
  final running = <String>{};
  final progress = <String, Map<String, dynamic>>{};
  final warnings = <String, List<String>>{};
  final _requests = <String, String>{};
  final _cancelled = <String>{};
  static int _sequence = 0;
  bool _disposed = false;
  bool _allowed(String id) =>
      !_disposed && collection(id) != null && authorized(id);
  Future<void> cancel(String id) async {
    _cancelled.add(id);
    await sources.cancel(id);
  }

  void revokeInaccessible() {
    for (final id in running.toList()) {
      if (!_allowed(id)) unawaited(cancel(id).catchError((Object _) {}));
    }
    warnings.removeWhere((id, _) => !_allowed(id));
    progress.removeWhere((id, _) => !_allowed(id));
  }

  Future<void> scan(String id) async {
    if (!_allowed(id)) throw StateError('Collection access is required.');
    if (!running.add(id)) return;
    _cancelled.remove(id);
    final request = '${clock.now().microsecondsSinceEpoch}-${++_sequence}';
    _requests[id] = request;
    progress[id] = {'found': 0, 'folder': ''};
    changed();
    bool cancelled() =>
        _disposed || _requests[id] != request || _cancelled.contains(id);
    try {
      final owner = collection(id)!;
      final result = await sources.scan(
        owner,
        requestId: request,
        authorized: () => _allowed(id),
        cancelled: cancelled,
      );
      if (cancelled() || !_allowed(id)) return;
      if (owner.kind == MediaKind.music) {
        final latest = collection(id)!;
        await save(
          VideoCollection.fromJson({
            ...latest.toJson(),
            'lastScanAt': clock.now().millisecondsSinceEpoch,
            'rootHealth': {
              for (final root in latest.roots) root.uri: 'Available',
            },
          }),
        );
      }
      if (cancelled() || !_allowed(id)) return;
      warnings[id] = List.unmodifiable(result);
      await reload();
    } finally {
      if (_requests[id] == request) {
        _requests.remove(id);
        running.remove(id);
        _cancelled.remove(id);
      }
      if (!_disposed) changed();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in running.toList()) {
      unawaited(cancel(id).catchError((Object _) {}));
    }
    _requests.clear();
    running.clear();
    unawaited(_events.cancel());
  }
}
