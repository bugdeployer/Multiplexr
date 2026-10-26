import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/classification.dart';
import 'collection_presenter.dart';

/// A local scope ignores global exclusions but never collection authorization.
class SpaceScope {
  const SpaceScope(this.subtype, {this.collectionId});
  final MediaSubtype subtype;
  final String? collectionId;
  bool get local => collectionId != null;
  bool includes(CatalogCollection collection, {required bool authorized}) =>
      collection.subtype == subtype &&
      authorized &&
      (local
          ? collection.id == collectionId
          : collection.access.eligibleGlobally);
}

class SpaceController<T, K> extends CollectionController<T, K> {
  SpaceController({required super.identity});
  int tab = 0;

  List<T> eligible(Iterable<T> items, bool Function(T) permitted) =>
      items.where(permitted).toList();

  /// Browsing preferences must not remove items from continuation or queues.
  List<T> browsing(
    Iterable<T> items, {
    required bool hideCompleted,
    required bool Function(T) completed,
  }) => items.where((item) => !hideCompleted || !completed(item)).toList();

  List<T> showcase(
    Iterable<T> eligible,
    Iterable<K> pins, {
    required bool pinned,
  }) {
    final values = eligible.toList();
    if (!pinned) return values.take(3).toList();
    final byId = {for (final item in values) identity(item): item};
    return [
      for (final key in pins.toSet().take(3))
        if (byId.containsKey(key)) byId[key]!,
    ];
  }
}
