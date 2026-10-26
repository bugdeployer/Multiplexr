abstract interface class AudiobookCatalogStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<T> mutate<T>(Future<T> Function() change);
}
