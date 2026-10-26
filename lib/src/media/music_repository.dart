import '../features/metadata/application/music_metadata_host.dart';
import '../features/catalog/application/music_catalog_commands.dart';
import '../features/metadata/application/music_metadata_job_port.dart';
import '../core/application/maintenance.dart';
import '../library/library_adapter_host.dart';
import 'legacy_music_catalog_store.dart';
import 'music_catalog.dart';
import '../core/persistence/state_repository.dart';
export '../features/catalog/application/music_catalog_commands.dart';

/// Catalog adapter used by metadata and playback sessions.
class MusicRepository extends MusicCatalogCommands
    implements MusicMetadataJobPort, MusicMetadataHost {
  @override
  MusicCatalogCommands get commands => this;
  @override
  Future<MusicCatalog> readCatalog() => catalog.read();
  MusicRepository(this.library)
    : super(
        LegacyMusicCatalogStore(library.service),
        collections: () => library.collections,
        authorized: library.canAccessCollection,
      );
  final LibraryAdapterHost library;
  @override
  Object get owner => library.service.persistenceOwner;
  @override
  Maintenance get maintenance => library.service.maintenance;
  @override
  Future<Map<String, dynamic>?> readJournal(String collectionId) =>
      state.read('metadata:music:$collectionId');
  @override
  Future<void> updateJournal(
    String collectionId,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>?) change,
  ) => state.update('metadata:music:$collectionId', change);
  MusicCatalogRepository get catalog =>
      (store as LegacyMusicCatalogStore).catalog;
  JsonStateRepository get state => (store as LegacyMusicCatalogStore).state;
  @override
  Future<void> markMetadataApplied(
    String collectionId,
    String trackKey, {
    required bool Function() authorized,
  }) => state.update('metadata:music:$collectionId', (value) async {
    if (value == null || !authorized()) return value;
    final entries = Map<String, dynamic>.from(value['entries'] ?? {});
    if (entries.containsKey(trackKey)) {
      entries[trackKey] = {'status': 'applied'};
    }
    return {...value, 'entries': entries};
  });
  static const extrasKey = LegacyMusicCatalogStore.extrasKey;
}
