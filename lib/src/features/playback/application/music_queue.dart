import 'dart:math';

import '../../../library/library_models.dart';
import '../../../media/music_catalog_models.dart';
import '../../../media/audio_session.dart';
import '../../../media/contracts.dart';
import '../../../media/video_projections.dart';
import '../../catalog/application/space_queries.dart';
import '../../catalog/application/music_catalog_commands.dart';
import '../../settings/application/player_preferences.dart';
import 'audio_playback_models.dart';
import 'music_session_store.dart';
import 'audio_commands.dart';

abstract interface class MusicAudioPort {
  AudioState get state;
  Future<void> openMusic(
    AudioSession session, {
    String? collectionId,
    bool autoplay = true,
  });
  Future<void> execute(AudioCommand command);
  Future<void> refresh();
  void observe();
}

/// Framework-free queue application. The presenter supplies change notifications;
/// the audio adapter remains the sole native playback and durable queue owner.
mixin MusicQueueApplication {
  MusicAudioPort get audio;
  MusicCatalogCommands get repository;
  MusicSessionStore get sessionStore;
  PlayerPreferences get playerPreferences;
  List<VideoCollection> get collections;
  bool authorized(String collectionId);
  void notifyListeners();
  Future<void> _tail = Future.value();
  Future<T> serialize<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  bool sameOrder(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);
  List<MusicTrack> _tracks = [];
  List<AudioSessionEntry> _entries = [];
  List<String> _traversal = [];
  String? _collectionId;
  bool shuffled = false;
  AudioRepeatMode repeat = AudioRepeatMode.off;
  int _sequence = 0;
  int _revision = 0;
  bool _disposed = false;
  void audioChanged() {
    final mode = audio.state.data['repeat'];
    if (audio.state.id?.kind == MediaKind.music && mode is String) {
      repeat = AudioRepeatMode.values.byName(mode);
    }
    notifyListeners();
  }

  Future<T> _mutation<T>(Future<T> Function() change) => serialize(() async {
    if (_disposed) throw StateError('Music playback was closed.');
    final tracks = [..._tracks],
        entries = [..._entries],
        order = [..._traversal];
    final scope = _collectionId, wasShuffled = shuffled, oldRepeat = repeat;
    try {
      return await change();
    } catch (_) {
      _tracks = tracks;
      _entries = entries;
      _traversal = order;
      _collectionId = scope;
      shuffled = wasShuffled;
      repeat = oldRepeat;
      if (!_disposed) notifyListeners();
      rethrow;
    }
  });
  List<AudioSessionEntry> get visibleEntries => List.unmodifiable(
    _entries.where(
      (entry) =>
          _tracks.any((track) => track.id == entry.owner && permitted(track)),
    ),
  );
  List<MusicTrack> get queue => List.unmodifiable(
    visibleEntries.map(
      (entry) => _tracks.firstWhere((track) => track.id == entry.owner),
    ),
  );
  String? get currentEntryId {
    final index = audio.state.index;
    return index >= 0 && index < _traversal.length ? _traversal[index] : null;
  }

  MusicTrack? get current =>
      _tracks.where((t) => t.id == audio.state.id && permitted(t)).firstOrNull;
  bool permitted(MusicTrack track) {
    final collection = collections
        .where((c) => c.id == track.id.collectionId)
        .firstOrNull;
    return track.available &&
        collection != null &&
        SpaceScope(MediaSubtype.music, collectionId: _collectionId).includes(
          collection.catalogCollection,
          authorized: authorized(collection.id),
        );
  }

  AudioSessionEntry _entry(MusicTrack track) => AudioSessionEntry(
    entryId: '${DateTime.now().microsecondsSinceEpoch}:${_sequence++}',
    owner: track.id,
    sourceId: track.source.id,
    uri: track.source.uri,
    title: track.metadata.title,
    creator: track.metadata.artist,
    album: track.metadata.album,
    artwork: track.metadata.cover,
  );

  Future<void> play(
    List<MusicTrack> tracks, {
    required MediaId start,
    String? collectionId,
    bool? shuffle,
    int? startIndex,
  }) => _mutation(
    () => _play(
      tracks,
      start: start,
      collectionId: collectionId,
      shuffle: shuffle,
      startIndex: startIndex,
    ),
  );
  Future<void> _play(
    List<MusicTrack> tracks, {
    required MediaId start,
    String? collectionId,
    bool? shuffle,
    int? startIndex,
  }) async {
    final preferences = await playerPreferences.loadForPlayback(
      PlayerKind.music,
    );
    final useShuffle = shuffle ?? preferences.shuffle;
    if (preferences.repeat.isNotEmpty) {
      repeat = AudioRepeatMode.values.byName(preferences.repeat);
    }
    _collectionId = collectionId;
    final eligible = tracks.where(permitted).toList();
    if (!eligible.any((track) => track.id == start)) {
      throw StateError(
        'Track is unavailable or collection access is required.',
      );
    }
    final resolved = await repository.tracks(
      SpaceScope(MediaSubtype.music, collectionId: collectionId),
    );
    final byId = {for (final t in resolved) t.id: t};
    _tracks = eligible.map((t) => byId[t.id] ?? t).toList();
    _entries = _tracks.map(_entry).toList();
    final occurrence =
        startIndex != null &&
            startIndex >= 0 &&
            startIndex < eligible.length &&
            eligible[startIndex].id == start
        ? startIndex
        : eligible.indexWhere((t) => t.id == start);
    final first = _entries[occurrence].entryId;
    shuffled = useShuffle;
    _traversal = _entries.map((entry) => entry.entryId).toList();
    if (useShuffle) {
      _traversal.remove(first);
      _traversal.shuffle(Random());
      _traversal.insert(0, first);
    }
    await _open(first, 0);
  }

  Future<void> _open(
    String entryId,
    int positionMs, {
    bool autoplay = true,
  }) async {
    final revision = ++_revision;
    if (_entries.isEmpty ||
        _entries.any(
          (entry) => !_tracks.any(
            (track) => track.id == entry.owner && permitted(track),
          ),
        )) {
      throw StateError('The queue contains unavailable tracks.');
    }
    await audio.openMusic(
      AudioSession(
        mode: AudioSessionMode.music,
        entries: _entries,
        currentEntryId: entryId,
        traversal: _traversal,
        positionMs: positionMs,
        repeat: repeat,
        shuffled: shuffled,
      ),
      collectionId: _collectionId,
      autoplay: autoplay,
    );
    if (!_disposed && revision == _revision) notifyListeners();
  }

  Future<void> refreshMetadata() => _mutation(() async {
    final current = currentEntryId;
    if (current == null || audio.state.id?.kind != MediaKind.music) return;
    final fresh = await repository.tracks(
      SpaceScope(MediaSubtype.music, collectionId: _collectionId),
    );
    final byId = {for (final t in fresh) t.id: t};
    final next = [
      for (final e in _entries)
        if (byId[e.owner] case final MusicTrack track)
          AudioSessionEntry(
            entryId: e.entryId,
            owner: e.owner,
            sourceId: track.source.id,
            uri: track.source.uri,
            title: track.metadata.title,
            creator: track.metadata.artist,
            album: track.metadata.album,
            artwork: track.metadata.cover,
          )
        else
          e,
    ];
    var changed = false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].title != _entries[i].title ||
          next[i].creator != _entries[i].creator ||
          next[i].album != _entries[i].album ||
          next[i].artwork != _entries[i].artwork) {
        changed = true;
      }
    }
    if (!changed) return;
    _tracks = [for (final t in _tracks) byId[t.id] ?? t];
    _entries = next;
    await _open(current, audio.state.positionMs, autoplay: audio.state.playing);
  });
  Future<void> setShuffle(bool value) => _mutation(() => _setShuffle(value));
  Future<void> _setShuffle(bool value) async {
    final current = currentEntryId;
    if (current == null) return;
    shuffled = value;
    _traversal = _entries.map((e) => e.entryId).toList();
    if (value) {
      _traversal.remove(current);
      _traversal.shuffle(Random());
      _traversal.insert(0, current);
    }
    await _open(current, audio.state.positionMs, autoplay: audio.state.playing);
  }

  Future<void> setRepeat(AudioRepeatMode value) async {
    await audio.execute(AudioCommand.repeat(value));
    if (_disposed) return;
    repeat = value;
    notifyListeners();
  }

  Future<void> enqueue(MusicTrack track, {bool next = false}) =>
      _mutation(() => _enqueue(track, next: next));
  Future<void> _enqueue(MusicTrack track, {bool next = false}) async {
    if (!permitted(track)) {
      throw StateError('Track is not eligible for this queue.');
    }
    final current = currentEntryId;
    if (current == null) {
      return _play([track], start: track.id, collectionId: _collectionId);
    }
    if (!_tracks.any((t) => t.id == track.id)) _tracks.add(track);
    final entry = _entry(track);
    if (next) {
      _entries.insert(
        _entries.indexWhere((e) => e.entryId == current) + 1,
        entry,
      );
    } else {
      _entries.add(entry);
    }
    final index = next ? _traversal.indexOf(current) + 1 : _traversal.length;
    _traversal.insert(index, entry.entryId);
    await _open(current, audio.state.positionMs, autoplay: audio.state.playing);
  }

  Future<void> selectEntry(int visibleIndex) => audio.execute(
    AudioCommand.chapter(
      _traversal.indexOf(visibleEntries[visibleIndex].entryId),
    ),
  );

  MusicQueueSnapshot captureQueue() => MusicQueueSnapshot(
    [..._tracks],
    [..._entries],
    [..._traversal],
    _collectionId,
    currentEntryId,
    audio.state.positionMs,
    audio.state.playing,
    shuffled,
    repeat,
  );
  Future<void> restoreQueue(MusicQueueSnapshot saved) => _mutation(() async {
    _tracks = saved.tracks;
    _entries = [...saved.entries];
    _traversal = [...saved.order];
    _collectionId = saved.scope;
    shuffled = saved.shuffled;
    repeat = saved.repeat;
    if (saved.current != null && _entries.isNotEmpty) {
      await _open(saved.current!, saved.position, autoplay: saved.playing);
    }
  });
  Future<void> clearQueue() => _mutation(_clearQueue);
  Future<void> _clearQueue() async {
    await audio.execute(const AudioCommand.action(AudioAction.clearQueue));
    await sessionStore.clear();
    _entries = [];
    _tracks = [];
    _traversal = [];
    notifyListeners();
  }

  Future<void> removeEntry(String id) => _mutation(() async {
    final current = currentEntryId;
    final nextIndex = _traversal.indexOf(id);
    _entries.removeWhere((e) => e.entryId == id);
    _traversal.remove(id);
    if (_entries.isEmpty) {
      await _clearQueue();
      return;
    }
    final selected = current == id
        ? _traversal[nextIndex.clamp(0, _traversal.length - 1)]
        : current!;
    await _open(
      selected,
      current == id ? 0 : audio.state.positionMs,
      autoplay: audio.state.playing,
    );
  });
  Future<void> reorderEntry(int oldIndex, int newIndex) => _mutation(() async {
    final current = currentEntryId;
    final visible = [...visibleEntries];
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);
    final eligibleIds = visible.map((e) => e.entryId).toSet();
    var offset = 0;
    _entries = [
      for (final e in _entries)
        eligibleIds.contains(e.entryId) ? visible[offset++] : e,
    ];
    if (!shuffled) _traversal = _entries.map((e) => e.entryId).toList();
    if (current != null) {
      await _open(
        current,
        audio.state.positionMs,
        autoplay: audio.state.playing,
      );
    }
  });
  Future<void> moveNext(String id) => _mutation(() async {
    final current = currentEntryId;
    if (current == null || current == id) return;
    _traversal.remove(id);
    _traversal.insert(_traversal.indexOf(current) + 1, id);
    final entry = _entries.firstWhere((e) => e.entryId == id);
    _entries.remove(entry);
    _entries.insert(
      _entries.indexWhere((e) => e.entryId == current) + 1,
      entry,
    );
    await _open(current, audio.state.positionMs, autoplay: audio.state.playing);
  });

  Future<bool> restore({SpaceScope? scope}) => _mutation(() async {
    final previous = captureQueue();
    final restored = await _restore(scope: scope);
    if (!restored) {
      _tracks = previous.tracks;
      _entries = previous.entries;
      _traversal = previous.order;
      _collectionId = previous.scope;
      shuffled = previous.shuffled;
      repeat = previous.repeat;
    }
    return restored;
  });
  Future<void> attach() => _mutation(() async {
    await audio.refresh();
    if (_disposed) return;
    if (audio.state.id?.kind == MediaKind.music) await _restore(open: false);
    audio.observe();
  });

  Future<bool> _restore({bool open = true, SpaceScope? scope}) async {
    final saved = await sessionStore.read();
    if (saved == null) return false;
    if (saved['version'] != 1) {
      throw const FormatException('Unsupported Music session.');
    }
    _collectionId = scope != null
        ? scope.collectionId
        : (saved['scopeCollectionId'] as String).isEmpty
        ? null
        : saved['scopeCollectionId'];
    _tracks = (await repository.tracks(
      SpaceScope(MediaSubtype.music, collectionId: _collectionId),
    )).where(permitted).toList();
    _entries = [];
    for (final raw in saved['entries'] as List) {
      final id = MediaId.fromJson(Map<String, dynamic>.from(raw['owner']));
      final track = _tracks.where((t) => t.id == id).firstOrNull;
      if (track == null) continue;
      _entries.add(
        AudioSessionEntry(
          entryId: raw['entryId'],
          owner: id,
          sourceId: track.source.id,
          uri: track.source.uri,
          title: track.metadata.title,
          creator: track.metadata.artist,
          album: track.metadata.album,
          artwork: track.metadata.cover,
        ),
      );
    }
    if (_entries.isEmpty) return false;
    final ids = _entries.map((e) => e.entryId).toSet();
    _traversal = List<String>.from(saved['traversal'])
        .where(ids.contains)
        .toList();
    if (_traversal.toSet().length != ids.length ||
        _traversal.length != ids.length) {
      throw const FormatException('Invalid Music traversal.');
    }
    shuffled =
        saved['shuffled'] == true ||
        !sameOrder(_traversal, _entries.map((e) => e.entryId).toList());
    final id = saved['currentEntryId'] as String;
    final resume = _traversal.contains(id);
    repeat = AudioRepeatMode.values.byName(saved['repeat']);
    if (open) {
      await _open(
        resume ? id : _traversal.first,
        resume ? saved['positionMs'] as int : 0,
        autoplay: false,
      );
    }
    return true;
  }

  void accessChanged() {
    final id = audio.state.id;
    if (id != null && _tracks.any((t) => t.id == id && !permitted(t))) {
      audio
          .execute(const AudioCommand.action(AudioAction.pause))
          .catchError((Object _) {});
    }
    notifyListeners();
  }

  void disposeSession() {
    _disposed = true;
    _revision++;
  }
}

class MusicQueueSnapshot {
  MusicQueueSnapshot(
    this.tracks,
    this.entries,
    this.order,
    this.scope,
    this.current,
    this.position,
    this.playing,
    this.shuffled,
    this.repeat,
  );
  final List<MusicTrack> tracks;
  final List<AudioSessionEntry> entries;
  final List<String> order;
  final String? scope, current;
  final int position;
  final bool playing, shuffled;
  final AudioRepeatMode repeat;
}
