import 'contracts.dart';

enum AudioSessionMode { audiobook, music }

enum AudioRepeatMode { off, all, one }

/// Identity of an occurrence in a queue is distinct from the progress owner.
class AudioSessionEntry {
  AudioSessionEntry({
    required this.entryId,
    required this.owner,
    required this.sourceId,
    required this.uri,
    required this.title,
    this.creator = '',
    this.artwork = '',
    this.album = '',
    this.startMs = 0,
    this.endMs,
  }) {
    if (entryId.trim().isEmpty ||
        sourceId.trim().isEmpty ||
        uri.trim().isEmpty ||
        owner.collectionId.trim().isEmpty ||
        owner.itemId.trim().isEmpty ||
        owner.kind == MediaKind.video ||
        startMs < 0 ||
        (endMs != null && endMs! <= startMs)) {
      throw ArgumentError('Invalid audio session entry.');
    }
  }
  final String entryId, sourceId, uri, title, creator, artwork, album;
  final MediaId owner;
  final int startMs;
  final int? endMs;
}

/// No authorization snapshot is stored here: the host must resolve current
/// access before dispatch and every queue transition.
class AudioSession {
  AudioSession({
    required this.mode,
    required Iterable<AudioSessionEntry> entries,
    required this.currentEntryId,
    this.repeat = AudioRepeatMode.off,
    Iterable<String>? traversal,
    this.positionMs = 0,
    this.shuffled = false,
  }) : entries = List.unmodifiable(entries) {
    final ids = this.entries.map((e) => e.entryId).toSet();
    this.traversal = List.unmodifiable(
      traversal ?? this.entries.map((e) => e.entryId),
    );
    final expected = mode == AudioSessionMode.music
        ? MediaKind.music
        : MediaKind.audiobook;
    if (ids.isEmpty ||
        ids.length != this.entries.length ||
        !ids.contains(currentEntryId) ||
        positionMs < 0 ||
        this.entries.any((e) => e.owner.kind != expected) ||
        this.traversal.length != ids.length ||
        this.traversal.toSet().length != ids.length ||
        !this.traversal.every(ids.contains) ||
        (mode == AudioSessionMode.audiobook &&
            this.entries.map((e) => e.owner).toSet().length != 1)) {
      throw ArgumentError('Invalid audio session ownership or traversal.');
    }
  }
  final AudioSessionMode mode;
  final List<AudioSessionEntry> entries;
  late final List<String> traversal;
  final String currentEntryId;
  final AudioRepeatMode repeat;
  final int positionMs;
  final bool shuffled;
  AudioSessionEntry get current =>
      entries.firstWhere((entry) => entry.entryId == currentEntryId);

  /// Explicit Next bypasses repeat-one; natural completion honors it.
  AudioSessionEntry? next({bool naturalCompletion = false}) {
    if (naturalCompletion && repeat == AudioRepeatMode.one) return current;
    final index = traversal.indexOf(currentEntryId) + 1;
    if (index >= traversal.length && repeat != AudioRepeatMode.all) return null;
    final id = traversal[index % traversal.length];
    return entries.firstWhere((entry) => entry.entryId == id);
  }
}
