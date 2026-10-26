import '../../../media/contracts.dart';
import '../../../library/library_models.dart';
import '../../../core/application/maintenance.dart';

abstract interface class VideoSessionStore {
  Future<void> save(VideoProgress progress);
}

/// Application policy shared by lifecycle and handoff paths. Returning to the
/// foreground never starts playback; only an explicit user/queue action may do so.
class SessionPolicy {
  const SessionPolicy();
  bool shouldPause({
    required bool authorized,
    required bool foreground,
    required bool backgroundAllowed,
    required bool pictureInPicture,
  }) => !authorized || (!foreground && !backgroundAllowed && !pictureInPicture);
  bool mayAdvance({
    required bool authorized,
    required bool foreground,
    required bool pictureInPicture,
  }) => authorized && foreground && !pictureInPicture;
}

/// Serializes progress commits so a delayed checkpoint cannot overwrite a later
/// close/completion checkpoint. Failed commits do not poison subsequent writes.
class VideoSession {
  VideoSession(
    this.id,
    this.store, {
    required this.authorized,
    this.maintenance,
  });
  final Maintenance? maintenance;
  void Function()? _detachMaintenance;
  void bindDrain(Future<void> Function() drain) {
    _detachMaintenance?.call();
    _detachMaintenance = maintenance?.register(drain: drain);
  }

  void dispose() {
    _detachMaintenance?.call();
    _detachMaintenance = null;
  }

  final MediaId id;
  final VideoSessionStore store;
  final bool Function() authorized;
  bool completionPending = false;
  bool _completed = false;
  int _lastSaved = -1;
  bool _finishing = false;

  /// Completion remains pending while hidden or access is revoked. Selection
  /// is application policy; the UI only performs navigation for the result.
  Future<VideoAsset?> finish({
    required Future<void> Function() checkpoint,
    required Future<void> Function() reload,
    required bool Function() active,
    required bool Function() foreground,
    required bool Function() pictureInPicture,
    required bool Function() autoplayNext,
    required VideoAsset? Function() queued,
    required List<VideoAsset> Function() episodeVersions,
  }) async {
    if (_finishing || !completionPending || !active()) return null;
    _finishing = true;
    try {
      await checkpoint();
      await reload();
      if (!active() ||
          !const SessionPolicy().mayAdvance(
            authorized: authorized(),
            foreground: foreground(),
            pictureInPicture: pictureInPicture(),
          )) {
        return null;
      }
      completionPending = false;
      final next = queued();
      if (next != null) return next;
      final versions = episodeVersions()
          .where((asset) => asset.available)
          .toList();
      return autoplayNext() && versions.length == 1 ? versions.single : null;
    } finally {
      _finishing = false;
    }
  }

  Future<void> handoff({
    required Future<void> Function() pause,
    required Future<void> Function() checkpoint,
    required Future<void> Function() disableBackground,
    required Future<void> Function() launch,
  }) async {
    if (!authorized()) throw StateError('Playback collection is unavailable');
    await pause();
    await checkpoint();
    await disableBackground();
    if (!authorized()) throw StateError('Playback collection is unavailable');
    await launch();
  }

  ({bool completion, bool checkpoint}) observe({
    required int positionMs,
    required int durationMs,
    required bool completed,
  }) {
    final completion = completed && !_completed;
    if (completion) completionPending = true;
    if (!completed) completionPending = false;
    _completed = completed;
    final seconds = positionMs ~/ 1000;
    final checkpoint = durationMs > 0 && (seconds - _lastSaved).abs() >= 5;
    if (checkpoint) _lastSaved = seconds;
    return (completion: completion, checkpoint: checkpoint);
  }

  Future<void> _pending = Future.value();
  Future<void> save({
    required int positionMs,
    required int durationMs,
    required bool completed,
  }) {
    final progress = VideoProgress(
      id,
      positionMs: completed ? durationMs : positionMs,
      durationMs: durationMs,
      watched: completed,
    );
    final result = _pending.then((_) async {
      if (!authorized()) throw StateError('Playback collection is unavailable');
      await store.save(progress);
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
