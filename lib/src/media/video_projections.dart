import '../catalog/domain/catalog_models.dart';
import '../library/library_models.dart';
import 'contracts.dart';

extension SharedVideoAsset on VideoAsset {
  CatalogTitle<Map<String, String>> asCatalogTitle(
    MediaSubtype collectionSubtype,
  ) {
    if (collectionSubtype.type != MediaType.video) {
      throw ArgumentError('A video title needs a video collection.');
    }
    return CatalogTitle(
      id: CatalogIdentity(collectionId, id, CatalogEntityKind.title),
      subtype: collectionSubtype,
      title: title,
      metadata: Map.unmodifiable(metadata),
      sources: [
        CatalogSource(
          id: id,
          uri: uri,
          name: filename,
          rootUri: rootUri,
          available: available,
        ),
      ],
    );
  }

  MediaId get mediaId => MediaId(MediaKind.video, collectionId, id);
  VideoRecord get mediaRecord =>
      VideoRecord(mediaId, title, uri: uri, available: available);
  VideoProgress get progress => VideoProgress(
    mediaId,
    positionMs: positionMs,
    durationMs: durationMs,
    watched: watched,
  );
}

extension SharedVideoCollection on VideoCollection {
  CatalogCollection get catalogCollection => CatalogCollection(
    id: id,
    name: name,
    subtype: mediaSubtype,
    access: CatalogAccess(
      locked: locked,
      includeInGlobal: isAudio
          ? includeInGlobalAudio
          : subtype == VideoSubtype.videos
          ? includeInGlobalVideos
          : includeInGlobalCinema,
    ),
    roots: roots.map(
      (r) => CatalogRoot(
        uri: r.uri,
        name: r.name,
        contentHint: r.contentSubtype?.name,
      ),
    ),
  );

  MediaCollection get mediaCollection {
    final neutral = catalogCollection;
    return MediaCollection(
      id: neutral.id,
      name: neutral.name,
      kind: kind,
      access: CollectionAccess(
        locked: neutral.access.locked,
        includeInGlobal: neutral.access.includeInGlobal,
      ),
      sources: neutral.roots.map((r) => MediaSource(r.uri, r.name)).toList(),
    );
  }
}
