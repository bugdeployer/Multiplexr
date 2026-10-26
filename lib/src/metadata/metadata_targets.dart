import 'dart:convert';

export '../features/metadata/application/audiobook_metadata_target.dart';

import 'package:flutter/services.dart';

import 'metadata_failures.dart';
import '../library/library_models.dart';
import '../library/library_service.dart';
import '../features/metadata/application/metadata_contracts.dart';

class VideoMetadataTarget implements MetadataTarget {
  VideoMetadataTarget({
    required this.service,
    required this.asset,
    required this.latest,
    required this.access,
  });
  @override
  MetadataEntityType get entity => asset.mediaSubtype == VideoSubtype.tv
      ? MetadataEntityType.television
      : MetadataEntityType.movie;
  final LibraryService service;
  final VideoAsset asset;
  final Future<VideoAsset> Function() latest;
  final bool Function() access;
  @override
  Object get owner => service.persistenceOwner;
  @override
  String get key => 'video:${asset.collectionId}:${asset.id}';
  @override
  bool get authorized => access();
  static const artworkFields = {'poster', 'backdrop', 'seriesBackdrop'};
  static const descriptiveFields = {
    'title',
    'year',
    'genres',
    'director',
    'series',
    'seriesOverview',
    'description',
    'cast',
    'tagline',
    'runtimeMinutes',
    'airDate',
    'seasonEpisodeCount',
  };
  Map<String, dynamic> fields(VideoAsset a) => {
    ...a.metadata,
    'poster': a.poster,
    'backdrop': a.backdrop,
    'seriesBackdrop': a.seriesBackdrop,
  };
  @override
  Future<MetadataSnapshot> read() async {
    final a = await latest();
    return MetadataSnapshot(
      fields(a),
      provider: a.metadataSource,
      candidateId: a.metadata['providerCandidate'] ?? '${a.providerId ?? ''}',
      manualFields: {
        if (a.metadataSource == 'manual') ...a.metadata.keys,
        for (final key in artworkFields)
          if (a.metadata['${key}Source'] == 'manual') key,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    cancellation.check();
    return {
      for (final e in candidate.values.entries)
        if (descriptiveFields.contains(e.key) && e.value != null)
          e.key: e.value,
    };
  }

  @override
  Future<void> commit(
    Map<String, dynamic> selected,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    final a = await latest();
    if (!authorized) {
      throw const MetadataFailure(
        MetadataFailureKind.permission,
        'Collection access is required.',
      );
    }
    try {
      final updated = VideoAsset.fromJson({
        ...a.toJson(),
        'metadata': {
          ...a.metadata,
          for (final e in selected.entries)
            if (!artworkFields.contains(e.key))
              e.key: (e.value is List
                  ? (e.value as List).join(', ')
                  : e.value.toString()),
          if (candidate.implementation != null)
            'providerImplementation': jsonEncode(
              candidate.implementation!.toJson(),
            ),
          'providerCandidate': candidate.id,
        },
        for (final key in artworkFields)
          if (selected.containsKey(key)) key: selected[key],
        if (selected.containsKey('poster') && selected['poster'] != a.poster)
          'localPoster': null,
        if (selected.containsKey('backdrop') &&
            selected['backdrop'] != a.backdrop)
          'localBackdrop': null,
        if (selected.containsKey('seriesBackdrop') &&
            selected['seriesBackdrop'] != a.seriesBackdrop)
          'localSeriesBackdrop': null,
        'providerId': null,
        'metadataSource': a.metadataSource == 'manual'
            ? 'manual'
            : candidate.provenance,
        'metadataStatus': '',
      }, a.mediaSubtype);
      cancellation.check();
      await service.applyMetadataPatch(a, updated, {
        ...selected.keys,
        if (candidate.implementation != null) 'providerImplementation',
        'providerCandidate',
      });
    } on MetadataFailure {
      rethrow;
    } on PlatformException catch (e) {
      throw metadataFailure(e);
    } catch (_) {
      throw const MetadataFailure(
        MetadataFailureKind.storage,
        'Could not save to device storage.',
      );
    }
  }
}
