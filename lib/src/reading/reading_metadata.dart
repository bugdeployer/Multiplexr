import 'dart:typed_data';

import '../features/metadata/application/publication_provider.dart';
import '../features/metadata/application/metadata_contracts.dart';
export '../features/metadata/application/reading_metadata_target.dart';

class NoInstalledPublicationProvider implements PublicationProvider {
  @override
  String get id => 'host.unavailable';
  @override
  Set<MetadataEntityType> get entities => const {
    MetadataEntityType.ebook,
    MetadataEntityType.comic,
  };
  Never unavailable() => throw const MetadataFailure(
    MetadataFailureKind.unavailable,
    'Install and enable a metadata or artwork plugin.',
  );
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async =>
      unavailable();
  @override
  Future<Map<String, dynamic>> details(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async => unavailable();
  @override
  Future<Uint8List> cover(String url) async => unavailable();
}
