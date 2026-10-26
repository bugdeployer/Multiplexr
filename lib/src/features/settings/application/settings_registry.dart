enum RegisteredSettingScope { app, collection, group, title }

class RegisteredSetting {
  RegisteredSetting({
    required this.key,
    required this.label,
    required this.defaultValue,
    required this.accepts,
    Set<RegisteredSettingScope> scopes = const {RegisteredSettingScope.app},
    this.secret = false,
  }) : scopes = Set.unmodifiable(scopes);
  final String key, label;
  final Object defaultValue;
  final bool Function(Object) accepts;
  final Set<RegisteredSettingScope> scopes;
  final bool secret;
}

/// Definitions belong to one namespace. Extensions cannot replace host entries.
/// Package installation/grants remain the plugin host's responsibility.
class SettingsRegistry {
  final _definitions = <String, RegisteredSetting>{};
  final _owners = <String, String>{};
  Iterable<RegisteredSetting> get definitions =>
      List.unmodifiable(_definitions.values);
  void register(String owner, Iterable<RegisteredSetting> definitions) {
    if (!RegExp(r'^[a-z][a-z0-9_.-]{0,79}$').hasMatch(owner)) {
      throw ArgumentError('Invalid settings owner');
    }
    final batch = definitions.toList();
    final keys = <String>{};
    for (final definition in batch) {
      if (!definition.key.startsWith('$owner.') ||
          !RegExp(r'^[a-z][a-zA-Z0-9_.-]{0,159}$').hasMatch(definition.key) ||
          definition.label.trim().isEmpty ||
          definition.scopes.isEmpty ||
          !definition.accepts(definition.defaultValue) ||
          !keys.add(definition.key) ||
          _definitions.containsKey(definition.key)) {
        throw ArgumentError('Invalid or duplicate settings definition');
      }
    }
    for (final definition in batch) {
      _definitions[definition.key] = definition;
      _owners[definition.key] = owner;
    }
  }

  RegisteredSetting definition(String key) =>
      _definitions[key] ?? (throw ArgumentError('Unknown setting: $key'));

  void validate(String key, Object value, RegisteredSettingScope scope) {
    final entry = definition(key);
    if (!entry.scopes.contains(scope) || !entry.accepts(value)) {
      throw ArgumentError('Invalid setting value or scope: $key');
    }
  }

  void unregister(String owner) {
    if (owner == 'host') throw StateError('Host settings cannot be removed');
    final keys = _owners.keys.where((key) => _owners[key] == owner).toList();
    for (final key in keys) {
      _owners.remove(key);
      _definitions.remove(key);
    }
  }
}

class SettingAddress {
  SettingAddress(this.scope, {this.collection = '', this.entity = ''}) {
    if (scope == RegisteredSettingScope.app &&
            (collection.isNotEmpty || entity.isNotEmpty) ||
        scope != RegisteredSettingScope.app && collection.isEmpty ||
        (scope == RegisteredSettingScope.title ||
                scope == RegisteredSettingScope.group) &&
            entity.isEmpty ||
        scope == RegisteredSettingScope.collection && entity.isNotEmpty) {
      throw ArgumentError('Invalid settings scope identity');
    }
  }
  final RegisteredSettingScope scope;
  final String collection, entity;
}

abstract interface class RegisteredSettingsStore {
  Future<Object?> read(
    SettingAddress address,
    String key, {
    required bool secret,
  });
  Future<void> write(
    SettingAddress address,
    String key,
    Object? value, {
    required bool secret,
  });
}

class EffectiveRegisteredSetting {
  const EffectiveRegisteredSetting(this.value, this.source);
  final Object value;

  /// Null denotes the registered package/host default.
  final SettingAddress? source;
}

class RegisteredSettings {
  const RegisteredSettings(
    this.registry,
    this.store, {
    required this.authorized,
  });
  final SettingsRegistry registry;
  final RegisteredSettingsStore store;
  final bool Function(SettingAddress) authorized;
  void _access(SettingAddress address) {
    if (!authorized(address)) throw StateError('Settings scope is unavailable');
  }

  Future<void> set(SettingAddress address, String key, Object value) async {
    _access(address);
    registry.validate(key, value, address.scope);
    await store.write(
      address,
      key,
      value,
      secret: registry.definition(key).secret,
    );
  }

  Future<void> reset(SettingAddress address, String key) async {
    _access(address);
    final entry = registry.definition(key);
    if (!entry.scopes.contains(address.scope)) {
      throw ArgumentError('Invalid scope');
    }
    await store.write(address, key, null, secret: entry.secret);
  }

  Future<EffectiveRegisteredSetting> resolve(
    String key,
    List<SettingAddress> lineage,
  ) async {
    final entry = registry.definition(key);
    var resolved = EffectiveRegisteredSetting(entry.defaultValue, null);
    // Callers supply an app -> collection -> group -> title lineage.
    var previous = -1;
    String? collection;
    for (final address in lineage) {
      if (address.scope.index <= previous ||
          address.scope != RegisteredSettingScope.app &&
              collection != null &&
              address.collection != collection) {
        throw ArgumentError('Invalid settings inheritance lineage');
      }
      previous = address.scope.index;
      if (address.scope != RegisteredSettingScope.app) {
        collection = address.collection;
      }
      _access(address);
      if (!entry.scopes.contains(address.scope)) continue;
      final value = await store.read(address, key, secret: entry.secret);
      _access(address);
      if (value != null) {
        registry.validate(key, value, address.scope);
        resolved = EffectiveRegisteredSetting(value, address);
      }
    }
    for (final address in lineage) {
      _access(address);
    }
    return resolved;
  }
}
