import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../features/catalog/application/extension_catalog.dart';
import '../features/catalog/application/space_queries.dart';
import '../catalog/domain/classification.dart';
import '../reading/reading_app_controller.dart';
import 'library_controller.dart';
import 'library_models.dart';

/// Storage/controller composition adapter; the extension contract owns none of
/// these dependencies. Plugin access is checked by the host gateway.
class LegacyExtensionCatalog implements ExtensionCatalogSource {
  const LegacyExtensionCatalog(this.library, this.reading);
  final LibraryController library;
  final ReadingAppController reading;
  bool _reading(ExtensionMedia kind) =>
      kind == ExtensionMedia.ebook || kind == ExtensionMedia.comic;
  @override
  bool authorized(String collection, ExtensionMedia kind) => _reading(kind)
      ? reading.canAccess(collection)
      : library.collections.any((c) => c.id == collection) &&
            library.canAccessCollection(collection);
  String _revision(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  ExtensionTitle _title(
    String id,
    String collection,
    ExtensionMedia kind,
    String title,
    Object version,
  ) => ExtensionTitle(
    id: id,
    collection: collection,
    kind: kind,
    title: title,
    revision: _revision([library.service.maintenance.generation, version]),
  );
  @override
  Future<List<ExtensionTitle>> titles(
    String collection,
    ExtensionMedia kind,
  ) async {
    if (_reading(kind)) {
      final catalog = await reading.library.readCollection(collection);
      return [
        for (final title in catalog.catalog.titles)
          if (title.catalog.id.collectionId == collection &&
              (title.catalog.subtype.name == 'ebook') ==
                  (kind == ExtensionMedia.ebook))
            _title(
              title.catalog.id.entityId,
              collection,
              kind,
              title.catalog.title,
              [title.sourceRevision, title.catalog.metadata.toJson()],
            ),
      ];
    }
    if (kind == ExtensionMedia.audiobook) {
      final books = await library
          .audiobookCatalog(collectionId: collection)
          .query();
      return [
        for (final book in books)
          _title(
            book.id.itemId,
            collection,
            kind,
            book.metadata.title,
            book.toJson(),
          ),
      ];
    }
    if (kind == ExtensionMedia.music) {
      final tracks = await library.musicCatalog.tracks(
        SpaceScope(MediaSubtype.music, collectionId: collection),
      );
      return [
        for (final track in tracks)
          _title(
            track.id.itemId,
            collection,
            kind,
            track.metadata.title,
            track.toJson(),
          ),
      ];
    }
    await library.load();
    return [
      for (final asset in library.items(collection))
        if ((asset.mediaSubtype == VideoSubtype.tv
                ? ExtensionMedia.television
                : asset.mediaSubtype == VideoSubtype.videos
                ? ExtensionMedia.video
                : ExtensionMedia.movie) ==
            kind)
          _title(asset.id, collection, kind, asset.title, asset.toJson()),
    ];
  }
}
