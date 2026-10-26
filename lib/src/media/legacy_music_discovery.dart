import '../features/sources/application/music_scan_workflow.dart';
import '../library/library_service.dart';
import 'audio_models.dart';
import 'music_catalog_models.dart';

class LegacyMusicDiscovery implements MusicDiscoveryPort {
  LegacyMusicDiscovery(this.service);
  final LibraryService service;
  @override
  Future<MusicDiscovery> discover(
    String collectionId, {
    String? requestId,
  }) async {
    final result = await service.transport.invokeMapMethod<String, dynamic>(
      'discoverMusic',
      {'id': collectionId, 'requestId': ?requestId},
    );
    if (result == null) throw StateError('Music discovery returned no result.');
    final sources = (result['sources'] as List).map((raw) {
      final v = Map<String, dynamic>.from(raw);
      return MusicSource(
        id: v['id'],
        rootId: v['rootId'],
        folderId: v['folderId'],
        folderName: v['folderName'],
        albumArtist: v['albumArtist'] ?? '',
        releaseId: v['releaseId'] ?? '',
        year: v['year'],
        cover: v['cover'] ?? '',
        file: AudioFile.fromJson(Map<String, dynamic>.from(v['file'])),
      );
    }).toList();
    return MusicDiscovery(sources, List<String>.from(result['warnings'] ?? []));
  }
}
