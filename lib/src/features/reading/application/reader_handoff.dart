import '../../../reading/domain/reading_catalog.dart';

abstract interface class ExternalReaderPort {
  Future<void> open(ReadingTitle title, String package);
  Future<void> recordOpened(ReadingTitle title);
}

class ReaderHandoff {
  const ReaderHandoff(this.port, {required this.authorized});
  final ExternalReaderPort port;
  final bool Function(String) authorized;
  Future<void> open(ReadingTitle title, String package) async {
    if (package.isEmpty) throw ArgumentError('Reader package is required');
    if (!authorized(title.catalog.id.collectionId)) {
      throw StateError('Reading collection is unavailable');
    }
    await port.open(title, package);
    if (!authorized(title.catalog.id.collectionId)) return;
    try {
      await port.recordOpened(title);
    } catch (_) {
      // The external reader already opened. An activity-write failure must never
      // trigger a retry that launches another reader or replays media.
    }
  }
}
