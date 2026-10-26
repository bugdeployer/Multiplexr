import '../features/metadata/application/publication_provider.dart';
import 'contracts.dart';

import 'package:flutter/foundation.dart';

import '../features/playback/application/music_queue.dart';
export '../features/playback/application/music_queue.dart'
    show MusicQueueSnapshot;
import '../features/playback/application/music_session_store.dart';
import '../features/settings/application/player_preferences.dart';
import '../library/library_models.dart';
import '../library/library_controller.dart';
import 'audio_player.dart';
import 'music_repository.dart';
import 'music_metadata_job.dart';

/// Flutter presenter for the app-owned music queue and metadata job projection.
class MusicPlayback extends ChangeNotifier with MusicQueueApplication {
  MusicPlayback({
    required this.library,
    required this.audio,
    required this.metadataJobFactory,
    required this.repository,
    required this.sessionStore,
    required this.metadataProvider,
    // Public assembly option maps to private lifetime ownership.
    bool disposeAudio = false,
    // ignore: prefer_initializing_formals
  }) : _disposeAudio = disposeAudio {
    audio.addListener(audioChanged);
    library.addListener(_accessChanged);
  }
  final LibraryController library;
  final bool _disposeAudio;
  @override
  final MusicRepository repository;
  @override
  final AudioController audio;
  @override
  final MusicSessionStore sessionStore;
  @override
  PlayerPreferences get playerPreferences => library.playerPreferences;
  @override
  List<VideoCollection> get collections => library.collections;
  @override
  bool authorized(String id) => library.canAccessCollection(id);
  Future<bool> canResume(Iterable<MediaId> available) async {
    final ids = available.toSet();
    final saved = await sessionStore.read();
    return (saved?['entries'] as List? ?? []).any(
      (entry) => ids.contains(
        MediaId.fromJson(Map<String, dynamic>.from(entry['owner'])),
      ),
    );
  }

  final MusicProvider metadataProvider;
  final MusicMetadataJob Function(String) metadataJobFactory;
  final _jobs = <String, MusicMetadataJob>{};
  bool get metadataRunning => _jobs.values.any((job) => job.running);
  MusicMetadataJob jobFor(String id) => _jobs.putIfAbsent(id, () {
    library.service.maintenance.checkAdmission();
    final job = metadataJobFactory(id);
    job.addListener(library.notifyListeners);
    return job;
  });
  void _accessChanged() {
    for (final entry in _jobs.entries) {
      if (entry.value.running &&
          !entry.value.cancellation.cancelled &&
          (!collections.any((c) => c.id == entry.key) ||
              !authorized(entry.key))) {
        entry.value.cancel();
      }
    }
    accessChanged();
  }

  @override
  void dispose() {
    disposeSession();
    for (final job in _jobs.values) {
      job.dispose();
    }
    library.removeListener(_accessChanged);
    audio.removeListener(audioChanged);
    if (_disposeAudio) audio.dispose();
    super.dispose();
  }
}
