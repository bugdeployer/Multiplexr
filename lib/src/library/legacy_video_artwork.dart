import '../features/metadata/application/video_artwork.dart';
import 'library_models.dart';
import 'library_service.dart';

class LegacyVideoArtwork implements VideoArtworkPort {
  const LegacyVideoArtwork(this.service);
  final LibraryService service;
  @override
  Future<List<String>> candidates(VideoAsset asset, String kind) =>
      Future.value(const []);
  @override
  Future<void> apply(VideoAsset before, VideoAsset after, Set<String> fields) =>
      service.applyMetadataPatch(before, after, fields);
}
