import '../catalog/domain/classification.dart';
import '../features/catalog/application/collection_spaces.dart';
import '../core/persistence/state_repository.dart';
import 'library_service.dart';

class LegacyCollectionSpaces implements CollectionSpaceStore {
  LegacyCollectionSpaces(this.service);
  final LibraryService service;
  String _key(MediaSubtype subtype, String id) => switch (subtype) {
    MediaSubtype.music => 'spaces:music:$id',
    MediaSubtype.audiobooks => 'spaces:audiobooks:$id',
    _ => throw ArgumentError('Unsupported separate space preferences'),
  };
  @override
  Future<Map<String, dynamic>?> read(MediaSubtype subtype, String id) =>
      service.readState(_key(subtype, id));
  @override
  Future<void> write(
    MediaSubtype subtype,
    String id,
    Map<String, dynamic> value, {
    required void Function() checkAccess,
  }) => JsonStateRepository(service).update(_key(subtype, id), (_) async {
    checkAccess();
    return value;
  });
}
