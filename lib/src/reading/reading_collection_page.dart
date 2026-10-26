import '../experience/plugins/plugin_contribution_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../features/catalog/application/reading_collection_projection.dart';
export '../features/catalog/application/reading_collection_projection.dart'
    show ReadingItem;
import '../media/shared_audio_mini_player.dart';
import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../experience/actions/media_actions.dart';
import '../features/catalog/application/collection_presenter.dart';
import '../experience/collection/collection_layout.dart';
import '../experience/navigation/browse_memory.dart';
import '../experience/navigation/navigation_coordinator.dart';
import '../experience/navigation/navigation_origin.dart';
import '../experience/navigation/opening_policy.dart';
import '../library/tags.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../metadata/metadata_review_page.dart';

import 'package:app_shell/app_shell.dart';

import '../media/media_ui_patterns.dart';
import '../media/grouping.dart';
import '../settings/domain/media_settings.dart';
import 'comic_reader_page.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import 'reading_library.dart';
import '../features/metadata/application/publication_provider.dart';
import '../features/metadata/application/reading_metadata_target.dart';
import 'reading_metadata_job.dart';
import 'reading_metadata_page.dart';
import 'reading_management_pages.dart';
import 'reading_workflow_widgets.dart';
import 'reader_opening.dart';

/// Collection workflows used by both production reading subtype routes.
class ReadingCollectionPage extends StatefulWidget {
  const ReadingCollectionPage({
    super.key,
    required this.library,
    required this.collectionId,
    this.groupId,
    this.provider,
    this.openTitle,
    this.openSpace,
    this.scanOnOpen = false,
    this.showJobs = false,
  });
  final ReadingLibrary library;
  final bool scanOnOpen, showJobs;
  final String collectionId;
  final CatalogIdentity? groupId;
  final PublicationProvider? provider;
  final Future<void> Function(BuildContext, ReadingTitle)? openTitle;
  final Future<void> Function(BuildContext, String)? openSpace;
  @override
  State<ReadingCollectionPage> createState() => _ReadingCollectionPageState();
}

class _ReadingCollectionPageState extends State<ReadingCollectionPage> {
  bool controlsExpanded = false;
  final controller = CollectionController<ReadingItem, CatalogIdentity>(
    identity: (i) => i.id,
  );
  final query = TextEditingController(), scroll = ScrollController();
  final navigation = NavigationCoordinator();
  ReadingBundle? bundle;
  String author = '', language = '';
  bool busy = false, scanning = false;
  String? scanMessage;

  late final provider = widget.provider ?? widget.library.metadataJobs.provider;
  late final job = widget.library.metadataJobs.job(
    widget.collectionId,
    provider,
  );
  late final memory = BrowseMemory(
    preferences: widget.library.service.userPreferences,
    capture: () => NavigationOrigin(
      routeId: 'reading:${widget.groupId?.entityId ?? 'collection'}',
      collectionId: widget.collectionId,
      query: query.text,
      sort: controller.sort,
      filter: jsonEncode([
        controller.filter,
        author,
        language,
        controller.descending,
      ]),
      tag: controller.tag,
      folder: controller.folder,
      layout: controller.layout.name,
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
    ),
    defaults: () => NavigationOrigin(
      layout: controller.layout.name,
      sort: controller.sort,
      routeId: 'reading:${widget.groupId?.entityId ?? 'collection'}',
      collectionId: widget.collectionId,
    ),
    apply: (origin) {
      if (!mounted) return;
      setState(() {
        controller.sort = origin.sort.isEmpty ? 'title' : origin.sort;
        controller.tag = origin.tag;
        controller.folder = origin.folder;
        if (CatalogLayout.values.any((v) => v.name == origin.layout)) {
          controller.layout = CatalogLayout.values.byName(origin.layout);
        }
        try {
          final f = jsonDecode(origin.filter) as List;
          controller.filter = f[0] as String;
          author = f[1] as String;
          language = f[2] as String;
          controller.descending = f.length > 3 && f[3] == true;
        } catch (_) {
          controller.filter = 'all';
        }
      });
    },
    alive: () => mounted,
    contentReady: () => !controller.loading,
    query: query,
    scroll: scroll,
  );
  @override
  void initState() {
    super.initState();
    query.addListener(changed);
    job.addListener(changed);
    unawaited(initialize());
  }

