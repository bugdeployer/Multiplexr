import '../application/mutations.dart';
import '../application/maintenance.dart';
import 'state_repository.dart';

class LegacyApplicationMutations implements ApplicationMutations {
  const LegacyApplicationMutations();
  @override
  Future<T> run<T>(Object owner, String key, Future<T> Function() operation) =>
      Maintenance.forOwner(
        owner,
      ).activity(() => MutationCoordinator.forOwner(owner).run(key, operation));
}
