import 'settings_registry.dart';
import 'host_settings.dart';

enum PlayerKind { video, music, audiobooks }

class PlayerOptions {
  const PlayerOptions({
    required this.backSeconds,
    required this.forwardSeconds,
    this.shuffle = false,
    this.repeat = '',
  });
  final int backSeconds, forwardSeconds;
  final bool shuffle;
  final String repeat;
  static const intervals = [5, 10, 15, 20, 30, 60];
  factory PlayerOptions.decode(PlayerKind kind, Map<String, dynamic>? value) {
    int interval(String key, int fallback) =>
        intervals.contains(value?[key]) ? value![key] as int : fallback;
    return PlayerOptions(
      backSeconds: interval(
        'backSeconds',
        kind == PlayerKind.audiobooks ? 15 : 10,
      ),
      forwardSeconds: interval(
        'forwardSeconds',
        kind == PlayerKind.audiobooks ? 30 : 10,
      ),
      shuffle: value?['shuffle'] == true,
      repeat: {'off', 'all', 'one'}.contains(value?['repeat'])
          ? value!['repeat'] as String
          : '',
    );
  }
  Map<String, dynamic> toJson() => {
    'backSeconds': backSeconds,
    'forwardSeconds': forwardSeconds,
    'shuffle': shuffle,
    'repeat': repeat,
  };
}

abstract interface class PlayerPreferenceStore {
  Future<Map<String, dynamic>?> read(PlayerKind kind);
  Future<void> write(PlayerKind kind, Map<String, dynamic>? value);
}

class PlayerPreferences {
  const PlayerPreferences(this.store);
  final PlayerPreferenceStore store;
  static final registry = HostSettings.registry;
  Future<PlayerOptions> load(PlayerKind kind) async =>
      PlayerOptions.decode(kind, await store.read(kind));
  Future<PlayerOptions> loadForPlayback(PlayerKind kind) async {
    try {
      return await load(kind);
    } catch (_) {
      return PlayerOptions.decode(kind, null);
    }
  }

  Future<void> save(PlayerKind kind, PlayerOptions value) async {
    for (final entry in value.toJson().entries) {
      registry.validate(
        'host.player.${kind.name}.${entry.key}',
        entry.value,
        RegisteredSettingScope.app,
      );
    }
    await store.write(kind, value.toJson());
  }

  Future<void> reset(PlayerKind kind) => store.write(kind, null);
}
