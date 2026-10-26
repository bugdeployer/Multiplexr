import 'dart:typed_data';

import 'metadata_contracts.dart';
import 'metadata_workflow.dart';
import 'publication_provider.dart';

/// Batch work resolves an installed provider at each bounded search, never a vendor.
class RegistryMusicProvider
    implements
        MusicProvider,
        VersionedMetadataProvider,
        MetadataCommitProvider {
  RegistryMusicProvider(this.workflow);
  final MetadataWorkflow Function() workflow;
  @override
  Future<void> commitCandidate(
    MetadataCandidate candidate,
    Future<void> Function() operation,
  ) => workflow().authorizeCommit(candidate, operation);
  @override
  String get checkpointIdentity => workflow().implementationEpoch;
  @override
  String get id => 'host:auto';
  @override
  Set<MetadataEntityType> get entities => const {
    MetadataEntityType.musicTrack,
    MetadataEntityType.musicAlbum,
  };
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) =>
      workflow().search(request, MetadataCancellation());
  @override
  Future<List<String>> artwork(String releaseId) async =>
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Choose an installed artwork contribution.',
      );
  @override
  Future<String> download(String url) async => throw const MetadataFailure(
    MetadataFailureKind.unavailable,
    'Artwork downloads belong to the host gateway.',
  );
}

class RegistryPublicationProvider
    implements
        PublicationProvider,
        VersionedMetadataProvider,
        MetadataCommitProvider {
  RegistryPublicationProvider(this.workflow);
  final MetadataWorkflow Function() workflow;
  @override
  Future<void> commitCandidate(
    MetadataCandidate candidate,
    Future<void> Function() operation,
  ) => workflow().authorizeCommit(candidate, operation);
  @override
  String get checkpointIdentity => workflow().implementationEpoch;
  @override
  String get id => 'host:auto';
  @override
  Set<MetadataEntityType> get entities => const {
    MetadataEntityType.ebook,
    MetadataEntityType.comic,
  };
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) =>
      workflow().search(request, MetadataCancellation());
  @override
  Future<Map<String, dynamic>> details(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    cancellation.check();
    return candidate.values;
  }

  @override
  Future<Uint8List> cover(String url) async => throw const MetadataFailure(
    MetadataFailureKind.unavailable,
    'Choose an installed artwork contribution.',
  );
}
