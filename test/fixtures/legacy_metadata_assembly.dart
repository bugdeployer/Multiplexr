import 'legacy_library_service.dart';

import 'package:multiplexr/src/library/legacy_video_metadata_jobs.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/metadata/metadata_targets.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_work_runner.dart';
import 'package:multiplexr/src/metadata/metadata_failures.dart';

import 'legacy_video_details.dart';

import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/bootstrap/metadata_assembly.dart' as production;
export 'package:multiplexr/src/bootstrap/metadata_assembly.dart'
    hide createMetadataJob, createAudiobookMetadataJob;
import 'package:multiplexr/src/library/library_adapter_host.dart';
import 'package:multiplexr/src/library/metadata_job.dart';
import 'package:multiplexr/src/media/audio_library.dart';
import 'package:multiplexr/src/media/audiobook_metadata_job.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import 'legacy_provider_adapters.dart';

MetadataWorkflow historicalVideo(LibraryAdapterHost library) =>
    MetadataWorkflow([
      TmdbMetadataProvider(
        library.service as LibraryService,
        legacyFirstPage: true,
      ),
    ], mutations: const OwnerApplicationMutations());
MetadataWorkflow historicalAudio() => MetadataWorkflow([
  const AudiobookMetadataProvider('audiobookdb'),
], mutations: const OwnerApplicationMutations());
MetadataJob createMetadataJob(
  LibraryAdapterHost library,
  VideoCollection collection, {
  MetadataWorkflow? workflow,
}) => MetadataJob(
  HistoricalVideoJobs(library),
  collection,
  coordinator: workflow ?? historicalVideo(library),
  runner: MetadataWorkRunner(classify: metadataFailure),
);
AudiobookMetadataJob createAudiobookMetadataJob(
  AudioLibrary library, {
  String? collectionId,
  MetadataWorkflow? workflow,
}) => production.createAudiobookMetadataJob(
  library,
  collectionId: collectionId,
  workflow: workflow ?? historicalAudio(),
);

class HistoricalVideoJobs extends LegacyVideoMetadataJobs {
  HistoricalVideoJobs(super.library);
  @override
  MetadataTarget target(
    VideoAsset lookup,
    VideoAsset original,
    String collectionId,
  ) {
    final base =
        super.target(lookup, original, collectionId) as VideoMetadataTarget;
    return HistoricalVideoTarget(
      service: base.service,
      asset: base.asset,
      latest: base.latest,
      access: base.access,
    );
  }
}

class HistoricalVideoTarget extends VideoMetadataTarget {
  HistoricalVideoTarget({
    required super.service,
    required super.asset,
    required super.latest,
    required super.access,
  });
  @override
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    if (candidate.implementation != null) {
      return super.resolve(candidate, cancellation);
    }
    final matched = await matchedAsset(
      service,
      await latest(),
      asset.mediaSubtype,
      candidate.values,
    );
    cancellation.check();
    return fields(matched)..removeWhere(
      (key, value) =>
          (!VideoMetadataTarget.descriptiveFields.contains(key) &&
              !VideoMetadataTarget.artworkFields.contains(key)) ||
          key.endsWith('Source') ||
          value == null ||
          value == '',
    );
  }
}
