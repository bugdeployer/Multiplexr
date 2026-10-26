import 'package:flutter/foundation.dart' show Listenable;

import '../features/metadata/application/series_metadata_work.dart';

/// Flutter subscription adapter; application work and journals remain pure.
class SeriesMetadataJob extends SeriesMetadataWork implements Listenable {
  SeriesMetadataJob(
    super.series, {
    required super.owner,
    required super.maintenance,
    required super.checkAccess,
    required super.readState,
    required super.writeState,
    required super.items,
    required super.reload,
    required super.target,
    required super.runner,
    required super.coordinator,
  });
}
