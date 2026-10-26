/// One queue per storage owner/key. A failed operation never poisons later work.
class MutationCoordinator {
  static final _owners = Expando<MutationCoordinator>();
  static MutationCoordinator forOwner(Object owner) =>
      _owners[owner] ??= MutationCoordinator();
  final _tails = <String, Future<void>>{};
  final _revisions = <String, int>{};
  int revision(String key) => _revisions[key] ?? 0;
  Future<T> run<T>(String key, Future<T> Function() change) {
    final previous = _tails[key] ?? Future<void>.value();
    final task = previous.then((_) async {
      final result = await change();
      _revisions[key] = revision(key) + 1;
      return result;
    });
    final tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[key] = tail;
    tail.then((_) {
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
    return task;
  }
}
