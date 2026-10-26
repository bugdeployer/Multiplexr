import 'host_settings.dart';
import 'settings_registry.dart';
import '../../../catalog/domain/classification.dart';
import '../../../reading/domain/reading_catalog.dart';
import '../../../reading/domain/reader_settings.dart';
import '../../../settings/domain/media_settings.dart';
import '../../reading/application/reading_progress_store.dart';

class ReaderPreferenceCommands {
  const ReaderPreferenceCommands(this.store, {required this.authorized});
  final ReadingProgressStore store;
  final bool Function(String) authorized;
  Future<void> setScope({
    required MediaSubtype subtype,
    required SettingsScope scope,
    String? collectionId,
    String? entityId,
    Map<String, Object> changes = const {},
    bool reset = false,
    String? inherit,
  }) async {
    void access() {
      if (scope != SettingsScope.app &&
          (collectionId == null || !authorized(collectionId))) {
        throw StateError('Reading collection is unavailable');
      }
    }

    access();
    HostSettings.validate(
      'reader.${subtype.name}',
      changes,
      scope: RegisteredSettingScope.values.byName(scope.name),
    );
    if (inherit != null &&
        !ReaderSettings.definitions(subtype).any((d) => d.id == inherit)) {
      throw ArgumentError('Unknown reader preference');
    }
    await store.update((catalog) async {
      access();
      final old = catalog.settings
          .where(
            (layer) =>
                layer.scope == scope &&
                layer.subtype == subtype &&
                layer.collectionId == collectionId &&
                layer.entityId == entityId,
          )
          .firstOrNull;
      final values = reset
          ? <String, Object>{}
          : <String, Object>{...?old?.values, ...changes};
      if (inherit != null) values.remove(inherit);
      return ReadingCatalog(
        collections: catalog.collections,
        groups: catalog.groups,
        titles: catalog.titles,
        memberships: catalog.memberships,
        progress: catalog.progress,
        settings: [
          ...catalog.settings.where((layer) => !identical(layer, old)),
          if (values.isNotEmpty)
            ReadingSettingsLayer(
              scope: scope,
              subtype: subtype,
              collectionId: collectionId,
              entityId: entityId,
              values: values,
            ),
        ],
      );
    });
  }

  Future<void> setTitle(
    ReadingTitle title,
    Map<String, Object> changes, {
    bool reset = false,
    Future<void> Function(ReadingCatalog)? prepare,
  }) async {
    void access() {
      if (!authorized(title.catalog.id.collectionId)) {
        throw StateError('Reading collection is unavailable');
      }
    }

    access();
    HostSettings.validate(
      'reader.${title.catalog.subtype.name}',
      changes,
      scope: RegisteredSettingScope.title,
    );
    await store.update((catalog) async {
      access();
      final old = catalog.settings
          .where(
            (s) =>
                s.scope == SettingsScope.title &&
                s.collectionId == title.catalog.id.collectionId &&
                s.entityId == title.catalog.id.entityId,
          )
          .firstOrNull;
      final values = reset
          ? <String, dynamic>{}
          : <String, dynamic>{...?old?.values, ...changes};
      final next = ReadingCatalog(
        collections: catalog.collections,
        groups: catalog.groups,
        titles: catalog.titles,
        memberships: catalog.memberships,
        progress: catalog.progress,
        settings: [
          ...catalog.settings.where((s) => !identical(s, old)),
          if (values.isNotEmpty)
            ReadingSettingsLayer(
              scope: SettingsScope.title,
              subtype: title.catalog.subtype,
              collectionId: title.catalog.id.collectionId,
              entityId: title.catalog.id.entityId,
              values: values,
            ),
        ],
      );
      if (prepare != null) await prepare(next);
      access();
      return next;
    });
  }
}
