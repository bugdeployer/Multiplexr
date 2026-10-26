import '../media/music_playback.dart';
import '../reading/reading_app_controller.dart';

/// One owner for app-level sessions. Attachment/lifecycle UI stays in AppShell.
class AppSessionScope {
  AppSessionScope({required this.music, required this.reading});
  final MusicPlayback music;
  final ReadingAppController reading;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    reading.dispose();
    music.dispose();
  }
}
