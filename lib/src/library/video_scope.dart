import '../catalog/domain/classification.dart';

import 'dart:convert';

import 'library_models.dart';
import 'library_controller.dart';
import '../features/catalog/application/video_queries.dart';

List<VideoCollection> globalVideoCollections(LibraryController library) =>
    scopedVideoCollections(library, MediaSubtype.videos);
List<VideoCollection> scopedVideoCollections(
  LibraryController library,
  MediaSubtype subtype, {
  String? collectionId,
}) {
  return library.scopedCollections(subtype, collectionId: collectionId);
}

List<VideoAsset> videoSpaceItems(
  LibraryController library, {
  String? collectionId,
}) => scopedVideoCollections(
  library,
  MediaSubtype.videos,
  collectionId: collectionId,
).expand((c) => library.items(c.id)).toList();
List<VideoAsset> videoSpaceQueue(
  LibraryController library, {
  String? collectionId,
}) {
  final keys = videoSpaceItems(
    library,
    collectionId: collectionId,
  ).map(library.queueKey).toSet();
  return library.queuedVideos
      .where((a) => keys.contains(library.queueKey(a)))
      .toList();
}

String videoParent(VideoAsset a) {
  final parts = a.relativePath.replaceAll('\\', '/').split('/');
  if (parts.length < 2) return '';
  return parts.take(parts.length - 1).join('/');
}

String videoFolderKey(VideoAsset a) =>
    jsonEncode([a.collectionId, a.rootUri, videoParent(a)]);
String videoFolderLabel(
  VideoAsset a,
  LibraryController library, {
  bool global = false,
}) {
  final collection = library.collections
      .where((c) => c.id == a.collectionId)
      .firstOrNull;
  final root = collection?.roots
      .where((r) => r.uri == a.rootUri)
      .firstOrNull
      ?.name;
  final folder = videoParent(a);
  final label = [
    if (global) collection?.name,
    root,
    if (folder.isNotEmpty) folder,
  ].whereType<String>().where((s) => s.isNotEmpty).join(' / ');
  return label.isEmpty ? collection?.name ?? 'Root folder' : label;
}

List<String> videoTags(VideoAsset a) => (a.metadata['tags'] ?? '')
    .split(RegExp(r'[,;]'))
    .map((s) => s.trim().replaceFirst(RegExp(r'^#'), ''))
    .where((s) => s.isNotEmpty)
    .toList();
List<VideoAsset> browseVideoFeed(
  List<VideoAsset> source, {
  String query = '',
  String sort = 'added',
  String filter = 'all',
  String? folder,
  String? tag,
}) {
  final words = query.toLowerCase().trim();
  final filtered = source
      .where(
        (a) =>
            (folder == null || videoFolderKey(a) == folder) &&
            (tag == null ||
                videoTags(a)
                    .any((t) => t.toLowerCase() == tag.toLowerCase())) &&
            (words.isEmpty ||
                '${a.title} ${a.filename} ${a.relativePath} ${a.metadata['tags'] ?? ''}'
                    .toLowerCase()
                    .contains(words)),
      )
      .toList();
  return browseVideos(filtered, sort: sort, filter: filter);
}
