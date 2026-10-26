/// Local presentation preferences. Storage keys and merge transactions are
/// implementation details; these values never authorize media access.
abstract interface class UserPreferencesHost {
  UserPreferences get userPreferences;
}

abstract interface class UserPreferences {
  Future<Map<String, dynamic>?> browsing(String route, String? collection);
  Future<void> saveBrowsing(
    String route,
    String? collection,
    Map<String, dynamic> value,
  );
  Future<Map<String, dynamic>?> spaces();
  Future<void> mergeSpaces(Map<String, dynamic> values);
}
