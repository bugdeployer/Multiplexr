import 'package:multiplexr/src/features/settings/application/host_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/settings/application/settings_registry.dart';

class SettingsMemory implements RegisteredSettingsStore {
  final values = <String, Object>{};
  bool? lastSecret;
  String key(SettingAddress a, String id) =>
      '${a.scope}:${a.collection}:${a.entity}:$id';
  @override
  Future<Object?> read(
    SettingAddress a,
    String id, {
    required bool secret,
  }) async => values[key(a, id)];
  @override
  Future<void> write(
    SettingAddress a,
    String id,
    Object? value, {
    required bool secret,
  }) async {
    lastSecret = secret;
    if (value == null) {
      values.remove(key(a, id));
    } else {
      values[key(a, id)] = value;
    }
  }
}

RegisteredSetting definition(String key, {bool secret = false}) =>
    RegisteredSetting(
      key: key,
      label: 'Example',
      defaultValue: 10,
      scopes: RegisteredSettingScope.values.toSet(),
      secret: secret,
      accepts: (v) => v is int && v >= 0 && v <= 100,
    );

void main() {
  test(
    'host registry covers valid defaults and rejects foreign values and scopes',
    () {
      for (final definition in HostSettings.registry.definitions) {
        for (final scope in definition.scopes) {
          HostSettings.registry.validate(
            definition.key,
            definition.defaultValue,
            scope,
          );
        }
      }
      HostSettings.validate('notification', {
        'completed': true,
        'errors': false,
        'activity': true,
      });
      expect(
        () => HostSettings.validate('notification', {'alerts': true}),
        throwsArgumentError,
      );
      expect(
        () => HostSettings.validate('app', {'lockDelay': 7}),
        throwsArgumentError,
      );
      expect(
        () => HostSettings.validate('app', {'dark': 'true'}),
        throwsArgumentError,
      );
      expect(
        () => HostSettings.validate('player.video', {'backSeconds': 7}),
        throwsArgumentError,
      );
      expect(
        () => HostSettings.validate('collection', {'cardSize': 180}),
        throwsArgumentError,
      );
    },
  );

  test(
    'registration is atomic, namespaced and cannot replace host definitions',
    () {
      final registry = SettingsRegistry()
        ..register('host', [definition('host.size')]);
      expect(
        () => registry.register('example', [
          definition('example.valid'),
          definition('host.size'),
        ]),
        throwsArgumentError,
      );
      expect(() => registry.definition('example.valid'), throwsArgumentError);
      registry.register('example', [definition('example.size')]);
      expect(
        () => registry.register('example', [definition('example.size')]),
        throwsArgumentError,
      );
      registry.unregister('example');
      expect(() => registry.definition('example.size'), throwsArgumentError);
      expect(() => registry.unregister('host'), throwsStateError);
      expect(registry.definition('host.size').defaultValue, 10);
    },
  );
  test(
    'scope inheritance exposes provenance and reset reveals parent value',
    () async {
      final registry = SettingsRegistry()
        ..register('host', [definition('host.size')]);
      final values = RegisteredSettings(
        registry,
        SettingsMemory(),
        authorized: (_) => true,
      );
      final app = SettingAddress(RegisteredSettingScope.app);
      final collection = SettingAddress(
        RegisteredSettingScope.collection,
        collection: 'books',
      );
      final title = SettingAddress(
        RegisteredSettingScope.title,
        collection: 'books',
        entity: 'one',
      );
      await values.set(app, 'host.size', 20);
      await values.set(title, 'host.size', 30);
      var effective = await values.resolve('host.size', [
        app,
        collection,
        title,
      ]);
      expect(effective.value, 30);
      expect(effective.source, same(title));
      await values.reset(title, 'host.size');
      effective = await values.resolve('host.size', [app, collection, title]);
      expect(effective.value, 20);
      expect(effective.source, same(app));
      await expectLater(
        values.set(title, 'host.size', 101),
        throwsArgumentError,
      );
      await expectLater(
        values.resolve('host.size', [title, app]),
        throwsArgumentError,
      );
    },
  );
  test(
    'unauthorized scopes never reach storage; secret routing stays explicit',
    () async {
      final registry = SettingsRegistry()
        ..register('example', [definition('example.token', secret: true)]);
      final store = SettingsMemory();
      var allowed = false;
      final values = RegisteredSettings(
        registry,
        store,
        authorized: (_) => allowed,
      );
      final address = SettingAddress(RegisteredSettingScope.app);
      await expectLater(
        values.set(address, 'example.token', 50),
        throwsStateError,
      );
      expect(store.values, isEmpty);
      allowed = true;
      await values.set(address, 'example.token', 50);
      expect(store.lastSecret, isTrue);
      await values.reset(address, 'example.token');
      expect(store.lastSecret, isTrue);
      expect(store.values, isEmpty);
    },
  );
}
