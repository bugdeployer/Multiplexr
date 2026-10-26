import 'dart:async';

import '../../../media/audio_models.dart';
import '../../../media/audio_session.dart';
import '../../../media/contracts.dart';
import 'audio_playback_models.dart';
import 'audio_commands.dart';
export 'audio_commands.dart';

class AudioSnapshot {
  const AudioSnapshot(this.state, this.token);
  final AudioState state;
  final Object token;
}

abstract interface class AudioEnginePort {
  Future<void> open(AudioPlaybackRequest request, {required bool autoplay});
  Future<AudioSnapshot?> read();
  Future<void> execute(AudioCommand command);
}

/// Owns open/restore/observation races above the native engine. Attaching only
/// observes; foregrounding and process restoration never implicitly play.
mixin AudioSessionApplication {
  AudioEnginePort get engine;
  void notifyListeners();
  AudioState state = const AudioState();
  Timer? _poll;
  Future<void>? _reading;
  int _readingRevision = -1;
  Object? _lastRaw;
  bool _disposed = false;
  int _sessionRevision = 0;
  Future<void> openBook(
    Audiobook book,
    MediaProgressStore storage, {
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    final revision = ++_sessionRevision;
    final progress = await storage.read(book.id);
    if (_disposed || revision != _sessionRevision) return;
    await _openRequest(
      AudioPlaybackRequest.audiobook(book, progress as AudiobookProgress?),
      revision,
      autoplay: autoplay,
    );
  }

  Future<void> openMusic(
    AudioSession session, {
    String? collectionId,
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    final revision = ++_sessionRevision;
    await _openRequest(
      AudioPlaybackRequest.music(session, collectionId: collectionId),
      revision,
      autoplay: autoplay,
    );
  }

  Future<void> _openRequest(
    AudioPlaybackRequest request,
    int revision, {
    required bool autoplay,
  }) async {
    _lastRaw = null;
    await engine.open(request, autoplay: autoplay);
    if (_disposed || revision != _sessionRevision) return;
    await refresh();
    if (!_disposed && revision == _sessionRevision) {
      observe();
    }
  }

  /// Observe an already running service without starting or resuming playback.
  void observe() {
    final revision = _sessionRevision;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed || revision != _sessionRevision) return;
      refresh().catchError((Object error) {
        if (!_disposed && revision == _sessionRevision) {
          _lastRaw = null;
          state = AudioState({
            ...state.data,
            'error': 'Could not read audio playback status.',
          });
          notifyListeners();
        }
      });
    });
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    if (_reading != null && _readingRevision == _sessionRevision) {
      return _reading!;
    }
    _readingRevision = _sessionRevision;
    late final Future<void> reading;
    reading = _read().whenComplete(() {
      if (identical(_reading, reading)) _reading = null;
    });
    _reading = reading;
    return reading;
  }

  Future<void> _read() async {
    final revision = _sessionRevision;
    final raw = await engine.read();
    if (!_disposed &&
        revision == _sessionRevision &&
        raw != null &&
        raw.token != _lastRaw) {
      _lastRaw = raw.token;
      state = raw.state;
      notifyListeners();
    }
  }

  Future<void> execute(AudioCommand command) async {
    if (_disposed) return;
    command.validate();
    final revision = _sessionRevision;
    await engine.execute(command);
    if (_disposed || revision != _sessionRevision) return;
    if (_readingRevision == revision) await _reading;
    if (_disposed || revision != _sessionRevision) return;
    await refresh();
  }

  void disposeSession() {
    _disposed = true;
    _sessionRevision++;
    _poll?.cancel();
  }

  /// Revoke delayed opens/observations before native state is replaced.
  void invalidateSession() {
    _sessionRevision++;
    _poll?.cancel();
    _lastRaw = null;
    state = const AudioState();
    if (!_disposed) notifyListeners();
  }
}
