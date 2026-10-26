import '../features/reading/application/reading_annotations.dart';
import '../core/persistence/state_repository.dart';
import 'domain/reading_annotations.dart';
import 'domain/reading_codec.dart';
import 'reading_repository.dart';

class ReadingAnnotationsRepository extends ReadingAnnotations {
  ReadingAnnotationsRepository(StateStore store, {required super.authorized})
    : super(_LegacyReadingAnnotationStore(store, authorized: authorized));
}

class _LegacyReadingAnnotationStore implements ReadingAnnotationStore {
  _LegacyReadingAnnotationStore(this.store, {required this.authorized})
    : _state = JsonStateRepository(store);
  final StateStore store;
  final JsonStateRepository _state;
  final bool Function(String) authorized;
  @override
  Future<List<ReadingAnnotation>> read() async {
    final catalog = await ReadingRepository(store).read();
    final raw = await store.readState(ReadingAnnotationCodec.key);
    return raw == null
        ? const []
        : ReadingAnnotationCodec.decode(
            raw,
            catalog,
          ).where((a) => authorized(a.title.collectionId)).toList();
  }

  @override
  Future<void> change(
    String owner,
    List<ReadingAnnotation> Function(List<ReadingAnnotation>) change,
  ) => MutationCoordinator.forOwner(store.persistenceOwner).run(
    ReadingCodec.key,
    () => _state.update(ReadingAnnotationCodec.key, (raw) async {
      if (!authorized(owner)) {
        throw StateError('Reading collection is unavailable');
      }
      final catalog = await ReadingRepository(store).read();
      final previous = raw == null
          ? <ReadingAnnotation>[]
          : ReadingAnnotationCodec.decode(raw, catalog);
      final next = change(previous);
      final encoded = ReadingAnnotationCodec.encode(next);
      ReadingAnnotationCodec.decode(encoded, catalog);
      if (!authorized(owner)) {
        throw StateError('Reading collection is unavailable');
      }
      return encoded;
    }),
  );
}
