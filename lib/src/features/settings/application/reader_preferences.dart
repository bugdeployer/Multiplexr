import '../../../settings/domain/media_settings.dart';
import '../../../reading/domain/reading_catalog.dart';
import '../../../reading/domain/reader_settings.dart';

Map<String, ResolvedSetting<Object>> resolveReaderPreferences(
  ReadingCatalog catalog,
  ReadingTitle title,
) {
  final parent = catalog.memberships
      .where((m) => m.child == title.catalog.id)
      .firstOrNull
      ?.parent;
  final layers =
      catalog.settings
          .where(
            (s) =>
                s.subtype == title.catalog.subtype &&
                (s.scope == SettingsScope.app ||
                    s.collectionId == title.catalog.id.collectionId &&
                        (s.scope == SettingsScope.collection ||
                            s.scope == SettingsScope.group &&
                                s.entityId == parent?.entityId ||
                            s.scope == SettingsScope.title &&
                                s.entityId == title.catalog.id.entityId)),
          )
          .toList()
        ..sort((a, b) => a.scope.index.compareTo(b.scope.index));
  return {
    for (final definition in ReaderSettings.definitions(title.catalog.subtype))
      definition.id: const SettingsResolver().resolve(
        definition,
        layers.map((s) => s.layer),
      ),
  };
}
