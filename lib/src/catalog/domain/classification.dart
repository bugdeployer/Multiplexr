/// Collection classification; deliberately independent of legacy storage kinds.
enum MediaType { video, audio, photo, ebook }

enum MediaSubtype {
  moviesTv(MediaType.video, 'Movies & TV'),
  videos(MediaType.video, 'Videos'),
  music(MediaType.audio, 'Music'),
  audiobooks(MediaType.audio, 'Audiobooks'),
  photo(MediaType.photo, 'Photo'),
  gif(MediaType.photo, 'GIF'),
  ebook(MediaType.ebook, 'Ebook'),
  comics(MediaType.ebook, 'Comics/Manhua/Manga');

  const MediaSubtype(this.type, this.label);
  final MediaType type;
  final String label;
}

enum CatalogEntityKind { group, title }

enum CatalogGroupKind { series, season, album, playlist }

enum CatalogLayout { compact, list, grid }

enum MediaEngineKind { video, audio, image, reader }

enum MediaCapability {
  multipleRoots,
  search,
  filters,
  selection,
  tags,
  metadataLookup,
  bulkMetadata,
  artwork,
  localSpace,
  globalSpace,
  externalEngine,
}

/// Describes structure, not file paths or provider-assigned membership.
class HierarchyDefinition {
  HierarchyDefinition({
    Iterable<CatalogGroupKind> groups = const [],
    Iterable<CatalogGroupKind> structuralTitleParents = const [],
    Iterable<(CatalogGroupKind, CatalogGroupKind)> structuralGroupEdges =
        const [],
    Iterable<CatalogGroupKind> curatedParents = const [],
    this.titleRequiresGroup = false,
  }) : groups = Set.unmodifiable(groups),
       structuralTitleParents = Set.unmodifiable(structuralTitleParents),
       structuralGroupEdges = Set.unmodifiable(structuralGroupEdges),
       curatedParents = Set.unmodifiable(curatedParents) {
    if (titleRequiresGroup &&
        (this.groups.isEmpty || this.structuralTitleParents.isEmpty)) {
      throw ArgumentError('A required group needs a supported group kind.');
    }
    if (!this.groups.containsAll(this.structuralTitleParents) ||
        !this.groups.containsAll(this.curatedParents) ||
        this.structuralGroupEdges.any(
          (edge) =>
              !this.groups.contains(edge.$1) || !this.groups.contains(edge.$2),
        )) {
      throw ArgumentError('Hierarchy edges must use declared group kinds.');
    }
    if (this.curatedParents.any((kind) => kind != CatalogGroupKind.playlist)) {
      throw ArgumentError('Only playlists accept curated membership.');
    }
  }
  final Set<CatalogGroupKind> groups;
  final Set<CatalogGroupKind> structuralTitleParents, curatedParents;
  final Set<(CatalogGroupKind, CatalogGroupKind)> structuralGroupEdges;
  final bool titleRequiresGroup;
}

class SubtypeDefinition {
  SubtypeDefinition({
    required this.id,
    required this.engine,
    required this.hierarchy,
    required this.enabled,
    Iterable<MediaCapability> capabilities = const [],
    Iterable<CatalogLayout> layouts = CatalogLayout.values,
  }) : capabilities = Set.unmodifiable(capabilities),
       layouts = Set.unmodifiable(layouts);
  final MediaSubtype id;
  MediaType get type => id.type;
  final MediaEngineKind engine;
  final HierarchyDefinition hierarchy;

  /// Describes currently usable implementation, not future product intent.
  final bool enabled;
  final Set<MediaCapability> capabilities;
  final Set<CatalogLayout> layouts;
}

