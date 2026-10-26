import 'package:flutter/services.dart';

import '../core/application/maintenance.dart';
import '../features/metadata/application/video_metadata_job_port.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../metadata/metadata_targets.dart';
import 'library_adapter_host.dart';
import 'library_models.dart';

class LegacyVideoMetadataJobs implements VideoMetadataJobPort {
  LegacyVideoMetadataJobs(this.library);
  final LibraryAdapterHost library;
  @override
  Object get owner => library.service.persistenceOwner;
  @override
  Maintenance get maintenance => library.service.maintenance;
  @override
  bool checkpointSupported = true;
  @override
  bool canAccessCollection(String id) => library.canAccessCollection(id);
  @override
  List<VideoAsset> items(String id) => library.items(id);
  @override
  List<VideoAsset> indexedItems(String id) => library.indexedItems(id);
  @override
  Future<void> load() => library.load();
  @override
  Future<Map<String, dynamic>?> readJournal(String id) async {
    try {
      return await library.service.readState('metadata:$id');
    } on MissingPluginException {
      checkpointSupported = false;
      return null;
    }
  }

  @override
  Future<bool> writeJournal(String id, Map<String, dynamic> value) async {
    try {
      await library.service.writeState('metadata:$id', value);
      return true;
    } on MissingPluginException {
      checkpointSupported = false;
      return false;
    }
  }

  @override
  MetadataTarget target(
    VideoAsset lookup,
    VideoAsset original,
    String collectionId,
  ) => VideoMetadataTarget(
    service: library.service,
    asset: lookup,
    access: () => canAccessCollection(collectionId),
    latest: () async =>
        indexedItems(collectionId)
            .where((asset) => asset.id == original.id)
            .firstOrNull ??
        (throw const MetadataFailure(
          MetadataFailureKind.unavailable,
          'This title no longer exists.',
        )),
  );
  @override
  Future<void> applyStatus(VideoAsset before, VideoAsset after) =>
      library.service.applyMetadataPatch(before, after, {});
}