  Future<void> initialize() async {
    await load();
    await memory.restore();
    if (mounted &&
        widget.showJobs &&
        bundle != null &&
        widget.library.authorized(widget.collectionId)) {
      await reviewJobs();
    }
    if (!mounted || !widget.scanOnOpen || bundle == null) return;
    final owner = bundle!.catalog.collections
        .where((c) => c.id == widget.collectionId)
        .firstOrNull;
    if (owner == null || owner.roots.isEmpty) return;
    setState(() => scanning = true);
    try {
      final applied = await widget.library.autoScans.run(widget.collectionId);
      if (!mounted) return;
      if (applied) {
        await load();
      } else {
        setState(
          () => scanMessage = 'Review source warnings in Folder health.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              scanMessage = 'Scan did not finish. Open Folder health to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> folderHealth() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReadingFolderHealthPage(
          library: widget.library,
          collectionId: widget.collectionId,
        ),
      ),
    );
    if (mounted) {
      setState(() => scanMessage = null);
      await load();
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    if (!widget.library.authorized(widget.collectionId)) {
      if (mounted) setState(() => bundle = null);
      return;
    }
    ReadingBundle? incoming;
    final accepted = await controller.load(() async {
      final b = await widget.library.readCollection(widget.collectionId);
      widget.library.access(widget.collectionId);
      incoming = b;
      final prefs = b.management.collections
          .where((c) => c.collectionId == widget.collectionId)
          .firstOrNull;
      final previous = (bundle?.management.collections ?? [])
          .where((c) => c.collectionId == widget.collectionId)
          .firstOrNull;
      if (prefs != null &&
          (controller.items.isEmpty ||
              prefs.layout != previous?.layout ||
              prefs.sort != previous?.sort)) {
        controller.layout = CatalogLayout.values.byName(prefs.layout);
        controller.sort = prefs.sort;
      }
      final titles = b.catalog.titles
          .where((t) => t.catalog.id.collectionId == widget.collectionId)
          .toList();
      final children =
          b.catalog.memberships
              .where((m) => m.parent == widget.groupId)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
      return [
        if (widget.groupId == null)
          ...b.catalog.groups
              .where((g) => g.id.collectionId == widget.collectionId)
              .map((g) => ReadingItem(g.id, g.metadata, null)),
        for (final title in titles)
          if (widget.groupId != null
              ? children.any((m) => m.child == title.catalog.id)
              : true)
            ReadingItem(title.catalog.id, title.catalog.metadata, title),
      ];
    }, failure: 'Could not load this reading collection. Retry.');
    if (accepted) bundle = incoming;
    try {
      await job.recover();
    } catch (_) {
      /* Browse remains usable; opening lookup work retries its journal. */
    }
    if (mounted) {
      setState(() {});
      memory.changed();
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      widget.library.access(widget.collectionId);
      await action();
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is MetadataFailure
                  ? e.message
                  : 'Could not save this change. Retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  ReadingCollectionProjection get projection => ReadingCollectionProjection(
    bundle!,
    controller,
    groupId: widget.groupId,
    query: query.text,
    author: author,
    language: language,
  );
  String status(ReadingItem item) => projection.status(item);
  List<ReadingItem> get visible => projection.visible;
  Future<void> reader(ReadingTitle title) => navigation.run(
    'reader:${title.catalog.id.entityId}',
    () => readTitle(title),
  );
  Future<void> readTitle(ReadingTitle title) async {
    widget.library.access(widget.collectionId);
    await memory.flush();
    if (!mounted) return;
    if (widget.openTitle != null) {
      await widget.openTitle!(context, title);
    } else if (title.catalog.subtype == MediaSubtype.ebook) {
      await openEbookReader(
        context,
        widget.library.readerHost,
        title,
        authorized: widget.library.authorized,
      );
    } else {
      await openComicReader(
        context,
        widget.library.readerHost,
        title,
        authorized: widget.library.authorized,
      );
    }
  }

  Future<void> open(ReadingItem item) =>
      navigation.run('open:${item.id.entityId}', () => openItem(item));
  Future<void> openItem(ReadingItem item) async {
    if (controller.selecting) {
      setState(() => controller.toggle(item));
      return;
    }
    await memory.flush();
    if (!mounted) return;
    final prefs = bundle!.management.collections
        .where((c) => c.collectionId == widget.collectionId)
        .firstOrNull;
    final destination = const OpeningPolicy().resolve(
      group: item.group,
      action: prefs?.openAction == 'open'
          ? TitleOpenAction.play
          : TitleOpenAction.details,
      authorized: widget.library.authorized(widget.collectionId),
      available: item.title?.catalog.sources.single.available ?? true,
    );
    if (destination == OpeningDestination.contents) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingCollectionPage(
            library: widget.library,
            collectionId: widget.collectionId,
            groupId: item.id,
            provider: provider,
            openTitle: widget.openTitle,
            openSpace: widget.openSpace,
          ),
        ),
      );
    } else if (destination == OpeningDestination.session) {
      await reader(item.title!);
    } else if (destination == OpeningDestination.details) {
      await details(item);
    } else if (destination == OpeningDestination.unavailable) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingFolderHealthPage(
            library: widget.library,
            collectionId: widget.collectionId,
          ),
        ),
      );
    }
    await load();
  }

  MediaActionContext actionContext(ReadingItem item) => MediaActionContext(
    authorized: widget.library.authorized(widget.collectionId),
    hasSettings: true,
    capabilities: appSubtypes
        .definition(
          bundle!.catalog.collections
              .singleWhere((c) => c.id == widget.collectionId)
              .subtype,
        )
        .capabilities,
    hasProvider: true,
  );
  Future<void> action(
    ReadingItem item,
    MediaActionId action,
  ) => MediaActionRegistry.execute(action, () => actionContext(item), () async {
    if (action == MediaActionId.settings) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingScopedSettingsPage(
            library: widget.library,
            collectionId: widget.collectionId,
            subtype: bundle!.catalog.collections
                .singleWhere((c) => c.id == widget.collectionId)
                .subtype,
            identity: item.id,
          ),
        ),
      );
    } else if (action == MediaActionId.chooseArtwork) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingArtworkPage(
            library: widget.library,
            identity: item.id,
            provider: provider,
          ),
        ),
      );
    } else if (action == MediaActionId.findMetadata) {
      final target = await ReadingMetadataTarget(
        widget.library,
        item.id,
        provider,
      ).initialize();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingMetadataPage(target: target),
        ),
      );
    } else {
      final fresh = await widget.library.readCollection(widget.collectionId);
      final m = item.group
          ? fresh.catalog.groups.singleWhere((g) => g.id == item.id).metadata
          : fresh.catalog.titles
                .singleWhere((t) => t.catalog.id == item.id)
                .catalog
                .metadata;
      if (!mounted) return;
      await readingFields(
        context,
        title: 'Edit metadata',
        initial: {
          'title': m.title,
          'authors': m.authors.join('\n'),
          'description': m.description,
          'language': m.language,
          'identifier': m.identifier,
          if (bundle!.catalog.collections
                  .singleWhere((c) => c.id == widget.collectionId)
                  .subtype ==
              MediaSubtype.comics)
            'comicStyle': m.comicStyle?.name ?? 'comic',
        },
        multiline: {'authors', 'description'},
        labels: {
          'title': 'Title',
          'authors': 'Authors (one per line)',
          'description': 'Description',
          'language': 'Language',
          'identifier': 'Identifier',
          'comicStyle': 'comic / manga / manhua / manhwa',
        },
        save: (values) => widget.library.metadata(item.id, {
          ...values,
          'authors': values['authors']!
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        }),
      );
    }
  });
  Future<void> details(ReadingItem item) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => ReadingTitleDetailsPage(
        library: widget.library,
        identity: item.id,
        actions: (a) => run(() => action(item, a)),
        open: () => reader(
          bundle!.catalog.titles.singleWhere((t) => t.catalog.id == item.id),
        ),
      ),
    ),
  );
  List<CatalogIdentity> get selected => controller.selected.toList();
  List<CatalogIdentity> get selectedTitles => {
    for (final id in selected)
      if (id.kind == CatalogEntityKind.title)
        id
      else
        ...bundle!.catalog.memberships
            .where((m) => m.parent == id)
            .map((m) => m.child),
  }.toList();
  Future<void> markFinished(bool value) async {
    final ids = selectedTitles;
    final before = {
      for (final id in ids)
        id:
            bundle!.catalog.progress
                .where((p) => p.id == id)
                .firstOrNull
                ?.finished ??
            false,
    };
    await widget.library.finished(widget.collectionId, ids, value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? 'Marked finished' : 'Marked unread'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => run(
            () => widget.library.restoreFinished(
              widget.collectionId,
              before,
              value,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> editTags() => readingFields(
    context,
    title: 'Edit tags',
    initial: {
      'tags': selected.length == 1
          ? (bundle!.management.entity(selected.single).tags as List).join(', ')
          : '',
    },
    labels: {'tags': selected.length == 1 ? 'Tags' : 'Tags to add'},
    save: (fields) => widget.library.tags(
      widget.collectionId,
      selected,
      normalizeTags(fields['tags']!),
      operation: selected.length == 1 ? 'replace' : 'add',
    ),
  );
  Future<void> makeGroup() => readingFields(
    context,
    title: 'Move to series',
    initial: {'name': ''},
    labels: {'name': 'Series name'},
    save: (fields) async {
      final existing = bundle!.catalog.groups
          .where(
            (g) =>
                g.id.collectionId == widget.collectionId &&
                g.metadata.title == fields['name'],
          )
          .firstOrNull;
      await widget.library.group(
        widget.collectionId,
        existing?.id.entityId ??
            'manual-${DateTime.now().microsecondsSinceEpoch}',
        fields['name']!,
        selectedTitles.map((id) => id.entityId).toList(),
      );
    },
  );
  Future<void> startJob() async {
    if (selectedTitles.length > 20 || selectedTitles.isEmpty) {
      throw StateError('Select at most 20 titles.');
    }
    var replace = false;
    if (job.remaining.isNotEmpty ||
        job.entries.values.any((e) => e['status'] == 'review')) {
      replace =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace lookup results?'),
              content: const Text(
                'This starts a new selected batch and replaces unapplied results from the previous lookup. Applied metadata is kept.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Start new lookup'),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace) return;
    }
    await job.start(
      selectedTitles.map((id) => id.entityId).toList(),
      replace: replace,
    );
  }

  Future<void> reviewJobs() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => _ReadingJobResults(
        job: job,
        library: widget.library,
        provider: provider,
      ),
    ),
  );
  Future<void> viewSettings() async {
    final choice = await showCollectionView(
      context,
      layout: controller.layout.name,
      sort: controller.sort,
      sorts: const {
        'title': 'Title',
        'author': 'Author',
        'source': 'Source order',
      },
      descending: controller.descending,
      cardSize:
          bundle?.management.collections
              .where((r) => r.collectionId == widget.collectionId)
              .firstOrNull
              ?.cardSize ??
          180,
    );
    if (choice == null || !mounted) return;
    await run(() async {
      await widget.library.browse(widget.collectionId, {
        'layout': choice.layout,
        'sort': choice.sort,
        'cardSize': choice.cardSize,
      });
      controller.layout = CatalogLayout.values.byName(choice.layout);
      controller.sort = choice.sort;
      controller.descending = choice.descending;
    });
  }

  Future<void> filters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        Widget choose(
          String label,
          String value,
          Set<String> options,
          void Function(String) set,
        ) => DropdownButtonFormField<String>(
          icon: const AppIcon(AppIconRole.expand),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: {'', ...options, value}
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(
                    v.isEmpty
                        ? 'All'
                        : label == 'Status'
                        ? readingStatusLabel(v)
                        : label == 'Folder'
                        ? (bundle!.catalog.collections
                                  .expand((c) => c.roots)
                                  .where((r) => r.uri == v)
                                  .firstOrNull
                                  ?.name ??
                              'Source folder')
                        : v,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              update(() => set(v));
              changed();
            }
          },
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                choose(
                  'Status',
                  controller.filter == 'all' ? '' : controller.filter,
                  {'unread', 'inProgress', 'completed', 'missing'},
                  (v) => controller.filter = v.isEmpty ? 'all' : v,
                ),
                choose(
                  'Tag',
                  controller.tag,
                  controller.items
                      .expand(
                        (i) => (bundle!.management.entity(i.id).tags as List)
                            .cast<String>(),
                      )
                      .toSet(),
                  (v) => controller.tag = v,
                ),
                choose(
                  'Author',
                  author,
                  controller.items.expand((i) => i.metadata.authors).toSet(),
                  (v) => author = v,
                ),
                choose(
                  'Language',
                  language,
                  controller.items
                      .map((i) => i.metadata.language)
                      .where((v) => v.isNotEmpty)
                      .toSet(),
                  (v) => language = v,
                ),
                choose(
                  'Folder',
                  controller.folder,
                  bundle!.catalog.collections
                      .singleWhere((c) => c.id == widget.collectionId)
                      .roots
                      .map((r) => r.uri)
                      .toSet(),
                  (v) => controller.folder = v,
                ),
                TextButton(
                  onPressed: () {
                    update(() {
                      controller.filter = 'all';
                      controller.tag = '';
                      controller.folder = '';
                      author = '';
                      language = '';
                    });
                    changed();
                  },
                  child: const Text('Clear filters'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  List<ReadingItem> get orderedMembers {
    final members =
        bundle!.catalog.memberships
            .where((m) => m.parent == widget.groupId)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (final member in members)
        for (final title in bundle!.catalog.titles.where(
          (t) => t.catalog.id == member.child,
        ))
          ReadingItem(title.catalog.id, title.catalog.metadata, title),
    ];
  }

  Future<void> orderGroup() async {
    final group = bundle!.catalog.groups.singleWhere(
      (g) => g.id == widget.groupId,
    );
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GroupOrderPage<ReadingItem>(
          title: 'Edit order',
          items: orderedMembers,
          identity: (i) => i.id.entityId,
          label: (i) => i.metadata.title,
          save: (items) => widget.library.group(
            widget.collectionId,
            group.id.entityId,
            group.metadata.title,
            items.map((i) => i.id.entityId).toList(),
          ),
        ),
      ),
    );
  }

  Widget groupBody(CatalogGroup<ReadingMetadata> group) {
    final items = orderedMembers;
    final available = items
        .where((i) => i.title!.catalog.sources.single.available)
        .toList();
    final next =
        available.where((i) => status(i) == 'inProgress').firstOrNull ??
        available.where((i) => status(i) == 'unread').firstOrNull ??
        available.firstOrNull;
    return MediaDetailsBody(
      controller: scroll,
      artworkAspectRatio: 2 / 3,
      artwork: ReadingCover(
        library: widget.library,
        reference: readingCoverReference(bundle!, group.id),
        crop: bundle!.management.entity(group.id).coverMode == 'crop',
      ),
      children: [
        Text(
          group.metadata.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (group.metadata.authors.isNotEmpty)
          Text(group.metadata.authors.join(', ')),
        const AppGap(20),
        FilledButton(
          onPressed: next == null ? null : () => run(() => reader(next.title!)),
          child: const Text('Continue reading'),
        ),
        if (group.metadata.description.isNotEmpty) ...[
          const AppGap(24),
          Text(group.metadata.description),
        ],
        const AppGap(24),
        Text('Titles', style: Theme.of(context).textTheme.titleLarge),
        const AppGap(12),
        for (final item in items) tile(item, false, false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    memory.changed();
    final allowed = widget.library.authorized(widget.collectionId);
    final collection = bundle?.catalog.collections
        .where((c) => c.id == widget.collectionId)
        .firstOrNull;
    final group = bundle?.catalog.groups
        .where((g) => g.id == widget.groupId)
        .firstOrNull;
    final items = !allowed || bundle == null ? <ReadingItem>[] : visible;
    return Scaffold(
      bottomNavigationBar: SharedAudioMiniPlayer(
        owner: widget.library.service.persistenceOwner,
      ),
      appBar: AppBar(
        bottom: widget.groupId != null || controller.selecting
            ? null
            : CollectionExperienceHeader(
                expanded: controlsExpanded,
                onExpanded: () {
                  if (controlsExpanded) FocusScope.of(context).unfocus();
                  setState(() => controlsExpanded = !controlsExpanded);
                },
                onScope: () => CollectionScopeRouter.choose(
                  context,
                  widget.library.service.persistenceOwner,
                  collection?.subtype ?? MediaSubtype.ebook,
                ),
                scope: collection?.name ?? 'Collection',
                overview: false,
                onOverview: () =>
                    widget.openSpace?.call(context, widget.collectionId),
                onBrowse: () {},
              ),
        title: Text(
          controller.selecting
              ? '${selected.length} selected'
              : group?.metadata.title ??
                    collection?.name ??
                    'Reading collection',
        ),
        actions: [
          if (allowed && collection != null && !controller.selecting) ...[
            if (widget.groupId == null)
              IconButton(
                tooltip: 'Collection settings',
                onPressed: () => run(() async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingCollectionSettingsPage(
                        library: widget.library,
                        collectionId: widget.collectionId,
                      ),
                    ),
                  );
                }),
                icon: const AppIcon(AppIconRole.settings),
              ),
            CollectionActionsMenu(
              tooltip: 'Collection actions',
              icon: const AppIcon(AppIconRole.menu),
              onSelected: (value) => run(() async {
                if (group != null &&
                    [
                      'settings',
                      'edit',
                      'artwork',
                      'metadata',
                    ].contains(value)) {
                  await action(
                    ReadingItem(group.id, group.metadata, null),
                    switch (value) {
                      'settings' => MediaActionId.settings,
                      'edit' => MediaActionId.editMetadata,
                      'artwork' => MediaActionId.chooseArtwork,
                      _ => MediaActionId.findMetadata,
                    },
                  );
                }
                if (value == 'order') await orderGroup();
                if (value == 'collectionSettings') {
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingCollectionSettingsPage(
                        library: widget.library,
                        collectionId: widget.collectionId,
                      ),
                    ),
                  );
                }
                if (value == 'readerSettings') {
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingScopedSettingsPage(
                        library: widget.library,
                        collectionId: widget.collectionId,
                        subtype: collection.subtype,
                      ),
                    ),
                  );
                }
                if (value == 'reset') {
                  if (!context.mounted) return;
                  await confirmBrowseReset(context, memory);
                }
                if (value == 'scan') await folderHealth();
                if (value == 'retry') await job.start([], retry: true);
                if (value == 'missing') {
                  final missing = bundle!.catalog.titles
                      .where(
                        (t) =>
                            t.catalog.id.collectionId == widget.collectionId &&
                            bundle!.management.entity(t.catalog.id).provider ==
                                '',
                      )
                      .toList();
                  controller.selected
                    ..clear()
                    ..addAll(missing.take(20).map((t) => t.catalog.id));
                  if (missing.length > 20) {
                    setState(() => controller.selecting = true);
                  } else if (missing.isNotEmpty) {
                    await startJob();
                  }
                }
                if (!context.mounted) return;
                if (value == 'tags') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingTagsPage(
                        library: widget.library,
                        collectionId: widget.collectionId,
                      ),
                    ),
                  );
                }
                if (!context.mounted) return;
                if (value == 'health') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingFolderHealthPage(
                        library: widget.library,
                        collectionId: widget.collectionId,
                      ),
                    ),
                  );
                }
                if (value == 'select') {
                  setState(() => controller.selecting = !controller.selecting);
                }
                if (value == 'jobs') await reviewJobs();
                if (value == 'notes') {
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ReadingAnnotationsPage(
                        library: widget.library,
                        collectionId: widget.collectionId,
                      ),
                    ),
                  );
                }
              }),
              itemBuilder: (_) => [
                if (group != null) ...mediaMetadataActions(settings: true),
                if (group == null)
                  const PopupMenuItem(
                    value: 'collectionSettings',
                    child: Text('Settings'),
                  ),
                if (group != null)
                  const PopupMenuItem(
                    value: 'order',
                    child: Text('Edit order'),
                  ),
                const PopupMenuItem(value: 'tags', child: Text('Manage tags')),
                if (group == null)
                  const PopupMenuItem(
                    value: 'readerSettings',
                    child: Text('Reader settings'),
                  ),
                PopupMenuItem(value: 'select', child: Text('Select items')),
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Reset browsing'),
                ),
                if (group == null)
                  const PopupMenuItem(
                    value: 'scan',
                    child: Text('Scan folders'),
                  ),
                if (group == null)
                  PopupMenuItem(
                    value: 'missing',
                    enabled: !job.running,
                    child: const Text('Fetch missing metadata'),
                  ),
                if (group == null)
                  PopupMenuItem(
                    value: 'retry',
                    enabled:
                        !job.running &&
                        job.entries.values.any((e) => e['status'] == 'failed'),
                    child: const Text('Retry failed metadata'),
                  ),
                PopupMenuItem(
                  value: 'jobs',
                  child: Text('Review metadata matches'),
                ),
                PopupMenuItem(
                  value: 'notes',
                  child: Text('Bookmarks and notes'),
                ),
                PopupMenuItem(value: 'health', child: Text('Folder health')),
              ],
            ),
          ],
        ],
      ),
      body: !allowed
          ? const Center(child: Text('Collection access is required.'))
          : collection == null && !controller.loading
          ? Center(
              child: Text(
                controller.error ?? 'This reading collection no longer exists.',
              ),
            )
          : group != null && !controller.selecting
          ? groupBody(group)
          : Column(
              children: [
                if (controller.loading) const LinearProgressIndicator(),
                if (scanning)
                  ListTile(
                    title: const Text('Scanning collection…'),
                    trailing: TextButton(
                      onPressed: () =>
                          widget.library.autoScans.cancel(widget.collectionId),
                      child: const Text('Cancel'),
                    ),
                  ),
                if (scanMessage != null)
                  TextButton(
                    onPressed: folderHealth,
                    child: Text(scanMessage!),
                  ),
                if (controller.error != null)
                  TextButton(onPressed: load, child: Text(controller.error!)),
                if (job.running)
                  ListTile(
                    title: Text('Metadata lookup ${job.done} of ${job.total}'),
                    trailing: TextButton(
                      onPressed: job.cancel,
                      child: const Text('Pause'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Visibility(
                    visible: controlsExpanded,
                    maintainState: true,
                    child: CollectionBrowseToolbar(
                      query: query,
                      onChanged: (_) => changed(),
                      onFilters: filters,
                      onView: viewSettings,
                      count: items.length,
                      filters: {
                        if (controller.filter != 'all')
                          readingStatusLabel(controller.filter): () {
                            controller.filter = 'all';
                            changed();
                          },
                        if (controller.tag.isNotEmpty)
                          controller.tag: () {
                            controller.tag = '';
                            changed();
                          },
                        if (author.isNotEmpty)
                          author: () {
                            author = '';
                            changed();
                          },
                        if (language.isNotEmpty)
                          language: () {
                            language = '';
                            changed();
                          },
                        if (controller.folder.isNotEmpty)
                          'Folder': () {
                            controller.folder = '';
                            changed();
                          },
                      },
                      onClearFilters: () {
                        controller.filter = 'all';
                        controller.tag = '';
                        controller.folder = '';
                        author = '';
                        language = '';
                        changed();
                      },
                    ),
                  ),
                ),
                if (controller.selecting)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            controller.selected.addAll(items.map((i) => i.id));
                          }),
                          child: const Text('Select all'),
                        ),
                        TextButton(
                          onPressed: () => setState(controller.selected.clear),
                          child: const Text('Clear'),
                        ),
                        TextButton(
                          onPressed: selected.isEmpty || busy
                              ? null
                              : () => run(editTags),
                          child: const Text('Edit tags'),
                        ),
                        TextButton(
                          onPressed: selected.isEmpty || busy
                              ? null
                              : () => run(makeGroup),
                          child: const Text('Move to series'),
                        ),
                        TextButton(
                          onPressed: selected.isEmpty || busy || job.running
                              ? null
                              : () => run(startJob),
                          child: const Text('Find metadata online'),
                        ),
                        TextButton(
                          onPressed: selected.isEmpty || busy
                              ? null
                              : () => run(() => markFinished(true)),
                          child: const Text('Mark finished'),
                        ),
                        TextButton(
                          onPressed: selected.isEmpty || busy
                              ? null
                              : () => run(() => markFinished(false)),
                          child: const Text('Mark unread'),
                        ),
                        TextButton(
                          onPressed: () => setState(controller.endSelection),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: bundle == null
                      ? const SizedBox()
                      : items.isEmpty
                      ? Center(
                          child: Text(
                            query.text.isNotEmpty ||
                                    controller.filter != 'all' ||
                                    author.isNotEmpty ||
                                    language.isNotEmpty ||
                                    controller.tag.isNotEmpty ||
                                    controller.folder.isNotEmpty
                                ? 'No matching titles.'
                                : 'No titles yet. Scan folders to add books.',
                          ),
                        )
                      : CollectionLayout(
                          layout: controller.layout,
                          cardSize:
                              ((bundle!.management.collections
                                              .where(
                                                (c) =>
                                                    c.collectionId ==
                                                    widget.collectionId,
                                              )
                                              .firstOrNull
                                              ?.cardSize ??
                                          180)
                                      as num)
                                  .toDouble(),
                          builder: (context, width, grid, compact) => grid
                              ? GridView.builder(
                                  controller: scroll,
                                  padding: AppSpacing.of(context).all(20),
                                  itemCount: items.length,
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: width + 24,
                                        mainAxisExtent:
                                            width * 1.5 +
                                            120 *
                                                MediaQuery.textScalerOf(context)
                                                    .scale(1),
                                        mainAxisSpacing: 12,
                                        crossAxisSpacing: 12,
                                      ),
                                  itemBuilder: (_, i) =>
                                      tile(items[i], true, compact),
                                )
                              : ListView.builder(
                                  controller: scroll,
                                  padding: AppSpacing.of(context).all(20),
                                  itemCount: items.length,
                                  itemBuilder: (_, i) =>
                                      tile(items[i], false, compact),
                                ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget tile(ReadingItem item, bool grid, bool compact) {
    final managed = bundle!.management.entity(item.id);
    final cover = readingCoverReference(bundle!, item.id);
    final menu = PopupMenuButton<Object>(
      tooltip: 'Actions for ${item.metadata.title}',
      icon: const AppIcon(AppIconRole.menu),
      onSelected: (a) => run(
        () => a == 'openWith'
            ? openEbookReader(
                context,
                widget.library.readerHost,
                item.title!,
                authorized: widget.library.authorized,
                choose: true,
              )
            : action(item, a as MediaActionId),
      ),
      itemBuilder: (_) => [
        if (item.title?.catalog.subtype == MediaSubtype.ebook)
          const PopupMenuItem(value: 'openWith', child: Text('Open with…')),
        for (final action in MediaActionRegistry.definitions)
          if (MediaActionRegistry.permitted(action.id, actionContext(item)))
            PopupMenuItem(value: action.id, child: Text(action.label)),
      ],
    );
    final art = ReadingCover(
      library: widget.library,
      reference: cover,
      crop: managed.coverMode == 'crop',
    );
    final title = Text(
      item.metadata.title,
      maxLines: grid ? 2 : 3,
      overflow: TextOverflow.ellipsis,
    );
    return MediaItemSelection(
      selected: controller.selecting
          ? controller.selected.contains(item.id)
          : null,
      onToggle: () => setState(() => controller.toggle(item)),
      reserveLeading: !grid,
      child: Card(
        margin: grid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            try {
              await open(item);
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not open this item. Check its source or access.',
                    ),
                  ),
                );
              }
            }
          },
          onLongPress: () => setState(() {
            controller.selecting = true;
            controller.toggle(item);
          }),
          child: grid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(aspectRatio: 2 / 3, child: art),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: title,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              item.group
                                  ? 'Series · ${readingStatusLabel(status(item))}'
                                  : '${readingRoleLabel(item.title!)} · ${readingStatusLabel(status(item))}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        menu,
                      ],
                    ),
                  ],
                )
              : ListTile(
                  leading: SizedBox(
                    width: compact ? 32 : 56,
                    height: compact ? 48 : 84,
                    child: art,
                  ),
                  title: title,
                  subtitle: compact
                      ? null
                      : Text(
                          '${item.metadata.authors.join(', ')}\n${item.group ? 'Series' : readingRoleLabel(item.title!)} · ${readingStatusLabel(status(item))}',
                        ),
                  trailing: controller.selecting ? null : menu,
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    query.removeListener(changed);
    job.removeListener(changed);
    memory.dispose();
    controller.dispose();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }
}

