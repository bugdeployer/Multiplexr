import '../../../library/library_models.dart';

class ScanProgressEvent {
  const ScanProgressEvent({
    required this.collectionId,
    required this.found,
    required this.folder,
    this.requestId,
  });
  final String collectionId, folder;
  final String? requestId;
  final int found;
  static ScanProgressEvent? decode(Object? raw) {
    if (raw is! Map ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['found'] is! int ||
        (raw['found'] as int) < 0 ||
        raw['folder'] is! String ||
        (raw['requestId'] != null && raw['requestId'] is! String)) {
      return null;
    }
    return ScanProgressEvent(
      collectionId: raw['id'],
      found: raw['found'],
      folder: raw['folder'],
      requestId: raw['requestId'],
    );
  }

  Map<String, dynamic> toLegacyMap() => {
    'id': collectionId,
    'found': found,
    'folder': folder,
  };
}

/// Source operations preserve host-owned identities and native reconciliation.
abstract interface class CollectionSources {
  Stream<ScanProgressEvent> get progress;
  Future<LibraryRoot?> pickRoot();
  Future<void> releaseRoots(List<String> uris);
  Future<List<String>> scan(
    VideoCollection collection, {
    required String requestId,
    required bool Function() authorized,
    required bool Function() cancelled,
  });
  Future<void> cancel(String collectionId);
}
