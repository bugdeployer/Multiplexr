/// Native audio owns the durable queue; restore never implies autoplay.
abstract interface class MusicSessionStore {
  Future<Map<String, dynamic>?> read();
  Future<void> clear();
}
