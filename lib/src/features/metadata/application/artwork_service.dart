import 'metadata_contracts.dart';

typedef ArtworkDownload = Future<String> Function(
  String location,
  String provider,
);

enum ArtworkRole { cover, poster, backdrop, thumbnail }

enum ArtworkSource { online, device, child }

class ArtworkCandidate {
  const ArtworkCandidate({
    required this.location,
    required this.role,
    required this.source,
    required this.ownerId,
    this.provider = '',
    this.attribution = '',
  });
  final String location, ownerId, provider, attribution;
  final ArtworkRole role;
  final ArtworkSource source;
  double get aspectRatio => switch (role) {
    ArtworkRole.cover => 1,
    ArtworkRole.poster => 2 / 3,
    _ => 16 / 9,
  };
}

class ArtworkService {
  final Map<String, Future<String>> _downloads = {};
  Future<List<ArtworkCandidate>> candidates(
    Future<List<String>> Function() lookup, {
    required String ownerId,
    required ArtworkRole role,
    required String provider,
    required MetadataCancellation cancellation,
  }) async {
    cancellation.check();
    final values = await lookup();
    cancellation.check();
    return values
        .toSet()
        .where((v) => v.isNotEmpty)
        .map(
          (v) => ArtworkCandidate(
            location: v,
            role: role,
            source: ArtworkSource.online,
            ownerId: ownerId,
            provider: provider,
            attribution: provider,
          ),
        )
        .toList();
  }

  Future<String> select(
    ArtworkCandidate candidate,
    MetadataCancellation cancellation, {
    Future<String> Function(String)? download,
  }) async {
    cancellation.check();
    if (candidate.location.isEmpty) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Artwork is unavailable',
      );
    }
    var location = candidate.location;
    if (candidate.source == ArtworkSource.online) {
      final uri = Uri.tryParse(location);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const MetadataFailure(
          MetadataFailureKind.invalidResponse,
          'Invalid online artwork',
        );
      }
      if (download != null) {
        final key = '${candidate.ownerId}:${candidate.provider}:$location';
        final future = _downloads.putIfAbsent(key, () => download(location));
        try {
          location = await future;
        } catch (_) {
          _downloads.remove(key);
          rethrow;
        }
      }
    }
    cancellation.check();
    if (location.isEmpty) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Could not save artwork',
      );
    }
    return location;
  }
}
