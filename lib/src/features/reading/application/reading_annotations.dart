import '../../../reading/domain/reading_annotations.dart';

abstract interface class ReadingAnnotationStore {
  Future<List<ReadingAnnotation>> read();

  /// Adapter validates the resulting set against the current catalog in the same
  /// transaction, including authorization immediately before commit.
  Future<void> change(
    String owner,
    List<ReadingAnnotation> Function(List<ReadingAnnotation>) change,
  );
}

class ReadingAnnotations {
  const ReadingAnnotations(this.store, {required this.authorized});
  final ReadingAnnotationStore store;
  final bool Function(String) authorized;
  Future<List<ReadingAnnotation>> read() async => (await store.read())
      .where((a) => authorized(a.title.collectionId))
      .toList();
  Future<void> save(ReadingAnnotation annotation) => _change(
    annotation.title.collectionId,
    (items) => [...items.where((a) => a.id != annotation.id), annotation],
  );
  Future<void> remove(ReadingAnnotation annotation) => _change(
    annotation.title.collectionId,
    (items) => items.where((a) => a.id != annotation.id).toList(),
  );
  Future<void> _change(
    String owner,
    List<ReadingAnnotation> Function(List<ReadingAnnotation>) change,
  ) => store.change(owner, (previous) {
    if (!authorized(owner)) {
      throw StateError('Reading collection is unavailable');
    }
    final next = change(previous);
    for (final a in previous.where((a) => a.title.collectionId != owner)) {
      if (!next.any(
        (b) => b.id == a.id && b.toJson().toString() == a.toJson().toString(),
      )) {
        throw StateError('Annotation owner mismatch');
      }
    }
    return next;
  });
}
