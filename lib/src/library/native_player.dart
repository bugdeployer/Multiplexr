import '../features/playback/application/video_engine.dart';
export '../features/playback/application/video_engine.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin, injectable state bridge to the in-app Android Media3 surface.
class Player extends ChangeNotifier implements VideoEngine {
  MethodChannel? _channel;
  Timer? _timer;
  bool _disposed = false;
  Future<void>? _refreshing;
  @override
  PlaybackState state = PlaybackState();
  @override
  Future<void> attach(int id) async {
    if (_disposed) return;
    _timer?.cancel();
    _channel = MethodChannel('multiplexr/player/$id');
    await refresh();
    if (_disposed) return;
    _timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => refresh(),
    );
  }

  @override
  Future<void> refresh() {
    if (_disposed || _channel == null) return Future.value();
    return _refreshing ??= _readState().whenComplete(() => _refreshing = null);
  }

  Future<void> _readState() async {
    try {
      final data = await _channel!.invokeMapMethod('state');
      if (!_disposed && data != null) {
        state = PlaybackState(data);
        notifyListeners();
      }
    } on PlatformException {
      /* Surface disposal can race a final status read. */
    } on MissingPluginException {
      /* Platform view has already closed. */
    }
  }

  Future<void> _call(String name, [dynamic value]) async {
    if (_channel == null || _disposed) return;
    await _channel!.invokeMethod(name, value);
    // A status read begun before the command may contain the previous value.
    await _refreshing;
    await refresh();
  }

  @override
  Future<void> pause() => _call('pause');
  @override
  Future<void> playOrPause() => _call('playPause');
  @override
  Future<void> seek(Duration value) => _call('seek', value.inMilliseconds);
  @override
  Future<void> setRate(double value) => _call('rate', value);
  @override
  Future<void> setVolume(double value) => _call('volume', value);
  @override
  Future<void> setRepeat(bool value) => _call('repeat', value);
  @override
  Future<void> setAutoPip(bool value) => _call('autoPip', value);
  @override
  Future<void> setBackground(bool value) => _call('background', value);
  @override
  Future<void> setFit(String value) => _call('fit', value);
  @override
  Future<void> setSubtitleStyle(double scale, bool background) =>
      _call('subtitleStyle', {'scale': scale, 'background': background});
  @override
  Future<void> controlsVisible(bool value) => _call('controlsVisible', value);
  @override
  Future<void> addSubtitle() => _call('addSubtitle');
  @override
  Future<void> removeSubtitle() => _call('removeSubtitle');
  @override
  Future<void> resetPreferences() => _call('resetPreferences');
  @override
  Future<void> retry() => _call('retry');
  @override
  Future<void> setAudioTrack(PlaybackTrack value) => _call('audio', value.id);
  @override
  Future<void> setSubtitleTrack(PlaybackTrack value) =>
      _call('subtitle', value.id);
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _channel?.invokeMethod<void>('dispose').catchError((Object _) {});
    super.dispose();
  }
}

class PlaybackWindow extends ChangeNotifier implements VideoWindow {
  PlaybackWindow._() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        active = call.arguments == true;
        if (active) backgrounded = false;
        notifyListeners();
      } else if (call.method == 'pipBackgrounded') {
        backgrounded = call.arguments == true;
        if (backgrounded) active = false;
        notifyListeners();
      }
    });
  }
  static final instance = PlaybackWindow._();
  static const channel = MethodChannel('multiplexr/playback');
  @override
  bool active = false;
  @override
  bool backgrounded = false;
  Future<void> enter(Map<String, double> bounds) async {
    active = true;
    notifyListeners();
    try {
      if (await channel.invokeMethod<bool>('enterPip', bounds) != true) {
        throw StateError('Android did not allow picture-in-picture.');
      }
    } catch (_) {
      active = false;
      notifyListeners();
      rethrow;
    }
  }
}
