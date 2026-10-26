import 'dart:convert';

import '../../../reading/domain/reading_codec.dart';

Map<String, dynamic> parseBackup(String text) {
  final data = Map<String, dynamic>.from(jsonDecode(text));
  if (data['format'] != 'multiplexr-library' ||
      data['version'] != 1 ||
      data['collections'] is! List ||
      data['assets'] is! List) {
    throw const FormatException('Unsupported backup');
  }
  return data;
}

bool backupContainsLocked(Map<String, dynamic> data) =>
    (data['collections'] as List).any((c) => c['locked'] == true) ||
    readingBackupCollections(data).any((c) => c['locked'] == true);

/// Remap only source roots in the preview; identities/progress remain untouched.
void relinkBackupRoot(
  Map<String, dynamic> data,
  Map<String, dynamic> collection,
  int index,
  String uri,
  String name, {
  required bool reading,
}) {
  final roots = collection['roots'] as List;
  final old = roots[index]['uri'];
  (roots[index] as Map)['uri'] = uri;
  (roots[index] as Map)['name'] = name;
  if (!reading) {
    for (final asset in data['assets'] as List) {
      if (asset['collectionId'] == collection['id'] &&
          asset['rootUri'] == old) {
        asset['rootUri'] = uri;
      }
    }
    return;
  }
  final state = data['state'] as Map;
  for (final title in state[ReadingCodec.key]['titles'] as List) {
    if (title['collectionId'] == collection['id'] &&
        title['source']['rootUri'] == old) {
      title['source']['rootUri'] = uri;
      title['source']['available'] = false;
    }
  }
  final evidence = state['reading:index:v1'] as Map?;
  for (final entry in evidence?['entries'] as List? ?? []) {
    if (entry['collectionId'] == collection['id'] && entry['rootUri'] == old) {
      entry['rootUri'] = uri;
    }
  }
  for (final root in evidence?['roots'] as List? ?? []) {
    if (root['collectionId'] == collection['id'] && root['uri'] == old) {
      root['uri'] = uri;
      root['complete'] = false;
    }
  }
  (evidence?['replacements'] as List?)?.removeWhere(
    (r) => r['collectionId'] == collection['id'],
  );
}

String backupSummary(Map<String, dynamic> data) {
  final state = data['state'] as Map? ?? {};
  final books = (state['audio:library'] as Map?)?['books'] as List? ?? [];
  final tracks = (state['music:library'] as Map?)?['tracks'] as List? ?? [];
  final sources = books.fold<int>(
    0,
    (sum, b) => sum + ((b['files'] as List?)?.length ?? 0),
  );
  final reading = data['state']?[ReadingCodec.key] as Map?;
  final readingTitles = reading?['titles'] as List? ?? [];
  final annotations =
      data['state']?['reading:annotations:v1']?['items'] as List? ?? [];
  final base =
      '${(data['collections'] as List).length + readingBackupCollections(data).length} collections · ${(data['assets'] as List).length} videos · ${books.length} audiobooks ($sources audio files) · ${tracks.length} music tracks';
  final pageNotes = state['reading:management:v1']?['pageNotes'] as List? ?? [];
  return readingBackupCollections(data).isEmpty
      ? base
      : '$base · ${readingTitles.where((t) => t['subtype'] == 'ebook').length} ebooks · ${readingTitles.where((t) => t['subtype'] == 'comics').length} comics · ${annotations.length + pageNotes.length} reading annotations';
}

List<Map<String, dynamic>> readingBackupCollections(
  Map<String, dynamic> data,
) => (data['state']?[ReadingCodec.key]?['collections'] as List? ?? [])
    .map((v) => v as Map<String, dynamic>)
    .toList();
