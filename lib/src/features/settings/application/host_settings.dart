import 'dart:convert';

import '../../../catalog/domain/classification.dart';
import '../../../reading/domain/reader_settings.dart';
import '../../../settings/domain/collection_settings_schema.dart';
import 'settings_registry.dart';

/// Single catalogue of host-owned settings. Persistence adapters map these IDs
/// to their existing durable stores; plugins cannot replace or write host IDs.
abstract final class HostSettings {
  static final registry = SettingsRegistry()..register('host', definitions);
  static Iterable<RegisteredSetting> get definitions sync* {
    for (final key in [
      'dark',
      'followSystem',
      'compact',
      'reduceMotion',
      'pixel',
      'lockEnabled',
      'useBiometrics',
      'hidePreviews',
      'protectScreen',
      'notifications',
    ]) {
      yield RegisteredSetting(
        key: 'host.app.$key',
        label: key,
        defaultValue: {
          'dark',
          'pixel',
          'useBiometrics',
          'hidePreviews',
          'protectScreen',
        }.contains(key),
        accepts: (v) => v is bool,
      );
    }
    for (final key in ['darkBase', 'darkAccent', 'lightBase', 'lightAccent']) {
      yield RegisteredSetting(
        key: 'host.app.$key',
        label: key,
        defaultValue: {
          'darkBase': 1,
          'darkAccent': 1,
          'lightBase': 0,
          'lightAccent': 7,
        }[key]!,
        accepts: (v) => v is int && v >= 0 && v <= 10000,
      );
    }
    for (final key in ['libraryView', 'spacesView']) {
      yield RegisteredSetting(
        key: 'host.app.$key',
        label: key,
        defaultValue: 0,
        accepts: (v) => v is int && v >= 0 && v <= 2,
      );
    }
    yield RegisteredSetting(
      key: 'host.app.lockDelay',
      label: 'Lock delay',
      defaultValue: 0,
      accepts: (v) => v is int && {0, 30, 60, 300}.contains(v),
    );
    yield RegisteredSetting(
      key: 'host.app.themeState',
      label: 'Theme packages',
      defaultValue: '',
      accepts: (v) => v is String && utf8.encode(v).length <= 16 * 1024 * 1024,
    );
    for (final key in ['completed', 'errors', 'activity']) {
      yield RegisteredSetting(
        key: 'host.notification.$key',
        label: key,
        defaultValue: true,
        accepts: (v) => v is bool,
      );
    }
    for (final kind in ['video', 'music', 'audiobooks']) {
      for (final direction in ['backSeconds', 'forwardSeconds']) {
        yield RegisteredSetting(
          key: 'host.player.$kind.$direction',
          label: direction,
          defaultValue: kind == 'audiobooks'
              ? (direction == 'backSeconds' ? 15 : 30)
              : 10,
          accepts: (v) => v is int && {5, 10, 15, 20, 30, 60}.contains(v),
        );
      }
      yield RegisteredSetting(
        key: 'host.player.$kind.shuffle',
        label: 'Shuffle',
        defaultValue: false,
        accepts: (v) => v is bool,
      );
      yield RegisteredSetting(
        key: 'host.player.$kind.repeat',
        label: 'Repeat',
        defaultValue: '',
        accepts: (v) => {'', 'off', 'all', 'one'}.contains(v),
      );
    }
    for (final subtype in [MediaSubtype.ebook, MediaSubtype.comics]) {
      for (final definition in ReaderSettings.definitions(subtype)) {
        yield RegisteredSetting(
          key: 'host.reader.${subtype.name}.${definition.id}',
          label: definition.id,
          defaultValue: definition.defaultValue,
          scopes: definition.scopes
              .map((s) => RegisteredSettingScope.values.byName(s.name))
              .toSet(),
          accepts: definition.accepts,
        );
      }
    }
    for (final definition in CollectionSettingsSchema.fields.where(
      (f) => f.owner == CollectionFieldOwner.settings,
    )) {
      yield RegisteredSetting(
        key: 'host.collection.${definition.id}',
        label: definition.label,
        defaultValue: definition.defaultValue!,
        scopes: definition.scopes
            .map((s) => RegisteredSettingScope.values.byName(s.name))
            .toSet(),
        accepts: definition.accepts,
      );
    }
    for (final key in ['openAction', 'rate']) {
      yield RegisteredSetting(
        key: 'host.navigation.$key',
        label: key,
        defaultValue: key == 'rate' ? 0.0 : 'automatic',
        scopes: RegisteredSettingScope.values.toSet(),
        accepts: (v) => key == 'rate'
            ? v is num && v.isFinite && (v == 0 || v >= .5 && v <= 3)
            : {'automatic', 'details', 'play'}.contains(v),
      );
    }
  }

  static void validate(
    String namespace,
    Map<String, dynamic> values, {
    RegisteredSettingScope scope = RegisteredSettingScope.app,
  }) {
    for (final entry in values.entries) {
      if (entry.value == null) {
        throw ArgumentError('Setting value cannot be null');
      }
      registry.validate(
        'host.$namespace.${entry.key}',
        entry.value as Object,
        scope,
      );
    }
  }
}
