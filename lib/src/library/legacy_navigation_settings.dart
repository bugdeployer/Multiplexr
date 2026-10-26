import '../features/settings/application/navigation_preferences.dart';
import '../core/persistence/state_repository.dart';

import 'library_models.dart';

class LegacyNavigationSettings implements NavigationSettingsStore {
  LegacyNavigationSettings(StateStore store, {required this.load})
    : state = JsonStateRepository(store);
  final Future<Map<String, dynamic>> Function() load;
  final JsonStateRepository state;
  @override
  Future<VideoCollection?> collection(String id) async {
    final data = await load();
    final row = (data['collections'] as List? ?? [])
        .whereType<Map>()
        .where((c) => c['id'] == id)
        .firstOrNull;
    return row == null
        ? null
        : VideoCollection.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<Map<String, dynamic>?> read(String key) => state.read(key);
  @override
  Future<void> merge(String key, Map<String, dynamic> values) =>
      state.update(key, (current) async => {...?current, ...values});
}