/// Validated at composition; unavailable definitions never imply usable flows.
class SubtypeRegistry {
  SubtypeRegistry(Iterable<SubtypeDefinition> definitions) {
    final entries = <MediaSubtype, SubtypeDefinition>{};
    for (final definition in definitions) {
      if (entries.containsKey(definition.id)) {
        throw ArgumentError('Duplicate subtype: ${definition.id.name}');
      }
      final expected = switch (definition.type) {
        MediaType.video => MediaEngineKind.video,
        MediaType.audio => MediaEngineKind.audio,
        MediaType.photo => MediaEngineKind.image,
        MediaType.ebook => MediaEngineKind.reader,
      };
      if (definition.engine != expected) {
        throw ArgumentError('Incompatible engine for ${definition.id.name}');
      }
      if (definition.enabled && definition.layouts.isEmpty) {
        throw ArgumentError('Enabled subtypes need a collection layout.');
      }
      entries[definition.id] = definition;
    }
    _definitions = Map.unmodifiable(entries);
  }
  late final Map<MediaSubtype, SubtypeDefinition> _definitions;
  List<SubtypeDefinition> get definitions =>
      List.unmodifiable(_definitions.values);
  List<SubtypeDefinition> get enabled =>
      List.unmodifiable(definitions.where((d) => d.enabled));
  SubtypeDefinition definition(MediaSubtype id) =>
      _definitions[id] ??
      (throw UnsupportedError('Unregistered subtype: ${id.name}'));
  SubtypeDefinition requireEnabled(MediaSubtype id) {
    final value = definition(id);
    if (!value.enabled) throw UnsupportedError('${id.label} is not available.');
    return value;
  }

  void validateBindings({
    required Set<MediaSubtype> collectionRoutes,
    required Set<MediaEngineKind> engines,
  }) {
    for (final route in collectionRoutes) {
      requireEnabled(route);
    }
    for (final definition in enabled) {
      if (!collectionRoutes.contains(definition.id) ||
          !engines.contains(definition.engine)) {
        throw StateError(
          'Missing implementation binding for ${definition.id.name}',
        );
      }
    }
  }

  List<SubtypeDefinition> forType(
    MediaType type, {
    bool availableOnly = true,
  }) => List.unmodifiable(
    definitions.where((d) => d.type == type && (!availableOnly || d.enabled)),
  );
}

final appSubtypes = SubtypeRegistry([
  for (final id in MediaSubtype.values)
    SubtypeDefinition(
      id: id,
      engine: switch (id.type) {
        MediaType.video => MediaEngineKind.video,
        MediaType.audio => MediaEngineKind.audio,
        MediaType.photo => MediaEngineKind.image,
        MediaType.ebook => MediaEngineKind.reader,
      },
      enabled: {
        MediaSubtype.moviesTv,
        MediaSubtype.videos,
        MediaSubtype.audiobooks,
        MediaSubtype.music,
        MediaSubtype.ebook,
        MediaSubtype.comics,
      }.contains(id),
      hierarchy: HierarchyDefinition(
        groups: switch (id) {
          MediaSubtype.moviesTv => [
            CatalogGroupKind.series,
            CatalogGroupKind.season,
          ],
          MediaSubtype.audiobooks ||
          MediaSubtype.ebook ||
          MediaSubtype.comics => [CatalogGroupKind.series],
          MediaSubtype.music => [
            CatalogGroupKind.album,
            CatalogGroupKind.playlist,
          ],
          _ => [],
        },
        titleRequiresGroup:
            id == MediaSubtype.audiobooks || id == MediaSubtype.comics,
        structuralTitleParents: switch (id) {
          MediaSubtype.moviesTv => [CatalogGroupKind.season],
          MediaSubtype.audiobooks ||
          MediaSubtype.ebook ||
          MediaSubtype.comics => [CatalogGroupKind.series],
          MediaSubtype.music => [CatalogGroupKind.album],
          _ => [],
        },
        structuralGroupEdges: id == MediaSubtype.moviesTv
            ? [(CatalogGroupKind.series, CatalogGroupKind.season)]
            : [],
        curatedParents: id == MediaSubtype.music
            ? [CatalogGroupKind.playlist]
            : [],
      ),
      capabilities:
          {
            MediaSubtype.moviesTv,
            MediaSubtype.videos,
            MediaSubtype.audiobooks,
            MediaSubtype.music,
          }.contains(id)
          ? const {
              MediaCapability.multipleRoots,
              MediaCapability.search,
              MediaCapability.filters,
              MediaCapability.selection,
              MediaCapability.tags,
              MediaCapability.metadataLookup,
              MediaCapability.bulkMetadata,
              MediaCapability.artwork,
              MediaCapability.localSpace,
              MediaCapability.globalSpace,
              MediaCapability.externalEngine,
            }
          : id.type == MediaType.ebook
          ? const {
              MediaCapability.multipleRoots,
              MediaCapability.search,
              MediaCapability.filters,
              MediaCapability.selection,
              MediaCapability.tags,
              MediaCapability.metadataLookup,
              MediaCapability.bulkMetadata,
              MediaCapability.artwork,
              MediaCapability.localSpace,
              MediaCapability.globalSpace,
            }
          : const [],
    ),
]);
