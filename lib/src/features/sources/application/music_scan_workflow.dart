import '../../../core/application/clock.dart';
import '../../../features/catalog/application/music_catalog_ports.dart';
import '../../../media/music_catalog_models.dart';

class MusicDiscovery {
  MusicDiscovery(Iterable<MusicSource> sources, Iterable<String> warnings)
    : sources = List.unmodifiable(sources),
      warnings = List.unmodifiable(warnings);
  final List<MusicSource> sources;
  final List<String> warnings;
}

abstract interface class MusicDiscoveryPort {
  Future<MusicDiscovery> discover(String collectionId, {String? requestId});
}

class MusicScanWorkflow {
  MusicScanWorkflow(this.discovery, this.store, this.clock);
  final MusicDiscoveryPort discovery;
  final MusicCatalogStore store;
  final Clock clock;
  Future<List<String>> scan(
    String collectionId, {
    required bool Function(String) authorized,
    String? requestId,
    bool Function()? cancelled,
  }) async {
    if (!authorized(collectionId)) {
      throw StateError('Collection access required.');
    }
    final result = await discovery.discover(collectionId, requestId: requestId);
    final sources = result.sources;
    if (cancelled?.call() == true) throw StateError('Music scan cancelled.');
    await store.updateCatalog(
      collectionId: collectionId,
      authorized: (id) => authorized(id) && cancelled?.call() != true,
      change: (previous) => reconcileMusic(
        previous: previous,
        collectionId: collectionId,
        discovered: sources,
      ),
    );
    final catalog = await store.readCatalog();
    await store.updateExtras((value) async {
      if (!authorized(collectionId) || cancelled?.call() == true) {
        throw StateError('Music scan cancelled or collection access changed.');
      }
      final data =
          value ??
          {
            'version': 1,
            'titles': <String, dynamic>{},
            'albums': <String, dynamic>{},
            'playlists': [],
          };
      final titles = Map<String, dynamic>.from(data['titles'] ?? {});
      final now = clock.now().millisecondsSinceEpoch;
      for (final track in catalog.tracks.where(
        (t) => t.id.collectionId == collectionId,
      )) {
        final flags = Map<String, dynamic>.from(titles[track.id.key] ?? {});
        flags.putIfAbsent('addedAt', () => now);
        titles[track.id.key] = flags;
      }
      data['titles'] = titles;
      return data;
    });
    return [...result.warnings, ...musicGroupingWarnings(sources)];
  }
}
