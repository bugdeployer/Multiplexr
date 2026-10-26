import 'domain/reading_location.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../catalog/domain/catalog_models.dart';
import '../features/catalog/application/space_queries.dart';
import '../library/library_service.dart';

import 'package:app_shell/app_shell.dart';

import 'domain/reading_catalog.dart';
import 'reading_changes.dart';
import 'reading_library.dart';

String readingKey(CatalogIdentity id) =>
    jsonEncode([id.collectionId, id.entityId]);

/// Composition owner for neutral reading data, session grants and live scope.
class ReadingAppController extends ChangeNotifier with WidgetsBindingObserver {
  ReadingAppController(
    this.service, {
    required this.authenticate,
    required this.appBlocked,
    required ReadingLibrary Function(bool Function(String) authorized)
    libraryFactory,
  }) {
    library = libraryFactory(canAccess);
    ReadingChanges.forOwner(service.persistenceOwner).addListener(changed);
    _detachMaintenance = service.maintenance.register(
      invalidate: () {
        _generation++;
        _grants.clear();
        _sessions.clear();
        _creating.clear();
        _collections.clear();
        _progress.clear();
        bundle = null;
        notifyListeners();
      },
    );
    WidgetsBinding.instance.addObserver(this);
  }
  final LibraryService service;
  late final void Function() _detachMaintenance;
  final Future<bool> Function() authenticate;
  final bool Function() appBlocked;
  late final ReadingLibrary library;
  ReadingBundle? bundle;
  Object? error;
  Map<CatalogIdentity, ReadingProgress> _progress = {};
  Map<String, CatalogCollection> _collections = {};
  final _grants = <String>{}, _creating = <String>{};
  final _sessions = <String, int>{};
  int _generation = 0;
  bool _disposed = false;
  bool get ready => bundle != null;
  int get libraryGeneration => service.maintenance.generation;
  bool canAccess(String id) {
    if (appBlocked()) return false;
    if (_creating.contains(id)) return true;
    final c = _collections[id];
    return c != null && (!c.access.locked || _grants.contains(id));
  }

  void changed() {
    unawaited(load());
  }

  void securityChanged() {
    library.metadataJobs.registry.refreshAccess();
    if (appBlocked()) {
      _grants.clear();
      _sessions.clear();
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) changed();
    if (state == AppLifecycleState.paused) {
      _grants.clear();
      _sessions.clear();
      library.metadataJobs.registry.refreshAccess();
      notifyListeners();
    }
  }

  Future<void> load() async {
    final generation = ++_generation;
    try {
      final next = await library.read();
      if (_disposed || generation != _generation) return;
      final nextCollections = {
        for (final c in next.catalog.collections) c.id: c,
      };
      bool revoked(String id) =>
          !nextCollections.containsKey(id) ||
          (_collections[id]?.access.locked == false &&
              nextCollections[id]!.access.locked);
      _grants.removeWhere(revoked);
      _sessions.removeWhere((id, _) => revoked(id));
      bundle = next;
      _collections = {for (final c in next.catalog.collections) c.id: c};
      _progress = {for (final p in next.catalog.progress) p.id: p};
      library.metadataJobs.registry.refreshAccess();
      error = null;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e;
      // A failed refresh cannot authorize previously visible private content.
      _grants.clear();
      bundle = null;
      _collections = {};
      _progress = {};
      _sessions.clear();
    }
    notifyListeners();
  }

  Future<bool> unlock(String id) async {
    final generation = libraryGeneration;
    await load();
    if (generation != libraryGeneration) return false;
    if (canAccess(id)) {
      _sessions[id] = (_sessions[id] ?? 0) + 1;
      return true;
    }
    final collection = bundle?.catalog.collections
        .where((c) => c.id == id)
        .firstOrNull;
    if (collection == null || appBlocked() || !await authenticate()) {
      return false;
    }
    await load();
    if (generation != libraryGeneration ||
        appBlocked() ||
        !(bundle?.catalog.collections.any((c) => c.id == id) ?? false)) {
      return false;
    }
    _grants.add(id);
    _sessions[id] = (_sessions[id] ?? 0) + 1;
    notifyListeners();
    return true;
  }

  void endSession(String id) {
    final remaining = (_sessions[id] ?? 1) - 1;
    if (remaining <= 0) {
      _sessions.remove(id);
      _grants.remove(id);
    } else {
      _sessions[id] = remaining;
    }
    notifyListeners();
  }

  ReadingTitle? nextInSeries(ReadingTitle current) {
    final catalog = bundle?.catalog;
    if (catalog == null || !canAccess(current.catalog.id.collectionId)) {
      return null;
    }
    final membership = catalog.memberships
        .where((m) => m.child == current.catalog.id)
        .firstOrNull;
    if (membership == null) return null;
    final rest =
        catalog.memberships
            .where(
              (m) =>
                  m.parent == membership.parent && m.order > membership.order,
            )
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    for (final member in rest) {
      final title = catalog.titles
          .where((t) => t.catalog.id == member.child)
          .firstOrNull;
      if (title != null &&
          !finished(title) &&
          title.catalog.sources.single.available) {
        return title;
      }
    }
    return null;
  }

