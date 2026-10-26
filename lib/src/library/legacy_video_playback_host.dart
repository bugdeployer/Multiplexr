import 'native_player.dart';
import '../features/playback/application/video_playback_host.dart';
import '../features/playback/application/video_session.dart';
import '../features/settings/application/player_preferences.dart';
import '../media/contracts.dart';
import 'library_models.dart';
import 'library_service.dart';
import 'legacy_player_preferences.dart';
import 'legacy_video_session_store.dart';

class LegacyVideoPlaybackHost implements VideoPlaybackHost {
  const LegacyVideoPlaybackHost(this.service);
  final LibraryService service;
  @override
  VideoEngine createEngine() => Player();
  @override
  VideoWindow get window => PlaybackWindow.instance;
  @override
  PlayerPreferences get preferences =>
      PlayerPreferences(LegacyPlayerPreferenceStore(service));
  @override
  VideoSession session(
    VideoAsset asset, {
    required bool Function() authorized,
  }) {
    final generation = service.maintenance.generation;
    return VideoSession(
      MediaId(MediaKind.video, asset.collectionId, asset.id),
      LegacyVideoSessionStore(service, asset),
      authorized: () =>
          service.maintenance.isCurrent(generation) && authorized(),
      maintenance: service.maintenance,
    );
  }

  @override
  Future<void> external(VideoAsset asset) => service.external(asset);
  @override
  Future<void> started(VideoAsset asset) => service.watchState(asset, 'start');
}
