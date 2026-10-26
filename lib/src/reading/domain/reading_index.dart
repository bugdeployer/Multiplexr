import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/classification.dart';
import 'reading_catalog.dart';

/// Scan evidence is portable but separate from the R1 publication/progress schema.
class ReadingIndex {
  ReadingIndex(Map<String, dynamic> json, ReadingCatalog catalog)
    : json = Map<String, dynamic>.from(jsonDecode(jsonEncode(json))) {
    final row = ReadingWire.object(this.json, {
      'version',
      'entries',
      'roots',
      'replacements',
      'orders',
    });
    if (row['version'] is! int ||
        row['version'] != 1 ||
        jsonEncode(row).length > 10000000) {
      throw FormatException('Unsupported reading index');
    }
    final titles = {
      for (final t in catalog.titles)
        identity(t.catalog.id.collectionId, t.catalog.id.entityId): t,
    };
    final seen = <String>{};
    for (final raw in ReadingWire.list(row['entries'])) {
      final e = ReadingWire.object(raw, {
        'collectionId',
        'id',
        'sourceKey',
        'rootUri',
        'relativePath',
        'fingerprint',
        'metadata',
        'cover',
        'manualFields',
        'manualOrder',
        'manualCover',
        'encoding',
      });
      final key = identity(
        ReadingWire.text(e['collectionId']),
        ReadingWire.text(e['id']),
      );
      final title = titles[key];
      if (title == null ||
          !seen.add(key) ||
          title.catalog.sources.single.rootUri != e['rootUri']) {
        throw FormatException('Invalid reading index owner');
      }
      ReadingWire.text(e['sourceKey']);
      ReadingWire.text(e['relativePath']);
      if (!RegExp(r'^[a-f0-9]{64}$')
          .hasMatch(ReadingWire.text(e['fingerprint']))) {
        throw FormatException('Invalid source fingerprint');
      }
      ReadingMetadata.fromJson(e['metadata']);
      ReadingWire.flag(e['manualOrder']);
      ReadingWire.flag(e['manualCover']);
      final fields = ReadingWire.list(e['manualFields'], 6);
      if (fields.toSet().length != fields.length ||
          fields.any((v) => !metadataFields.contains(v))) {
        throw FormatException('Invalid manual field');
      }
      final cover = e['cover'];
      if (cover is! String ||
          cover.length > 2000000 ||
          !(cover.isEmpty ||
              RegExp(r'^reading-cover:[a-f0-9]{64}$').hasMatch(cover) ||
              cover.startsWith('data:image/jpeg;base64,') &&
                  RegExp(r'^[A-Za-z0-9+/]*={0,2}$')
                      .hasMatch(cover.substring(23)))) {
        throw FormatException('Invalid reading cover');
      }
      if (!encodings.contains(e['encoding'])) {
        throw FormatException('Invalid text encoding');
      }
    }
    final owners = {for (final c in catalog.collections) c.id: c};
    final roots = <String>{};
    for (final raw in ReadingWire.list(row['roots'], 1000000)) {
      final root = ReadingWire.object(raw, {'collectionId', 'uri', 'complete'});
      final c = owners[ReadingWire.text(root['collectionId'])];
      if (c == null ||
          !c.roots.any((r) => r.uri == root['uri']) ||
          !roots.add(identity(c.id, ReadingWire.text(root['uri'])))) {
        throw FormatException('Invalid root health');
      }
      ReadingWire.flag(root['complete']);
    }
    for (final raw in ReadingWire.list(row['replacements'], 10000)) {
      final r = ReadingWire.object(raw, {'collectionId', 'from', 'to'});
      final c = owners[ReadingWire.text(r['collectionId'])];
      if (c == null || !c.roots.any((root) => root.uri == r['to'])) {
        throw FormatException('Invalid root replacement');
      }
      final old = Uri.parse(ReadingWire.text(r['from']));
      if (old.scheme != 'content' || old.host.isEmpty || r['from'] == r['to']) {
        throw FormatException('Invalid old root');
      }
    }
    final orderedOwners = <String>{};
    for (final raw in ReadingWire.list(row['orders'], 10000)) {
      final o = ReadingWire.object(raw, {'collectionId', 'ids'});
      final owner = ReadingWire.text(o['collectionId']);
      final ids = ReadingWire.list(o['ids']);
      if (!owners.containsKey(owner) ||
          !orderedOwners.add(owner) ||
          ids.toSet().length != ids.length ||
          ids.any(
            (id) => id is! String || !titles.containsKey(identity(owner, id)),
          )) {
        throw FormatException('Invalid manual title order');
      }
    }
  }
  final Map<String, dynamic> json;
  static const key = 'reading:index:v1';
  static const metadataFields = {
    'title',
    'authors',
    'description',
    'language',
    'identifier',
    'comicStyle',
  };
  static const encodings = {
    '',
    'utf-8',
    'utf-16le',
    'utf-16be',
    'windows-1252',
  };
  static Map<String, dynamic> empty() => {
    'version': 1,
    'entries': <dynamic>[],
    'roots': <dynamic>[],
    'replacements': <dynamic>[],
    'orders': <dynamic>[],
  };
  static String identity(String collectionId, String titleId) =>
      jsonEncode([collectionId, titleId]);
  static String stableId(String collectionId, String sourceKey) =>
      'reading:${sha256.convert(utf8.encode(identity(collectionId, sourceKey)))}';
  static Map<String, dynamic> copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  late final Map<String, Map<String, dynamic>> _byTitle = {
    for (final e in (json['entries'] as List).cast<Map<String, dynamic>>())
      identity(e['collectionId'] as String, e['id'] as String): e,
  };
  Map<String, dynamic>? entry(CatalogIdentity id) =>
      id.kind != CatalogEntityKind.title
      ? null
      : _byTitle[identity(id.collectionId, id.entityId)];
}

/// Natural order compares digit runs without losing decimal chapters or specials.
int readingNaturalCompare(String a, String b) {
  final chunks = RegExp(r'[0-9]+|[^0-9]+');
  final left = chunks.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = chunks.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i], y = right[i];
    final numbers = RegExp(r'^[0-9]+$');
    int result;
    if (numbers.hasMatch(x) && numbers.hasMatch(y)) {
      final nx = x.replaceFirst(RegExp(r'^0+'), ''),
          ny = y.replaceFirst(RegExp(r'^0+'), '');
      result = nx.length.compareTo(ny.length);
      if (result == 0) result = nx.compareTo(ny);
    } else {
      result = x.compareTo(y);
    }
    if (result != 0) return result;
  }
  final length = left.length.compareTo(right.length);
  return length != 0 ? length : a.compareTo(b);
}
