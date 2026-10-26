import 'catalog_models.dart';
import 'classification.dart';

/// A global playlist is not a collection and does not own its source tracks.
class PlaylistScope {
  PlaylistScope.collection(String collectionId) : collectionId = collectionId {
    if (collectionId.trim().isEmpty) {
      throw ArgumentError('A local playlist requires a collection.');
    }
  }
  const PlaylistScope.global() : collectionId = null;
  final String? collectionId;
  bool get isGlobal => collectionId == null;
}

class PlaylistEntry {
  PlaylistEntry({required this.id, required this.track}) {
    if (id.trim().isEmpty || track.kind != CatalogEntityKind.title) {
      throw ArgumentError('Playlist entries require an identity and a title.');
    }
  }
  final String id;
  final CatalogIdentity track;
}

class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    required this.scope,
    required Iterable<PlaylistEntry> entries,
  }) : entries = List.unmodifiable(entries) {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        this.entries.map((e) => e.id).toSet().length != this.entries.length ||
        this.entries.any(
          (e) => !scope.isGlobal && e.track.collectionId != scope.collectionId,
        )) {
      throw ArgumentError('Invalid playlist identity, entries or scope.');
    }
  }
  final String id, name;
  final PlaylistScope scope;
  final List<PlaylistEntry> entries;

  /// Resolve on each query/action. Retain hidden references in saved state.
  List<PlaylistEntry> eligibleEntries({
    required Map<String, CatalogCollection> collections,
    required Set<String> authorizedCollections,
    required Set<CatalogIdentity> availableTracks,
  }) => List.unmodifiable(
    entries.where((entry) {
      final collection = collections[entry.track.collectionId];
      if (collection == null ||
          collection.subtype != MediaSubtype.music ||
          !availableTracks.contains(entry.track)) {
        return false;
      }
      if (scope.isGlobal) return collection.access.eligibleGlobally;
      return !collection.access.locked ||
          authorizedCollections.contains(collection.id);
    }),
  );

  MusicPlaylist reordered(List<String> entryIds) {
    final byId = {for (final entry in entries) entry.id: entry};
    if (entryIds.length != entries.length ||
        entryIds.toSet().length != entries.length ||
        !entryIds.every(byId.containsKey)) {
      throw ArgumentError('Reordering must include every entry exactly once.');
    }
    return MusicPlaylist(
      id: id,
      name: name,
      scope: scope,
      entries: entryIds.map((id) => byId[id]!),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'id': id,
    'name': name,
    'collectionId': scope.collectionId,
    'entries': [
      for (final e in entries)
        {
          'id': e.id,
          'collectionId': e.track.collectionId,
          'titleId': e.track.entityId,
        },
    ],
  };

  factory MusicPlaylist.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1) {
      throw const FormatException('Unsupported Music playlist version.');
    }
    return MusicPlaylist(
      id: value['id'] as String,
      name: value['name'] as String,
      scope: value['collectionId'] == null
          ? const PlaylistScope.global()
          : PlaylistScope.collection(value['collectionId'] as String),
      entries: (value['entries'] as List).map(
        (e) => PlaylistEntry(
          id: e['id'] as String,
          track: CatalogIdentity(
            e['collectionId'] as String,
            e['titleId'] as String,
            CatalogEntityKind.title,
          ),
        ),
      ),
    );
  }
}
