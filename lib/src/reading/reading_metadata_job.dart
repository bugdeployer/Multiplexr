import 'package:flutter/foundation.dart' show Listenable;

import '../features/metadata/application/reading_metadata_work.dart';

/// Flutter subscription shape; concrete dependencies are assembled at the root.
class ReadingMetadataJob extends ReadingMetadataWork implements Listenable {
  ReadingMetadataJob(
    super.library,
    super.collectionId,
    super.provider, {
    required super.workflow,
    required super.runner,
  });
}
