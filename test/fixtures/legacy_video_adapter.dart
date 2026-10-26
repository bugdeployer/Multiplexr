import 'legacy_library_service.dart';
import 'package:multiplexr/src/media/contracts.dart';
export 'package:multiplexr/src/media/video_projections.dart';

class TmdbVideoProvider implements MediaMetadataProvider {
  const TmdbVideoProvider(this.service, {this.television = false});
  final LibraryService service;
  final bool television;
  @override
  String get providerId => 'tmdb';
  @override
  Set<MediaKind> get supportedKinds => const {MediaKind.video};
  @override
  Future<List<Map<String, dynamic>>> search(MediaKind kind, String query) {
    if (!supportedKinds.contains(kind)) {
      throw UnsupportedError('TMDB supports video metadata only');
    }
    return service.search(television ? 'tv' : 'movie', query);
  }
}
