import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Application-owned extension projections. No persisted dictionaries, codecs,
/// framework controllers or source URIs cross this boundary. The permission
/// gateway must resolve opaque plugin handles to these internal identities.
enum ExtensionMedia { movie, television, video, music, audiobook, ebook, comic }

class ExtensionTitle {
  const ExtensionTitle({
    required this.id,
    required this.collection,
    required this.kind,
    required this.title,
    required this.revision,
  });
  final String id, collection, title, revision;
  final ExtensionMedia kind;
}

class ExtensionTitlePage {
  ExtensionTitlePage(Iterable<ExtensionTitle> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<ExtensionTitle> items;
  final String? nextCursor;
}

class ExtensionCatalogConflict implements Exception {
  const ExtensionCatalogConflict();
}

abstract interface class ExtensionCatalogSource {
  Future<List<ExtensionTitle>> titles(String collection, ExtensionMedia kind);
  bool authorized(String collection, ExtensionMedia kind);
}

class ExtensionCatalogQueries {
  const ExtensionCatalogQueries(this.source, {this.generation});
  final ExtensionCatalogSource source;
  final int Function()? generation;
  Future<ExtensionTitlePage> titles(
    String collection,
    ExtensionMedia kind, {
    int limit = 50,
    String? cursor,
  }) async {
    if (collection.isEmpty || limit < 1 || limit > 100) {
      throw ArgumentError('Invalid catalog query');
    }
    int offset = 0;
    String? expected;
    if (cursor != null) {
      final separator = cursor.indexOf(':');
      if (cursor.length > 256 || separator < 1) {
        throw ArgumentError('Invalid cursor');
      }
      offset = int.tryParse(cursor.substring(0, separator)) ?? -1;
      expected = cursor.substring(separator + 1);
      if (offset < 0 || expected.isEmpty) throw ArgumentError('Invalid cursor');
    }
    void access() {
      if (!source.authorized(collection, kind)) {
        throw StateError('Catalog scope is unavailable');
      }
    }

    final started = generation?.call();
    access();
    final rows = List.of(await source.titles(collection, kind));
    access();
    if (started != generation?.call()) throw const ExtensionCatalogConflict();
    if (rows.any(
          (row) =>
              row.collection != collection ||
              row.kind != kind ||
              row.id.isEmpty ||
              row.revision.isEmpty,
        ) ||
        rows.map((row) => row.id).toSet().length != rows.length) {
      throw StateError('Invalid catalog projection');
    }
    rows.sort((a, b) => a.id.compareTo(b.id));
    final revision = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              collection,
              kind.name,
              for (final row in rows) [row.id, row.title, row.revision],
            ]),
          ),
        )
        .toString();
    if (expected != null && expected != revision) {
      throw const ExtensionCatalogConflict();
    }
    if (offset > rows.length) throw ArgumentError('Invalid cursor');
    final page = rows.skip(offset).take(limit).toList();
    final end = offset + page.length;
    return ExtensionTitlePage(
      page,
      end < rows.length ? '$end:$revision' : null,
    );
  }
}
