import 'classification.dart';

/// In-memory neutral identity. Existing persisted MediaId keys are not replaced.
class CatalogIdentity {
  CatalogIdentity(this.collectionId, this.entityId, this.kind) {
    if (collectionId.isEmpty || entityId.isEmpty) {
      throw ArgumentError('Catalog identities cannot be empty.');
    }
  }
  final String collectionId, entityId;
  final CatalogEntityKind kind;
  @override
  bool operator ==(Object other) =>
      other is CatalogIdentity &&
      collectionId == other.collectionId &&
      entityId == other.entityId &&
      kind == other.kind;
  @override
  int get hashCode => Object.hash(collectionId, entityId, kind);
}

class CatalogRoot {
  const CatalogRoot({required this.uri, required this.name, this.contentHint});
  final String uri, name;

  /// Legacy movie/TV root hint remains distinct from the collection subtype.
  final String? contentHint;
}

class CatalogAccess {
  const CatalogAccess({required this.locked, required this.includeInGlobal});
  final bool locked, includeInGlobal;
  bool get eligibleGlobally => includeInGlobal && !locked;
}

class CatalogCollection {
  CatalogCollection({
    required this.id,
    required this.name,
    required this.subtype,
    required this.access,
    required Iterable<CatalogRoot> roots,
  }) : roots = List.unmodifiable(roots) {
    if (id.isEmpty) throw ArgumentError('Collection identity cannot be empty.');
  }
  final String id, name;
  final MediaSubtype subtype;
  MediaType get type => subtype.type;
  final CatalogAccess access;
  final List<CatalogRoot> roots;
}

class CatalogSource {
  const CatalogSource({
    required this.id,
    required this.uri,
    required this.name,
    this.available = true,
    this.rootUri,
  });
  final String id, uri, name;
  final String? rootUri;
  final bool available;
}

/// Metadata remains typed by subtype; files do not become individual titles.
class CatalogTitle<T> {
  CatalogTitle({
    required this.id,
    required this.subtype,
    required this.title,
    required this.metadata,
    required Iterable<CatalogSource> sources,
    Iterable<CatalogSegment> segments = const [],
  }) : sources = List.unmodifiable(sources),
       segments = List.unmodifiable(segments) {
    if (id.kind != CatalogEntityKind.title) {
      throw ArgumentError('Expected a title identity.');
    }
    if (this.sources.any((s) => s.id.isEmpty || s.uri.isEmpty) ||
        this.sources.map((s) => s.id).toSet().length != this.sources.length) {
      throw ArgumentError('Duplicate source identity.');
    }
    final sourceIds = this.sources.map((s) => s.id).toSet();
    if (this.segments.map((s) => s.id).toSet().length != this.segments.length ||
        this.segments.any((s) => !sourceIds.contains(s.sourceId))) {
      throw ArgumentError(
        'Segments need unique identities and existing sources.',
      );
    }
  }
  final CatalogIdentity id;
  final MediaSubtype subtype;
  final String title;
  final T metadata;
  final List<CatalogSource> sources;
  final List<CatalogSegment> segments;
}

/// Ordered internal time navigation, separate from catalog group membership.
/// Reading locations will use their own typed contract rather than time ranges.
class CatalogSegment {
  CatalogSegment({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.startMs,
    this.endMs,
  }) {
    if (id.isEmpty ||
        sourceId.isEmpty ||
        startMs < 0 ||
        (endMs != null && endMs! <= startMs)) {
      throw ArgumentError('Invalid internal segment.');
    }
  }
  final String id, sourceId, title;
  final int startMs;
  final int? endMs;
}

enum MembershipKind { structural, curated }

class CatalogGroup<T> {
  CatalogGroup({
    required this.id,
    required this.subtype,
    required this.kind,
    required this.metadata,
  }) {
    if (id.kind != CatalogEntityKind.group) {
      throw ArgumentError('Expected a group identity.');
    }
  }
  final CatalogIdentity id;
  final MediaSubtype subtype;
  final CatalogGroupKind kind;
  final T metadata;
}

/// Relationships, not title ownership: playlists can reference existing titles.
/// Graph validation is supplied by GroupSnapshot; persistence uses adapters.
class GroupMembership {
  GroupMembership({
    required this.parent,
    required this.child,
    required this.kind,
    required this.order,
  }) {
    if (parent.kind != CatalogEntityKind.group ||
        parent == child ||
        parent.collectionId != child.collectionId ||
        order < 0) {
      throw ArgumentError('Invalid group membership.');
    }
  }
  final CatalogIdentity parent, child;
  final MembershipKind kind;
  final int order;
}
