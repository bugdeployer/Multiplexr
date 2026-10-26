import '../features/jobs/application/activity_queries.dart';
import '../media/music_catalog.dart';
import '../media/contracts.dart';
import 'library_adapter_host.dart';
import 'library_models.dart';

class LegacyActivitySource implements ActivitySource {
  const LegacyActivitySource(this.library);
  final LibraryAdapterHost library;
  @override
  Future<Map<String, dynamic>?> journal(VideoCollection c) =>
      library.service.readState(
        c.kind == MediaKind.music
            ? 'metadata:music:${c.id}'
            : c.isAudio
            ? 'metadata:audiobooks:${c.id}'
            : 'metadata:${c.id}',
      );
  @override
  Future<Set<String>> eligibleAudioIds(VideoCollection c) async =>
      c.kind == MediaKind.music
      ? (await MusicCatalogRepository(library.service).read()).tracks
            .where(
              (t) =>
                  t.id.collectionId == c.id &&
                  t.metadata.metadataSource.isEmpty,
            )
            .map((t) => t.id.key)
            .toSet()
      : (await library.audiobookCatalog(collectionId: c.id).books())
            .map((b) => b.id.key)
            .toSet();
}
