import '../features/reading/application/reader_handoff.dart';
import '../library/library_service.dart';
import 'domain/reading_catalog.dart';
import '../features/catalog/application/reading_catalog_commands.dart';
import 'legacy_reading_catalog_store.dart';

class LegacyReaderHandoff implements ExternalReaderPort {
  const LegacyReaderHandoff(this.service, {required this.authorized});
  final LibraryService service;
  final bool Function(String) authorized;
  @override
  Future<void> open(ReadingTitle title, String package) async {
    await service.transport.invokeMethod<bool>('openExternalReading', {
      'collectionId': title.catalog.id.collectionId,
      'titleId': title.catalog.id.entityId,
      'revision': title.sourceRevision,
      'package': package,
    });
  }

  @override
  Future<void> recordOpened(ReadingTitle title) => ReadingCatalogCommands(
    LegacyReadingCatalogStore(service),
    authorized: authorized,
  ).recordOpened(title.catalog.id, DateTime.now().millisecondsSinceEpoch);
}
