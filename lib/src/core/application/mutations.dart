import 'mutation_coordinator.dart';

/// Shared application transaction/serialization boundary.
abstract interface class ApplicationMutations {
  Future<T> run<T>(Object owner, String key, Future<T> Function() operation);
}

class OwnerApplicationMutations implements ApplicationMutations {
  const OwnerApplicationMutations();
  @override
  Future<T> run<T>(Object owner, String key, Future<T> Function() operation) =>
      MutationCoordinator.forOwner(owner).run(key, operation);
}
