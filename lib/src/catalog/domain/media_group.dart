/// A group owns ordering, not the progress or metadata of its children.
class MediaGroup<T> {
  const MediaGroup(this.id, this.title, this.children);
  final String id, title;
  final List<T> children;
}

Map<String, List<T>> groupMedia<T>(Iterable<T> items, String Function(T) key) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    groups.putIfAbsent(key(item), () => []).add(item);
  }
  return groups;
}
