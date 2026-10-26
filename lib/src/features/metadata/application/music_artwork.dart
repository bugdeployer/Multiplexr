import 'metadata_contracts.dart';
import 'artwork_service.dart';
import 'publication_provider.dart';

Future<String> selectMusicArtwork(
  MusicProvider provider,
  String location,
  MetadataCancellation cancellation,
) => ArtworkService().select(
  ArtworkCandidate(
    location: location,
    role: ArtworkRole.cover,
    source: ArtworkSource.online,
    ownerId: location,
    provider: 'cover-art-archive',
    attribution: 'Cover Art Archive',
  ),
  cancellation,
  download: provider.download,
);
