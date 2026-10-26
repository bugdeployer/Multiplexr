import 'package:multiplexr/src/metadata/metadata_failures.dart';
import 'package:multiplexr/src/core/application/mutations.dart';

import '../library/library_controller.dart';
import '../library/series_metadata_job.dart';
import '../library/series.dart';
import '../library/metadata_job.dart';
import '../library/library_adapter_host.dart';
import '../library/library_models.dart';
import '../library/legacy_video_metadata_jobs.dart';
import '../media/audio_library.dart';
import '../media/audiobook_metadata_job.dart';
import '../media/legacy_audiobook_metadata_jobs.dart';
import '../media/music_metadata_job.dart';
import '../reading/reading_metadata_job.dart';
import '../reading/reading_metadata_host.dart';
import '../reading/legacy_reading_metadata_jobs.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../features/metadata/application/music_metadata_job_port.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_work_runner.dart';

MetadataJob createMetadataJob(
  LibraryAdapterHost library,
  VideoCollection collection, {
  MetadataWorkflow? workflow,
}) => MetadataJob(
  LegacyVideoMetadataJobs(library),
  collection,
  coordinator:
      workflow ??
      MetadataWorkflow([], mutations: const OwnerApplicationMutations()),
  runner: MetadataWorkRunner(classify: metadataFailure),
);
AudiobookMetadataJob createAudiobookMetadataJob(
  AudioLibrary library, {
  String? collectionId,
  MetadataWorkflow? workflow,
}) => AudiobookMetadataJob(
  LegacyAudiobookMetadataJobs(library),
  collectionId: collectionId,
  coordinator:
      workflow ??
      MetadataWorkflow([], mutations: const OwnerApplicationMutations()),
  runner: MetadataWorkRunner(classify: metadataFailure),
);
ReadingMetadataJob createReadingMetadataJob(
  ReadingMetadataHost library,
  String id,
  MetadataProvider provider,
) => ReadingMetadataJob(
  LegacyReadingMetadataJobs(library),
  id,
  provider,
  workflow: MetadataWorkflow([
    provider,
  ], mutations: const OwnerApplicationMutations()),
  runner: MetadataWorkRunner(classify: metadataFailure),
);
MusicMetadataJob createMusicMetadataJob(
  MusicMetadataJobPort repository,
  String id,
  MetadataProvider provider,
) => MusicMetadataJob(
  repository,
  id,
  provider,
  workflow: MetadataWorkflow([
    provider,
  ], mutations: const OwnerApplicationMutations()),
  runner: MetadataWorkRunner(classify: metadataFailure),
);

SeriesMetadataJob createSeriesMetadataJob(
  LibraryController library,
  SeriesRecord series, {
  MetadataWorkflow? workflow,
}) => SeriesMetadataJob(
  series,
  owner: library.service.persistenceOwner,
  maintenance: library.service.maintenance,
  checkAccess: () =>
      library.commands.requireAccess([series.assets.first.collectionId]),
  readState: library.service.readState,
  writeState: library.service.writeState,
  items: library.indexedItems,
  reload: library.load,
  target: library.metadataJobs.target,
  runner: MetadataWorkRunner(classify: metadataFailure),
  coordinator:
      workflow ??
      MetadataWorkflow([], mutations: const OwnerApplicationMutations()),
);
