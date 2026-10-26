import '../features/settings/application/player_preferences.dart';
import '../core/persistence/state_repository.dart';
import 'library_service.dart';

class LegacyPlayerPreferenceStore implements PlayerPreferenceStore {
  LegacyPlayerPreferenceStore(this.service);
  final LibraryService service;
  static const key = 'settings:players:v1';
  @override
  Future<Map<String, dynamic>?> read(PlayerKind kind) async {
    final state = await service.readState(key);
    if (state != null && state['version'] != 1) {
      throw const FormatException('Unsupported player settings');
    }
    final value = state?[kind.name];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<void> write(PlayerKind kind, Map<String, dynamic>? value) =>
      JsonStateRepository(service).update(key, (state) async {
        if (state != null && state['version'] != 1) {
          throw const FormatException('Unsupported player settings');
        }
        final next = <String, dynamic>{...?state, 'version': 1};
        if (value == null) {
          next.remove(kind.name);
        } else {
          next[kind.name] = value;
        }
        return next;
      });
}
