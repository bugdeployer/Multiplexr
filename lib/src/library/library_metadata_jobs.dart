import 'series_metadata_job.dart';
import 'series.dart';
import '../features/metadata/application/metadata_contracts.dart';

import 'package:flutter/foundation.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import '../features/jobs/application/job_registry.dart';
import '../media/audiobook_metadata_job.dart';
import 'library_adapter_host.dart';
import 'library_models.dart';
import 'metadata_job.dart';

class LibraryMetadataJobs {
  LibraryMetadataJobs(
    this.library, {
    required this.search,
    required this.createVideoJob,
    required this.createAudiobookJob,
    required this.createTarget,
    required this.createSeriesJob,
  });
  final SeriesMetadataJob Function(SeriesRecord) createSeriesJob;
  SeriesMetadataJob series(SeriesRecord value) {
    final collectionId = value.assets.first.collectionId;
    final anchor = (value.assets.map((a) => a.id).toList()..sort()).first;
    return observe(
      registry.obtain(
        'series:$collectionId:$anchor',
        () => createSeriesJob(value),
        authorized: () => library.canAccessCollection(collectionId),
      ),
    );
  }

  final MetadataJob Function(VideoCollection) createVideoJob;
  final AudiobookMetadataJob Function(String?) createAudiobookJob;
  final MetadataTarget Function(VideoAsset) createTarget;
  final LibraryAdapterHost library;
  late final registry = ApplicationJobs(
    maintenance: library.service.maintenance,
  );
  final _observed = <Listenable>{};
  T observe<T extends Listenable>(T job) {
    if (_observed.add(job)) job.addListener(library.notifyListeners);
    return job;
  }

  final MetadataWorkflow search;
  MetadataTarget target(VideoAsset asset) => createTarget(asset);
  MetadataJob video(VideoCollection collection) {
    final job = registry.obtain(
      'video:${collection.id}',
      () => createVideoJob(collection),
      authorized: () =>
          library.collections.any((c) => c.id == collection.id) &&
          library.canAccessCollection(collection.id),
    );
    job.collection = collection;
    return observe(job);
  }

  AudiobookMetadataJob audiobook(String? collectionId) => observe(
    registry.obtain(
      'audiobook:$collectionId',
      () => createAudiobookJob(collectionId),
      authorized: () =>
          collectionId == null ||
          library.collections.any((c) => c.id == collectionId) &&
              library.canAccessCollection(collectionId),
    ),
  );
}
