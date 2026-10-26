import 'catalog_models.dart';
import 'classification.dart';

/// Derived from the existing catalog, never a second authoritative database.
class GroupSnapshot {
  GroupSnapshot({
    required Iterable<CatalogGroup<Object?>> groups,
    required Iterable<CatalogIdentity> titles,
    required Iterable<GroupMembership> memberships,
    SubtypeRegistry? registry,
    Map<CatalogIdentity, MediaSubtype> titleSubtypes = const {},
  }) : groups = List.unmodifiable(groups),
       titles = Set.unmodifiable(titles),
       memberships = List.unmodifiable(memberships) {
    final definitions = registry ?? appSubtypes;
    final nodes = {for (final group in this.groups) group.id: group};
    if (this.titles.any((id) => id.kind != CatalogEntityKind.title) ||
        titleSubtypes.keys.any((id) => !this.titles.contains(id))) {
      throw StateError('Title declarations must reference title identities.');
    }
    if (nodes.length != this.groups.length) {
      throw StateError('Duplicate group identity.');
    }
    final collectionSubtypes = <String, MediaSubtype>{};
    for (final group in this.groups) {
      final previous = collectionSubtypes[group.id.collectionId];
      if (previous != null && previous != group.subtype) {
        throw StateError(
          'A collection cannot contain groups of different subtypes.',
        );
      }
      collectionSubtypes[group.id.collectionId] = group.subtype;
      if (!definitions
          .definition(group.subtype)
          .hierarchy
          .groups
          .contains(group.kind)) {
        throw StateError('Unsupported group kind for ${group.subtype.name}.');
      }
    }
    final owners = <CatalogIdentity, CatalogIdentity>{};
    final edges = <(CatalogIdentity, CatalogIdentity, MembershipKind)>{};
    for (final member in this.memberships) {
      final parent = nodes[member.parent];
      final child = nodes[member.child];
      if (parent == null ||
          (child == null && !this.titles.contains(member.child))) {
        throw StateError('Membership references a missing entity.');
      }
      if (!edges.add((member.parent, member.child, member.kind))) {
        throw StateError('Duplicate membership.');
      }
      final hierarchy = definitions.definition(parent.subtype).hierarchy;
      if (child == null &&
          titleSubtypes[member.child] != null &&
          titleSubtypes[member.child] != parent.subtype) {
        throw StateError('Title membership cannot cross subtypes.');
      }
      if (child != null && child.subtype != parent.subtype) {
        throw StateError('Group membership cannot cross subtypes.');
      }
      if (member.kind == MembershipKind.curated) {
        if (child != null || !hierarchy.curatedParents.contains(parent.kind)) {
          throw StateError('Only playlists accept curated membership.');
        }
        continue;
      }
      if (owners.containsKey(member.child)) {
        throw StateError('An entity can have only one structural parent.');
      }
      owners[member.child] = member.parent;
      if (child == null &&
          !hierarchy.structuralTitleParents.contains(parent.kind)) {
        throw StateError('Unsupported structural title edge.');
      }
      if (child != null &&
          !hierarchy.structuralGroupEdges.contains((parent.kind, child.kind))) {
        throw StateError('Unsupported structural group edge.');
      }
    }
    for (final title in this.titles) {
      final subtype =
          titleSubtypes[title] ?? collectionSubtypes[title.collectionId];
      if (subtype != null &&
          definitions.definition(subtype).hierarchy.titleRequiresGroup &&
          !owners.containsKey(title)) {
        throw StateError('This title requires a structural parent.');
      }
    }
    for (final node in nodes.keys) {
      final visited = <CatalogIdentity>{};
      CatalogIdentity? current = node;
      while (current != null) {
        if (!visited.add(current)) throw StateError('Structural cycle.');
        current = owners[current];
      }
    }
  }

  final List<CatalogGroup<Object?>> groups;
  final Set<CatalogIdentity> titles;
  final List<GroupMembership> memberships;

  List<CatalogIdentity> children(CatalogIdentity parent) {
    final edges = memberships.where((m) => m.parent == parent).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(edges.map((m) => m.child));
  }

  /// Reject stale/partial orders rather than dropping newly scanned members.
  Map<CatalogIdentity, int> order(
    CatalogIdentity parent,
    List<CatalogIdentity> ordered,
  ) {
    if (!groups.any((group) => group.id == parent)) {
      throw StateError('Group no longer exists.');
    }
    final current = children(parent).toSet();
    if (ordered.length != current.length ||
        ordered.toSet().length != ordered.length ||
        !current.containsAll(ordered)) {
      throw StateError('Group contents changed. Reopen the ordering screen.');
    }
    return {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
  }
}

abstract interface class GroupRepository {
  Future<GroupSnapshot> snapshot();
  Future<void> reorder(CatalogIdentity parent, List<CatalogIdentity> children);
}
