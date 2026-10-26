import 'package:flutter/foundation.dart' show Listenable;

import '../features/metadata/application/audiobook_metadata_work.dart';

/// Flutter subscription shape; concrete dependencies are assembled at the root.
class AudiobookMetadataJob extends AudiobookMetadataWork implements Listenable {
  AudiobookMetadataJob(
    super.library, {
    super.collectionId,
    required super.coordinator,
    required super.runner,
  });
}
