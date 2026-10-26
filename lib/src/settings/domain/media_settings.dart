/// Explicit inheritance; legacy zero/automatic sentinels stay in adapters.
class SettingOverride<T extends Object> {
  const SettingOverride.inherit() : value = null;
  const SettingOverride.value(T this.value);
  final T? value;
  bool get inherited => value == null;
}

enum SettingsScope { app, collection, group, title }

enum TitleOpenAction { details, play }

enum EngineSelection { internal, external }

class SettingDefinition<T extends Object> {
  const SettingDefinition(
    this.id,
    this.defaultValue,
    this.scopes,
    this.accepts,
  );
  final String id;
  final T defaultValue;
  final Set<SettingsScope> scopes;
  final bool Function(Object) accepts;
}

bool _opening(Object value) => value is TitleOpenAction;
bool _rate(Object value) =>
    value is double && value.isFinite && value >= .5 && value <= 3;
bool _engine(Object value) => value is EngineSelection;
bool _boolean(Object value) => value is bool;

abstract final class MediaSettings {
  static const opening = SettingDefinition('opening', TitleOpenAction.play, {
    SettingsScope.app,
    SettingsScope.collection,
    SettingsScope.group,
    SettingsScope.title,
  }, _opening);
  static const rate = SettingDefinition('rate', 1.0, {
    SettingsScope.app,
    SettingsScope.collection,
    SettingsScope.group,
    SettingsScope.title,
  }, _rate);
  // Existing engine/autoplay preferences are collection-level. Do not expose
  // ineffective entity overrides until the corresponding engine consumes them.
  static const engine = SettingDefinition('engine', EngineSelection.internal, {
    SettingsScope.app,
    SettingsScope.collection,
  }, _engine);
  static const autoplayNext = SettingDefinition('autoplayNext', false, {
    SettingsScope.app,
    SettingsScope.collection,
  }, _boolean);
  static const List<SettingDefinition<Object>> definitions = [
    opening,
    rate,
    engine,
    autoplayNext,
  ];
}

class SettingsLayer {
  SettingsLayer(
    this.scope,
    this.id,
    Map<String, SettingOverride<Object>> values,
  ) : values = Map.unmodifiable(values);
  final SettingsScope scope;
  final String id;
  final Map<String, SettingOverride<Object>> values;
}

class ResolvedSetting<T> {
  const ResolvedSetting(this.value, this.scope, this.sourceId);
  final T value;
  final SettingsScope scope;
  final String sourceId;
}

class SettingsResolver {
  const SettingsResolver();
  ResolvedSetting<T> resolve<T extends Object>(
    SettingDefinition<T> definition,
    Iterable<SettingsLayer> layers, {
    T? fallback,
  }) {
    if (!definition.accepts(fallback ?? definition.defaultValue)) {
      throw ArgumentError('Invalid ${definition.id} default.');
    }
    var result = ResolvedSetting<T>(
      fallback ?? definition.defaultValue,
      SettingsScope.app,
      'defaults',
    );
    var previous = SettingsScope.app;
    for (final layer in layers) {
      if (layer.scope.index < previous.index) {
        throw ArgumentError('Settings layers must follow parent order.');
      }
      previous = layer.scope;
      final override = layer.values[definition.id];
      if (override == null || override.inherited) continue;
      if (!definition.scopes.contains(layer.scope) ||
          !definition.accepts(override.value!)) {
        throw ArgumentError(
          'Invalid ${definition.id} override at ${layer.scope.name}.',
        );
      }
      result = ResolvedSetting(override.value as T, layer.scope, layer.id);
    }
    return result;
  }
}
