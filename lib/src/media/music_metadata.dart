import '../features/metadata/application/publication_provider.dart';
import '../features/metadata/application/metadata_contracts.dart';
export '../features/metadata/application/music_metadata_target.dart';
export '../features/metadata/application/music_artwork.dart';

/// Zero-plugin default; installed search is resolved through the registry.
class NoInstalledMusicProvider implements MusicProvider {
  @override
  String get id => 'host.unavailable';
  @override
  Set<MetadataEntityType> get entities => const {
    MetadataEntityType.musicTrack,
    MetadataEntityType.musicAlbum,
  };
  Never unavailable() => throw const MetadataFailure(
    MetadataFailureKind.unavailable,
    'Install and enable a metadata or artwork plugin.',
  );
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async =>
      unavailable();
  @override
  Future<List<String>> artwork(String releaseId) async => unavailable();
  @override
  Future<String> download(String url) async => unavailable();
}
