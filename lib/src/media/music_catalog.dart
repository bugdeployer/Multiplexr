import '../core/persistence/state_repository.dart';
import 'music_catalog_models.dart';

import 'dart:convert';

export 'music_catalog_models.dart';

class MusicCatalogRepository {
  MusicCatalogRepository(StateStore store) : state = JsonStateRepository(store);
  final JsonStateRepository state;
  static const key = 'music:library';
  Future<MusicCatalog> read() async {
    final value = await state.read(key);
    return value == null ? MusicCatalog([]) : MusicCatalog.fromJson(value);
  }

  Future<void> update({
    required String collectionId,
    required bool Function(String) authorized,
    required MusicCatalog Function(MusicCatalog) change,
  }) => state.update(key, (value) async {
    if (!authorized(collectionId)) {
      throw StateError('Collection access required.');
    }
    final before = value == null
        ? MusicCatalog([])
        : MusicCatalog.fromJson(value);
    final after = change(before);
    String others(MusicCatalog c) => jsonEncode(
      c.tracks
          .where((t) => t.id.collectionId != collectionId)
          .map((t) => t.toJson())
          .toList(),
    );
    if (others(before) != others(after)) {
      throw StateError('A collection update cannot change other collections.');
    }
    if (!authorized(collectionId)) {
      throw StateError('Collection access required.');
    }
    return after.toJson();
  });
}
