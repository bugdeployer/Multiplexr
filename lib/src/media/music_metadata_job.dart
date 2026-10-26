import 'package:flutter/foundation.dart' show Listenable;

import '../features/metadata/application/music_metadata_work.dart';

class MusicMetadataJob extends MusicMetadataWork implements Listenable {
  MusicMetadataJob(
    super.repository,
    super.collectionId,
    super.provider, {
    required super.workflow,
    required super.runner,
  });
}