class ReadingTitleDetailsPage extends StatefulWidget {
  const ReadingTitleDetailsPage({
    super.key,
    required this.library,
    required this.identity,
    required this.actions,
    required this.open,
  });
  final ReadingLibrary library;
  final CatalogIdentity identity;
  final Future<void> Function(MediaActionId) actions;
  final Future<void> Function() open;
  @override
  State<ReadingTitleDetailsPage> createState() =>
      ReadingTitleDetailsPageState();
}

class ReadingTitleDetailsPageState extends State<ReadingTitleDetailsPage> {
  bool opening = false;
  ReadingBundle? bundle;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.identity.collectionId);
      final b = await widget.library.readCollection(
        widget.identity.collectionId,
      );
      if (mounted) setState(() => bundle = b);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load details.');
    }
  }

  Future<void> action(MediaActionId id) async {
    try {
      await widget.actions(id);
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this action. Retry.')),
        );
      }
    }
  }

  Future<void> open() async {
    if (opening) return;
    setState(() => opening = true);
    try {
      await widget.open();
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this title. Check its source and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> manage(String value, ReadingTitle title) async {
    try {
      widget.library.access(widget.identity.collectionId);
      final tags = (bundle!.management.entity(widget.identity).tags as List)
          .cast<String>();
      if (value == 'tags') {
        await readingFields(
          context,
          title: 'Edit tags',
          initial: {'tags': tags.join(', ')},
          labels: {'tags': 'Tags (separate with commas)'},
          save: (v) => widget.library.tags(widget.identity.collectionId, [
            widget.identity,
          ], normalizeTags(v['tags']!)),
        );
      } else if (value == 'favorite') {
        await widget.library.tags(
          widget.identity.collectionId,
          [widget.identity],
          ['Favorite'],
          operation: tags.any((t) => t.toLowerCase() == 'favorite')
              ? 'remove'
              : 'add',
        );
      } else if (value == 'finished') {
        final finished =
            bundle!.catalog.progress
                .where((p) => p.id == widget.identity)
                .firstOrNull
                ?.finished ??
            false;
        await widget.library.finished(widget.identity.collectionId, [
          widget.identity,
        ], !finished);
      } else if (value == 'role') {
        final chosen = await showDialog<ReadingRole>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Content role'),
            children: [
              for (final role in ReadingRole.values.where(
                (r) =>
                    title.catalog.subtype != MediaSubtype.ebook ||
                    r != ReadingRole.issue,
              ))
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, role),
                  child: Text(
                    '${role.name[0].toUpperCase()}${role.name.substring(1)}',
                  ),
                ),
            ],
          ),
        );
        if (chosen != null) {
          await widget.library.role(widget.identity, chosen);
        }
      }
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this change. Retry.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.library.authorized(widget.identity.collectionId)) {
      return const Scaffold(
        body: Center(child: Text('Collection access is required.')),
      );
    }
    final title = bundle?.catalog.titles
        .where((t) => t.catalog.id == widget.identity)
        .firstOrNull;
    if (title == null) {
      return Scaffold(
        bottomNavigationBar: SharedAudioMiniPlayer(
          owner: widget.library.service.persistenceOwner,
        ),
        appBar: AppBar(title: const Text('Details')),
        body: Center(child: Text(error ?? 'Loading details…')),
      );
    }
    final m = title.catalog.metadata,
        managed = bundle!.management.entity(widget.identity);
    final progress = bundle!.catalog.progress
        .where((p) => p.id == widget.identity)
        .firstOrNull;
    final location = progress?.location;
    final started = location is TextReadingLocation
        ? location.locator != '0'
        : location is PageReadingLocation &&
              (location.pageIndex > 0 || location.offset > 0);
    return Scaffold(
      bottomNavigationBar: SharedAudioMiniPlayer(
        owner: widget.library.service.persistenceOwner,
      ),
      appBar: AppBar(
        title: Text(m.title),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Title actions',
            icon: const AppIcon(AppIconRole.menu),
            itemBuilder: (_) => [
              ...mediaMetadataActions(settings: true),
              if (title.catalog.subtype == MediaSubtype.ebook)
                const PopupMenuItem(
                  value: 'openWith',
                  child: Text('Open with…'),
                ),
              const PopupMenuItem(value: 'tags', child: Text('Edit tags')),
              PopupMenuItem(
                value: 'favorite',
                child: Text(
                  (managed.tags as List).any(
                        (t) => t.toString().toLowerCase() == 'favorite',
                      )
                      ? 'Remove favorite'
                      : 'Favorite',
                ),
              ),
              PopupMenuItem(
                value: 'finished',
                child: Text(
                  progress?.finished == true ? 'Mark unread' : 'Mark completed',
                ),
              ),
              const PopupMenuItem(value: 'role', child: Text('Content role')),
              const PopupMenuItem(
                value: 'notes',
                child: Text('Bookmarks and notes'),
              ),
            ],
            onSelected: (value) async {
              if (value == 'openWith') {
                await openEbookReader(
                  context,
                  widget.library.readerHost,
                  title,
                  authorized: widget.library.authorized,
                  choose: true,
                );
              } else if ([
                'tags',
                'favorite',
                'finished',
                'role',
              ].contains(value)) {
                await manage(value, title);
              } else if (value == 'notes') {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingAnnotationsPage(
                      library: widget.library,
                      collectionId: widget.identity.collectionId,
                      titleId: widget.identity,
                    ),
                  ),
                );
                await load();
              } else {
                await action(switch (value) {
                  'settings' => MediaActionId.settings,
                  'edit' => MediaActionId.editMetadata,
                  'artwork' => MediaActionId.chooseArtwork,
                  _ => MediaActionId.findMetadata,
                });
              }
            },
          ),
        ],
      ),
      body: MediaDetailsBody(
        artworkAspectRatio: 2 / 3,
        artwork: ReadingCover(
          library: widget.library,
          reference: readingCoverReference(bundle!, widget.identity),
          crop: managed.coverMode == 'crop',
        ),
        children: [
          PluginDetailExtensions(
            collection: widget.identity.collectionId,
            kind: title.catalog.subtype.name == 'ebook'
                ? ExtensionMedia.ebook
                : ExtensionMedia.comic,
            titleId: widget.identity.entityId,
          ),
          Text(m.title, style: Theme.of(context).textTheme.headlineSmall),
          if (m.authors.isNotEmpty) ...[
            const AppGap(8),
            Text(m.authors.join(', ')),
          ],
          const AppGap(20),
          FilledButton(
            onPressed: !opening && title.catalog.sources.single.available
                ? open
                : null,
            child: Text(started ? 'Continue reading' : 'Read'),
          ),
          if (!title.catalog.sources.single.available)
            const Text('Source missing · check Folder health'),
          if (m.description.isNotEmpty) ...[
            const AppGap(24),
            Text(m.description),
          ],
          const AppGap(24),
          if (m.language.isNotEmpty) Text('Language: ${m.language}'),
          if (m.identifier.isNotEmpty) Text('Identifier: ${m.identifier}'),
          Text('Format: ${title.format.name.toUpperCase()}'),
        ],
      ),
    );
  }
}

