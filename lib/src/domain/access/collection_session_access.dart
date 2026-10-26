/// Pure session grant state. Presentation decides when lifecycle events revoke it.
class CollectionSessionAccess {
  String? activeCollectionId;
  final _grants = <String>{};
  bool canAccess(String id, {required bool locked}) =>
      !locked || _grants.contains(id);
  void begin(String id) {
    _grants.clear();
    activeCollectionId = id;
  }

  void authorize(String id) => _grants.add(id);
  void revoke(String id) => _grants.remove(id);
  void relock() => _grants.clear();
  void end() {
    relock();
    activeCollectionId = null;
  }
}
