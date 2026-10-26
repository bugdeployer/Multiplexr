import 'dart:convert';

import 'platform_transport.dart';
import '../../features/playback/application/audio_session_controller.dart';
import '../../features/playback/application/audio_playback_models.dart';
import '../../media/audio_models.dart';

class NativeAudioEngine implements AudioEnginePort {
  const NativeAudioEngine(this.transport);
  final PlatformTransport transport;
  Future<AudioImport?> pickFiles() async {
    final raw = await transport.invokeMethod<String>('pickFiles');
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map;
    return AudioImport(
      orderedAudioFiles(
        (data['files'] as List).map(
          (f) => AudioFile.fromJson(Map<String, dynamic>.from(f)),
        ),
      ),
      List<String>.from(data['errors']),
    );
  }

  Future<void> releaseUnusedFiles(List<AudioFile> files) => transport
      .invokeMethod('releaseUnusedFiles', files.map((f) => f.uri).toList());

  @override
  Future<void> open(AudioPlaybackRequest request, {required bool autoplay}) =>
      transport.invokeMethod(
        'open',
        jsonEncode(request.toJson()..['autoplay'] = autoplay),
      );
  @override
  Future<AudioSnapshot?> read() async {
    final raw = await transport.invokeMethod<String>('state');
    return raw == null
        ? null
        : AudioSnapshot(
            AudioState(Map<String, dynamic>.from(jsonDecode(raw))),
            raw,
          );
  }

  @override
  Future<void> execute(AudioCommand command) {
    final (method, value) = switch (command) {
      AudioActionCommand(:final action) => (action.name, null),
      AudioSeek(:final milliseconds) => ('seek', milliseconds),
      AudioChapter(:final index) => ('chapter', index),
      AudioRate(:final rate) => ('rate', rate),
      AudioSleep(:final minutes) => ('sleep', minutes),
      AudioRepeat(:final mode) => ('musicRepeat', mode.name),
      AudioBookmark(:final label) => ('bookmark', label),
      AudioExternal(:final uri) => ('external', uri),
    };
    return transport.invokeMethod(method, value);
  }
}
