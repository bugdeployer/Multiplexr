import 'video_engine.dart';
import '../../../library/library_models.dart';
import '../../settings/application/player_preferences.dart';
import 'video_session.dart';

abstract interface class VideoPlaybackHost {
  VideoEngine createEngine();
  VideoWindow get window;
  PlayerPreferences get preferences;
  VideoSession session(VideoAsset asset, {required bool Function() authorized});
  Future<void> external(VideoAsset asset);
  Future<void> started(VideoAsset asset);
}
