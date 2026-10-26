import '../../settings/application/host_settings.dart';
import '../../settings/application/settings_registry.dart';
import '../../../settings/domain/collection_settings_schema.dart';
import '../../../library/library_models.dart';
import 'series_groups.dart';
import 'library_ports.dart';

/// Application entry points. Access is evaluated at execution, never captured as
/// a boolean in a screen draft. Adapters remain the sole durable mutation path.
class CatalogCommands {
  CatalogCommands(
    this.repository, {
    required this.authorized,
    required this.collections,
    required this.assets,
  });
  final LibraryRepository repository;
  final bool Function(String) authorized;
  final List<VideoCollection> Function() collections;
  final List<VideoAsset> Function() assets;
  void requireAccess(Iterable<String> ids) {
    if (ids.any(
      (id) => !collections().any((c) => c.id == id) || !authorized(id),
    )) {
      throw StateError('Collection access is required.');
    }
  }

  Future<void> save(VideoCollection collection) async {
    if (collections().any((c) => c.id == collection.id)) {
      requireAccess([collection.id]);
    }
    final values = collection.toJson();
    HostSettings.validate('collection', {
      for (final field in CollectionSettingsSchema.fields)
        if (field.owner == CollectionFieldOwner.settings &&
            values.containsKey(field.id))
          field.id: values[field.id],
    }, scope: RegisteredSettingScope.collection);
    await repository.saveCollection(collection);
  }

  Future<void> remove(String id) async {
    requireAccess([id]);
    await repository.removeCollection(id);
  }

  Future<void> browsing(String id, Map<String, dynamic> values) async {
    requireAccess([id]);
    await repository.saveBrowsing(id, Map.of(values));
  }

  Future<void> flags(
    List<VideoAsset> selected,
    String action,
    bool value,
  ) async {
    requireAccess(selected.map((a) => a.collectionId));
    await repository.updateFlags(selected, action, value);
  }

  Future<void> watch(VideoAsset asset, String action) async {
    requireAccess([asset.collectionId]);
    await repository.watchState(asset, action);
  }

  Future<void> update(VideoAsset asset) async {
    requireAccess([asset.collectionId]);
    await repository.saveAsset(asset);
  }

  Future<void> grouping(List<VideoAsset> changes) async {
    requireAccess(changes.map((a) => a.collectionId));
    validateSeriesCorrections(assets(), changes);
    await repository.saveGrouping(changes);
  }

  Future<void> tags(
    List<VideoAsset> selected, {
    required String operation,
    required List<String> tags,
    String? target,
    String? collectionId,
  }) async {
    requireAccess([...selected.map((a) => a.collectionId), ?collectionId]);
    if (!{'replace', 'add', 'remove', 'rename', 'delete'}.contains(operation)) {
      throw ArgumentError('Invalid tag action');
    }
    await repository.editTags(
      selected,
      operation: operation,
      tags: tags,
      target: target,
      collectionId: collectionId,
    );
  }
}
