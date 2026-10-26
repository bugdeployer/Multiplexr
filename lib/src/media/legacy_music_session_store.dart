import '../features/playback/application/music_session_store.dart';
import '../library/library_service.dart';

class LegacyMusicSessionStore implements MusicSessionStore {
  const LegacyMusicSessionStore(this.service);
  final LibraryService service;
  @override
  Future<Map<String, dynamic>?> read() => service.readState('music:session');
  @override
  Future<void> clear() => service.writeState('music:session', null);
}
