import '../../../reading/domain/reading_catalog.dart';

/// Atomic catalog access for reader sessions. Adapters preserve existing formats.
abstract interface class ReadingProgressStore {
  Future<ReadingCatalog> read();
  Future<void> update(Future<ReadingCatalog> Function(ReadingCatalog) change);
}