  List<ReadingTitle> eligible(SpaceScope scope) {
    final b = bundle;
    if (b == null || appBlocked()) return [];
    final owners = b.catalog.collections
        .where((c) => scope.includes(c, authorized: canAccess(c.id)))
        .map((c) => c.id)
        .toSet();
    return b.catalog.titles
        .where((t) => owners.contains(t.catalog.id.collectionId))
        .toList();
  }

  bool finished(ReadingTitle t) => _progress[t.catalog.id]?.finished ?? false;
  bool started(ReadingTitle title) {
    final location = progress(title)?.location;
    return location is TextReadingLocation
        ? location.locator != '0'
        : location is PageReadingLocation &&
              (location.pageIndex > 0 || location.offset > 0);
  }

  ReadingProgress? progress(ReadingTitle t) => _progress[t.catalog.id];
  List<ReadingTitle> nextUnread(SpaceScope scope) {
    final eligibleTitles = {for (final t in eligible(scope)) t.catalog.id: t};
    final result = <ReadingTitle>[];
    final grouped = <CatalogIdentity>{};
    final membersByGroup = <CatalogIdentity, List<GroupMembership>>{};
    for (final member in bundle?.catalog.memberships ?? <GroupMembership>[]) {
      (membersByGroup[member.parent] ??= []).add(member);
    }
    for (final group
        in bundle?.catalog.groups ?? <CatalogGroup<ReadingMetadata>>[]) {
      final members = (membersByGroup[group.id] ?? [])
        ..sort((a, b) => a.order.compareTo(b.order));
      final titles = members
          .map((m) => eligibleTitles[m.child])
          .whereType<ReadingTitle>()
          .toList();
      grouped.addAll(titles.map((t) => t.catalog.id));
      final next = titles
          .where((t) => !finished(t) && t.catalog.sources.single.available)
          .firstOrNull;
      if (next != null) result.add(next);
    }
    result.addAll(
      eligibleTitles.values.where(
        (t) =>
            !grouped.contains(t.catalog.id) &&
            !finished(t) &&
            t.catalog.sources.single.available,
      ),
    );
    return result;
  }

  String cover(ReadingTitle t) {
    final b = bundle!;
    final managed = b.management.entity(t.catalog.id);
    return (managed.cover).isNotEmpty
        ? managed.cover
        : b.index.entry(t.catalog.id)?.cover ?? '';
  }

  List<ReadingListView> lists(SpaceScope scope) {
    final allowed = eligible(scope)
        .map((t) => t.catalog.id.collectionId)
        .toSet();
    return (bundle?.management.lists ?? [])
        .where((r) => allowed.contains(r.collectionId))
        .toList();
  }

  Future<void> saveList(
    String owner,
    String id,
    String name,
    List<String> titles,
  ) => library.saveList(owner, id, name, titles);
  Future<void> deleteList(String owner, String id) =>
      library.deleteList(owner, id);
  Future<void> create(
    Map<String, dynamic> row, {
    Map<String, dynamic>? preferences,
  }) async {
    final id = row['id'] as String;
    _creating.add(id);
    try {
      await library.createCollection(
        library.collectionFromForm(row),
        preferences: preferences,
      );
      await load();
    } finally {
      _creating.remove(id);
    }
  }

  Future<void> deleteCollection(String id) async {
    library.access(id);
    await library.removeCollection(id);
    _grants.remove(id);
    await load();
  }

  @override
  void notifyListeners() {
    library.autoScans.refreshAccess();
    super.notifyListeners();
  }

  @override
  void dispose() {
    _detachMaintenance();
    _disposed = true;
    library.metadataJobs.registry.dispose();
    library.autoScans.dispose();
    ReadingChanges.forOwner(service.persistenceOwner).removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Replacing the subtree also disposes an active reader and its native handle.
class ReadingAccessGuard extends StatefulWidget {
  const ReadingAccessGuard({
    super.key,
    required this.controller,
    required this.collectionId,
    required this.child,
  });
  final ReadingAppController controller;
  final String? collectionId;
  final Widget child;
  @override
  State<ReadingAccessGuard> createState() => _ReadingAccessGuardState();
}

class _ReadingAccessGuardState extends State<ReadingAccessGuard> {
  late final int _generation = widget.controller.libraryGeneration;
  bool get allowed =>
      _generation == widget.controller.libraryGeneration &&
      !widget.controller.appBlocked() &&
      (widget.collectionId == null ||
          widget.controller.canAccess(widget.collectionId!));
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (!mounted) return;
    if (!allowed) {
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        Navigator.of(context).popUntil((r) => r == route || r.isFirst);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => allowed
      ? widget.child
      : Scaffold(
          appBar: AppBar(title: const Text('Reading')),
          body: Center(
            child: TextButton.icon(
              icon: const AppIcon(AppIconRole.back),
              label: const Text('Collection unavailable · Back'),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        );
}
