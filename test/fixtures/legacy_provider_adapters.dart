import 'legacy_video_details.dart';
import 'package:multiplexr/src/library/library_models.dart';
// Historical provider parser fixtures. Not part of the shipping application.
import 'legacy_library_service.dart';
import 'legacy_audiobook_metadata_service.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/metadata/metadata_failures.dart';

class TmdbMetadataProvider implements MetadataProvider {
  const TmdbMetadataProvider(this.service, {this.legacyFirstPage = false});
  final LibraryService service;
  final bool legacyFirstPage;
  @override
  String get id => 'tmdb';
  @override
  Set<MetadataEntityType> get entities => const {
    MetadataEntityType.movie,
    MetadataEntityType.television,
  };
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async {
    if (!entities.contains(request.entity)) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Provider does not support this media',
      );
    }
    try {
      final type = request.entity == MetadataEntityType.television
          ? 'tv'
          : 'movie';
      final response = legacyFirstPage && request.page == 1
          ? <String, dynamic>{
              'results': await service.search(type, request.title),
            }
          : await service.searchPage(type, request.title, request.page);
      final pages = (response['total_pages'] as num?)?.toInt().clamp(1, 500);
      final rows = (response['results'] as List? ?? []).cast<Map>();
      return MetadataSearchPage(
        request: request,
        attribution: 'TMDB',
        total: (response['total_results'] as num?)?.toInt(),
        totalPages: pages,
        nextPage: pages != null
            ? (request.page < pages ? request.page + 1 : null)
            : (rows.isEmpty ? null : request.page + 1),
        candidates: await Future.wait(rows.map(
          (row) async => MetadataCandidate(
            provider: id,
            id: '${row['id']}',
            entity: request.entity,
            values: legacyFirstPage ? {...Map<String,dynamic>.from(row), ...(await matchedAsset(service,
              VideoAsset.fromJson({'id':'fixture','collectionId':'fixture','uri':'content://fixture','filename':request.title}, VideoSubtype.movies),
              VideoSubtype.movies, Map<String,dynamic>.from(row))).metadata} : Map<String, dynamic>.from(row),
            attribution: 'TMDB',
          ),
        )),
      );
    } catch (e) {
      throw metadataFailure(e);
    }
  }
}

class AudiobookMetadataProvider implements MetadataProvider {
  const AudiobookMetadataProvider(
    this.id, {
    this.service = const AudiobookMetadataService(),
  });
  @override
  final String id;
  final AudiobookMetadataService service;
  @override
  Set<MetadataEntityType> get entities => const {MetadataEntityType.audiobook};
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async {
    if (!entities.contains(request.entity)) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Provider does not support this media',
      );
    }
    try {
      final rows = await service.find(
        request.title,
        author: request.creator,
        provider: id,
        region: request.locale,
        page: request.page,
      );
      final direct = RegExp(r'^(?:[Bb]0[A-Za-z0-9]{8}|[0-9]{10})$')
          .hasMatch(request.title);
      final attribution = id == 'audiobookdb'
          ? 'AudiobookDB · https://audiobookdb.org'
          : 'Audible · ${request.locale.toUpperCase()}';
      return MetadataSearchPage(
        request: request,
        attribution: attribution,
        nextPage: rows.isEmpty || direct ? null : request.page + 1,
        candidates: rows.map(
          (row) => MetadataCandidate(
            provider: id,
            id: '${row['providerId'] ?? ''}',
            entity: request.entity,
            values: {...row, 'metadataSource': row['metadataSource'] ?? id},
            attribution: attribution,
          ),
        ),
      );
    } catch (e) {
      throw metadataFailure(e);
    }
  }
}
