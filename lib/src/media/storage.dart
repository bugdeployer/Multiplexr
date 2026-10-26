import 'dart:convert';

import '../library/library_models.dart';
import '../library/library_service.dart';
import 'video_projections.dart';
import 'contracts.dart';

/// Namespaced persistence; legacy video queue bytes remain unchanged.
class MediaStorage implements MediaProgressStore, MediaQueueStore {
  const MediaStorage(this.service);
  final LibraryService service;
  @override
  Future<MediaProgress?> read(MediaId id) async {
    if (id.kind == MediaKind.video) {
      final data = await service.load();
      final raw = (data['assets'] as List? ?? [])
          .cast<Map>()
          .where(
            (a) => a['collectionId'] == id.collectionId && a['id'] == id.itemId,
          )
          .firstOrNull;
      return raw == null
          ? null
          : VideoAsset.fromJson(
              Map<String, dynamic>.from(raw),
              VideoSubtype.videos,
            ).progress;
    }
    final data = await service.readState('progress:${id.key}');
    if (data == null) return null;
    final progress = MediaProgress.fromJson(data);
    if (progress.id != id) throw StateError('Progress identity mismatch');
    return progress;
  }

  @override
  Future<void> write(MediaProgress progress) => progress is VideoProgress
      ? service.writeVideoProgress(progress.toJson())
      : service.writeState('progress:${progress.id.key}', progress.toJson());
  @override
  Future<List<MediaId>> readQueue(MediaKind kind) async {
    if (kind == MediaKind.video) {
      final data = await service.load();
      return (data['queue'] as List? ?? []).map((key) {
        final pair = jsonDecode(key as String) as List;
        return MediaId(kind, pair[0], pair[1]);
      }).toList();
    }
    final state = await service.readState('queue:${kind.name}');
    final items = (state?['items'] as List? ?? [])
        .map((v) => MediaId.fromJson(Map<String, dynamic>.from(v)))
        .toList();
    if (items.any((id) => id.kind != kind)) {
      throw StateError('Mixed media queue');
    }
    return items;
  }

  @override
  Future<void> writeQueue(MediaKind kind, List<MediaId> items) {
    if (items.any((id) => id.kind != kind) ||
        items.toSet().length != items.length) {
      throw ArgumentError(
        'Queue identities must be unique and match its medium',
      );
    }
    if (kind == MediaKind.video) {
      return service.saveQueue(
        items.map((id) => jsonEncode([id.collectionId, id.itemId])).toList(),
      );
    }
    return service.writeState('queue:${kind.name}', {
      'items': items.map((id) => id.toJson()).toList(),
    });
  }
}
