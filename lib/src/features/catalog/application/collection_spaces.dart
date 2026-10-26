import '../../../catalog/domain/classification.dart';

abstract interface class CollectionSpaceStore {
  Future<Map<String, dynamic>?> read(MediaSubtype subtype, String id);
  Future<void> write(
    MediaSubtype subtype,
    String id,
    Map<String, dynamic> value, {
    required void Function() checkAccess,
  });
}

class CollectionSpaces {
  CollectionSpaces(this.store, {required this.authorized});
  final CollectionSpaceStore store;
  final bool Function(String) authorized;
  void _access(String id) {
    if (!authorized(id)) throw StateError('Collection access is required.');
  }

  Future<Map<String, dynamic>?> read(MediaSubtype subtype, String id) async {
    _access(id);
    final value = await store.read(subtype, id);
    _access(id);
    return value;
  }

  Future<void> save(
    MediaSubtype subtype,
    String id,
    Map<String, dynamic> value,
  ) async {
    _access(id);
    await store.write(subtype, id, value, checkAccess: () => _access(id));
  }
}
