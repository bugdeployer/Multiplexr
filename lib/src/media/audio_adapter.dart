import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import 'audio_models.dart';

extension SharedAudiobookTitle on Audiobook {
  CatalogTitle<AudiobookMetadata> get catalogTitle => CatalogTitle(
    id: CatalogIdentity(id.collectionId, id.itemId, CatalogEntityKind.title),
    subtype: MediaSubtype.audiobooks,
    title: metadata.title,
    metadata: metadata,
    segments: chapterMarkers.map(
      (chapter) => CatalogSegment(
        id: chapter.id,
        sourceId: chapter.fileId,
        title: chapter.title,
        startMs: chapter.startMs,
        endMs: chapter.endMs,
      ),
    ),
    sources: files.map(
      (file) => CatalogSource(id: file.id, uri: file.uri, name: file.filename),
    ),
  );
}