class _ReadingJobResults extends StatefulWidget {
  const _ReadingJobResults({
    required this.job,
    required this.library,
    required this.provider,
  });
  final ReadingMetadataJob job;
  final ReadingLibrary library;
  final PublicationProvider provider;
  @override
  State<_ReadingJobResults> createState() => _ReadingJobResultsState();
}

class _ReadingJobResultsState extends State<_ReadingJobResults> {
  String? error;
  bool busy = false;
  final names = <String, String>{};
  @override
  void initState() {
    super.initState();
    widget.library
        .read()
        .then((b) {
          if (mounted) {
            setState(() {
              for (final t in b.catalog.titles.where(
                (t) => t.catalog.id.collectionId == widget.job.collectionId,
              )) {
                names[t.catalog.id.entityId] = t.catalog.title;
              }
            });
          }
        })
        .catchError((Object _) {});
  }

  Future<void> task(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Metadata lookup results')),
    body: !widget.library.authorized(widget.job.collectionId)
        ? const Center(child: Text('Collection access is required.'))
        : ListView(
            padding: AppSpacing.of(context).all(16),
            children: [
              Text(
                '${widget.job.done} of ${widget.job.total} searched · Review each edition before applying.',
              ),
              if (error != null) Text(error!),
              if (widget.job.remaining.isNotEmpty)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => task(() => widget.job.start([], resume: true)),
                  child: const Text('Resume lookup'),
                ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => task(() => widget.job.start([], retry: true)),
                child: const Text('Retry failed lookups'),
              ),
              for (final e in widget.job.entries.entries)
                ExpansionTile(
                  title: Text(
                    '${names[e.key] ?? 'Publication'} · ${e.value['status']}',
                  ),
                  subtitle: Text(e.value['error'] as String),
                  children: [
                    for (final row in e.value['candidates'] as List)
                      ListTile(
                        title: Text(row['values']['title'] as String),
                        subtitle: Text(
                          row['values']['edition'] as String? ?? '',
                        ),
                        onTap: busy
                            ? null
                            : () => task(() async {
                                final identity = CatalogIdentity(
                                  widget.job.collectionId,
                                  e.key,
                                  CatalogEntityKind.title,
                                );
                                final target = await ReadingMetadataTarget(
                                  widget.library,
                                  identity,
                                  widget.provider,
                                ).initialize();
                                if (!context.mounted) return;
                                final candidate = MetadataCandidate.fromJson(
                                  Map<String, dynamic>.from(row),
                                  provider: widget.provider.id,
                                  entity: target.entity,
                                  attribution: 'Imported metadata',
                                );
                                final saved = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MetadataReviewPage(
                                      target: target,
                                      candidate: candidate,
                                    ),
                                  ),
                                );
                                if (saved == true) {
                                  await widget.job.applied(e.key);
                                }
                              }),
                      ),
                  ],
                ),
            ],
          ),
  );
}
