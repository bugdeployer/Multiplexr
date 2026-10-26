import 'package:flutter/foundation.dart' show Listenable;

import '../features/metadata/application/video_metadata_work.dart';

/// Flutter subscription shape; concrete dependencies are assembled at the root.
class MetadataJob extends VideoMetadataWork implements Listenable {
  MetadataJob(
    super.library,
    super.collection, {
    required super.coordinator,
    required super.runner,
  });
}
