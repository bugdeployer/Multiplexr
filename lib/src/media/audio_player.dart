import 'package:flutter/foundation.dart';

import '../core/application/maintenance.dart';
import '../features/playback/application/music_queue.dart' show MusicAudioPort;
import '../features/playback/application/audio_session_controller.dart';
import '../features/playback/application/audio_playback_models.dart';
export '../features/playback/application/audio_playback_models.dart';
export '../features/playback/application/audio_commands.dart';
import 'audio_models.dart';

/// Observable app session over injected engine and import ports.
class AudioController extends ChangeNotifier
    with AudioSessionApplication
    implements MusicAudioPort {
  AudioController({
    required this.engine,
    required this.pickFiles,
    required this.releaseUnusedFiles,
    Maintenance? maintenance,
  }) {
    _detachMaintenance = maintenance?.register(
      invalidate: () {
        _stopForMaintenance = _stopForMaintenance || state.data.isNotEmpty;
        invalidateSession();
      },
      drain: () async {
        if (_stopForMaintenance) {
          await engine.execute(const AudioCommand.action(AudioAction.stop));
          _stopForMaintenance = false;
        }
      },
    );
  }
  void Function()? _detachMaintenance;
  bool _stopForMaintenance = false;
  @override
  final AudioEnginePort engine;
  final Future<AudioImport?> Function() pickFiles;
  final Future<void> Function(List<AudioFile>) releaseUnusedFiles;

  @override
  void dispose() {
    _detachMaintenance?.call();
    disposeSession();
    super.dispose();
  }
}
