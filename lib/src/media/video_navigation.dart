import 'source_recovery.dart';
import '../experience/navigation/navigation_origin.dart';
import '../experience/navigation/navigation_coordinator.dart';

import 'package:flutter/material.dart';

import '../library/library_models.dart';
import '../library/library_controller.dart';
import '../library/series.dart';
import 'video_projections.dart';
import 'navigation_settings.dart';
import '../experience/navigation/opening_policy.dart';

/// Shared decision/access boundary; callers retain their existing route/layout.
Future<void> openVideoTitle(
  BuildContext context,
  LibraryController library,
  VideoAsset asset, {
  required bool legacyDetails,
  required Future<void> Function() details,
  required Future<void> Function() play,
  NavigationOrigin? origin,
  void Function(NavigationOrigin)? restore,
}) async {
  if (!library.canAccessCollection(asset.collectionId)) return;
  final collection = library.collections
      .where((c) => c.id == asset.collectionId)
      .firstOrNull;
  if (collection == null) return;
  final series = seriesIdentity(asset);
  final effective = await resolveMediaNavigation(
    library.service,
    collection: collection,
    collectionId: asset.collectionId,
    ancestorIds: [if (series != null) 'series:$series'],
    titleId: asset.mediaId.key,
    legacyDetails: legacyDetails,
  );
  if (!context.mounted || !library.canAccessCollection(asset.collectionId)) {
    return;
  }
  final destination = effective.destination(
    authorized: library.canAccessCollection(asset.collectionId),
    available: asset.available,
  );
  await NavigationCoordinator.forOwner(library).run(
    '${asset.mediaId.key}:$destination',
    () async {
      switch (destination) {
        case OpeningDestination.details:
          await details();
        case OpeningDestination.session:
          await play();
        case OpeningDestination.unavailable:
          showUnavailableSource(context, library, asset.collectionId);
        case OpeningDestination.contents || OpeningDestination.denied:
          return;
      }
    },
    origin: origin,
    restore: restore,
  );
}
