import '../features/reading/application/reading_progress_store.dart';
import 'reading_changes.dart';
import '../core/persistence/state_repository.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_codec.dart';

/// Uses the app's persistence owner and shared mutation coordinator.
class ReadingRepository implements ReadingProgressStore {
  ReadingRepository(StateStore store) : _state = JsonStateRepository(store);
  final JsonStateRepository _state;
  @override
  Future<ReadingCatalog> read() async {
    final value = await _state.read(ReadingCodec.key);
    return value == null ? ReadingCatalog() : ReadingCodec.decode(value);
  }

  @override
  Future<void> update(Future<ReadingCatalog> Function(ReadingCatalog) change) =>
      _state
          .update(ReadingCodec.key, (value) async {
            final next = await change(
              value == null ? ReadingCatalog() : ReadingCodec.decode(value),
            );
            final encoded = ReadingCodec.encode(next);
            ReadingCodec.decode(
              encoded,
            ); // Programmatic callers use the same wire gate.
            return encoded;
          })
          .then(
            (_) =>
                ReadingChanges.forOwner(_state.store.persistenceOwner)
                    .changed(),
          );
  Future<void> removeCollection(String id) =>
      update((c) async => c.withoutCollection(id));
  Future<void> saveProgress(ReadingProgress progress) => update(
    (c) async => ReadingCatalog(
      collections: c.collections,
      groups: c.groups,
      titles: c.titles,
      memberships: c.memberships,
      settings: c.settings,
      progress: [...c.progress.where((p) => p.id != progress.id), progress],
    ),
  );
}
