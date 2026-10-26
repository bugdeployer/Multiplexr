import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import 'contracts.dart' show MediaId, MediaKind, MediaProgress;
import 'storage.dart';

/// Neutral callers retain the exact legacy progress identity and storage keys.
MediaId legacyTitleId(CatalogIdentity id, MediaSubtype subtype) {
  if (id.kind != CatalogEntityKind.title) {
    throw ArgumentError('Groups do not own title progress.');
  }
  final kind = switch (subtype) {
    MediaSubtype.moviesTv || MediaSubtype.videos => MediaKind.video,
    MediaSubtype.audiobooks => MediaKind.audiobook,
    MediaSubtype.music => MediaKind.music,
    _ => throw UnsupportedError(
      'Progress for ${subtype.name} is not implemented.',
    ),
  };
  return MediaId(kind, id.collectionId, id.entityId);
}

class CatalogProgressAdapter {
  const CatalogProgressAdapter(this.legacy);
  final MediaStorage legacy;
  Future<MediaProgress?> read(CatalogIdentity id, MediaSubtype subtype) =>
      legacy.read(legacyTitleId(id, subtype));
  Future<void> write(
    CatalogIdentity id,
    MediaSubtype subtype,
    MediaProgress progress,
  ) {
    if (progress.id != legacyTitleId(id, subtype)) {
      throw ArgumentError('Progress identity mismatch.');
    }
    return legacy.write(progress);
  }
}
