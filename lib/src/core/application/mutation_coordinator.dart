import 'maintenance.dart';

/// Application-owned serialization. Framework/native repositories share this
/// queue instead of delegating transaction ownership to a UI package.
class MutationCoordinator {
  MutationCoordinator._(this.owner);
  final Object owner;
  static final _owners = Expando<MutationCoordinator>();
  static MutationCoordinator forOwner(Object owner) =>
      _owners[owner] ??= MutationCoordinator._(owner);
  final _tails = <String, Future<void>>{};
  final _revisions = <String, int>{};
  int revision(String key) => _revisions[key] ?? 0;
  Future<T> run<T>(String key, Future<T> Function() change) =>
      Maintenance.forOwner(owner).activity(() {
        final previous = _tails[key] ?? Future<void>.value();
        final task = previous.then((_) async {
          final result = await change();
          _revisions[key] = revision(key) + 1;
          return result;
        });
        final tail = task.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        _tails[key] = tail;
        tail.then((_) {
          if (identical(_tails[key], tail)) _tails.remove(key);
        });
        return task;
      });
}
