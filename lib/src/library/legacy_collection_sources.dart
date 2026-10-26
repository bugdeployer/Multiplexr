import '../features/sources/application/source_ports.dart';
import '../media/contracts.dart';
import '../media/music_scanner.dart';
import 'library_models.dart';
import 'library_service.dart';

class LegacyCollectionSources implements CollectionSources {
  const LegacyCollectionSources(this.service);
  final LibraryService service;
  @override
  Stream<ScanProgressEvent> get progress => service.scanEvents;
  @override
  Future<LibraryRoot?> pickRoot() => service.pickRoot();
  @override
  Future<void> releaseRoots(List<String> uris) => service.releaseRoots(uris);
  @override
  Future<void> cancel(String collectionId) => service.cancelScan(collectionId);
  @override
  Future<List<String>> scan(
    VideoCollection collection, {
    required String requestId,
    required bool Function() authorized,
    required bool Function() cancelled,
  }) async {
    if (!authorized() || cancelled()) {
      throw StateError('Collection access is required.');
    }
    return collection.kind == MediaKind.music
        ? MusicScanner(service).scan(
            collection.id,
            requestId: requestId,
            authorized: (_) => authorized(),
            cancelled: cancelled,
          )
        : service.scan(collection.id, requestId: requestId);
  }
}
