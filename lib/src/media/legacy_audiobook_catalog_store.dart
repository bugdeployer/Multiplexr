import '../features/catalog/application/audiobook_catalog_ports.dart';
import '../core/persistence/state_repository.dart';
import '../library/library_service.dart';

class LegacyAudiobookCatalogStore implements AudiobookCatalogStore {
  LegacyAudiobookCatalogStore(this.service);
  final LibraryService service;
  static const key = 'audio:library';
  @override
  Future<Map<String, dynamic>?> read() => service.readState(key);
  @override
  Future<void> write(Map<String, dynamic> value) =>
      service.writeState(key, value);
  @override
  Future<T> mutate<T>(Future<T> Function() change) =>
      MutationCoordinator.forOwner(service.persistenceOwner).run(key, change);
}
