import 'dart:convert';

import '../../features/settings/application/user_preferences.dart';
import 'state_repository.dart';

class LocalUserPreferences implements UserPreferences {
  const LocalUserPreferences(this.store);
  final StateStore store;
  String _browseKey(String route, String? collection) =>
      'ui:browse:${jsonEncode([route, collection])}';
  @override
  Future<Map<String, dynamic>?> browsing(String route, String? collection) =>
      store.readState(_browseKey(route, collection));
  @override
  Future<void> saveBrowsing(
    String route,
    String? collection,
    Map<String, dynamic> value,
  ) =>
      JsonStateRepository(store)
          .update(_browseKey(route, collection), (_) async => value);
  @override
  Future<Map<String, dynamic>?> spaces() => store.readState('spaces:display');
  @override
  Future<void> mergeSpaces(Map<String, dynamic> values) =>
      JsonStateRepository(store)
          .update('spaces:display', (old) async => {...?old, ...values});
}
