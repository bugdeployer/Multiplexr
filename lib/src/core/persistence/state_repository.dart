import '../application/mutation_coordinator.dart';
export '../application/mutation_coordinator.dart' show MutationCoordinator;

import 'dart:convert';

import '../application/maintenance.dart';

/// A JSON state boundary; codecs and storage implementation remain in adapters.
abstract interface class StateStore {
  Object get persistenceOwner;
  Future<Map<String, dynamic>?> readState(String key);
  Future<void> writeState(String key, Map<String, dynamic>? value);
}

class JsonStateRepository {
  JsonStateRepository(this.store, {Object? owner})
    : mutations = MutationCoordinator.forOwner(owner ?? store.persistenceOwner);
  final StateStore store;
  final MutationCoordinator mutations;
  Future<Map<String, dynamic>?> read(String key) => store.readState(key);
  Future<void> update(
    String key,
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>?) change,
  ) => Maintenance.forOwner(store.persistenceOwner).activity(
    () => mutations.run(key, () async {
      final current = await store.readState(key);
      // Storage adapters may return shared maps. Work on a detached JSON snapshot.
      final draft = current == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(jsonEncode(current)));
      final next = await change(draft);
      final snapshot = next == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(jsonEncode(next)));
      await store.writeState(key, snapshot);
    }),
  );
}
