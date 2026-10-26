import '../features/playback/application/video_session.dart';
import '../media/contracts.dart';
import 'library_models.dart';
import 'library_service.dart';

/// Retains the native position command and its watched/completion semantics.
class LegacyVideoSessionStore implements VideoSessionStore {
  const LegacyVideoSessionStore(this.service, this.asset);
  final LibraryService service;
  final VideoAsset asset;
  @override
  Future<void> save(VideoProgress progress) {
    if (progress.id.collectionId != asset.collectionId ||
        progress.id.itemId != asset.id) {
      throw ArgumentError('Video session identity mismatch');
    }
    return service.position(
      VideoAsset.fromJson({
        ...asset.toJson(),
        'durationMs': progress.durationMs,
      }, asset.mediaSubtype),
      progress.positionMs,
    );
  }
}
