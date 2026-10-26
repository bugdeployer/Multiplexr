import 'dart:typed_data';

import 'metadata_contracts.dart';

abstract interface class PublicationProvider implements MetadataProvider {
  Future<Map<String, dynamic>> details(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  );
  Future<Uint8List> cover(String url);
}

abstract interface class MusicProvider implements MetadataProvider {
  Future<List<String>> artwork(String releaseId);
  Future<String> download(String url);
}
