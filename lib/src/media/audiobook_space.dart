import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';
import '../experience/navigation/browse_memory.dart';
import '../features/catalog/application/space_queries.dart';
import 'video_projections.dart';
import '../experience/navigation/navigation_coordinator.dart';
import '../experience/navigation/navigation_origin.dart';
import 'navigation_origin_controls.dart';
import 'media_ui_patterns.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../library/library_controller.dart';

import 'package:app_shell/app_shell.dart';

import '../space_preferences.dart';
import 'audio_library.dart';
import 'audio_models.dart';
import 'audiobook_cover.dart';
import 'audiobook_details.dart';
import 'audiobook_management.dart';
import 'audiobook_editor_page.dart';
import 'audiobook_player_page.dart';
import 'contracts.dart';
import 'grouping.dart';

class AudiobookSpace extends StatefulWidget {
  const AudiobookSpace({super.key, required this.library, this.collectionId});
  final LibraryController library;
  final String? collectionId;
  @override
  State<AudiobookSpace> createState() => _AudiobookSpaceState();
}

class _AudiobookSpaceState extends State<AudiobookSpace> {
  bool controlsExpanded = false;
  late final memory = BrowseMemory(
    preferences: widget.library.service.userPreferences,
    query: query,
    scroll: scroll,
    alive: () => mounted,
    capture: () => NavigationOrigin(
      routeId: 'audiobook-space',
      collectionId: widget.collectionId,
      query: query.text,
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
      tab: tab,
      sort: sort,
      filter: status,
      tag: author,
      layout: jsonEncode([layout, cardSize, descending]),
    ),
    defaults: () => NavigationOrigin(
      routeId: 'audiobook-space',
      collectionId: widget.collectionId,
      tab: 0,
    ),
    apply: (origin) {
      if (mounted) {
        setState(() {
          tab = origin.tab.clamp(0, 2);
        });
      }
    },
  );

  final preferences = SpacePreferences();
  String layout = 'grid', sort = 'title', status = 'all', author = '';
  double cardSize = 180;
  bool descending = false;
  Future<void> viewOptions() async {
    final value = await showCollectionView(
      context,
      layout: layout,
      sort: sort,
      sorts: const {'title': 'Title', 'author': 'Author'},
      cardSize: cardSize,
      descending: descending,
    );
    if (value != null && mounted) {
      setState(() {
        layout = value.layout;
        sort = value.sort;
        cardSize = value.cardSize;
        descending = value.descending;
      });
    }
  }

  Future<void> filterOptions() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheet) => ListView(
      shrinkWrap: true,
      padding: AppSpacing.of(context).all(24),
      children: [
        Text('Filters', style: Theme.of(sheet).textTheme.titleLarge),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Listening status'),
          items: [
            for (final e in const {
              'all': 'All',
              'unread': 'Not started',
              'progress': 'In progress',
              'completed': 'Completed',
            }.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) setState(() => status = v);
          },
        ),
        DropdownButtonFormField<String>(
          initialValue:
              books.any((b) => eligible(b) && b.metadata.author == author)
              ? author
              : '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Author'),
          items: [
            const DropdownMenuItem(value: '', child: Text('All authors')),
            for (final a
                in books
                    .where(eligible)
                    .map((b) => b.metadata.author)
                    .where((a) => a.isNotEmpty)
                    .toSet())
              DropdownMenuItem(
                value: a,
                child: Text(a, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => author = v);
          },
        ),
        FilledButton(
          onPressed: () => Navigator.pop(sheet),
          child: const Text('Done'),
        ),
      ],
    ),
  );
  Widget browseView(List<Audiobook> matches) => CustomScrollView(
    controller: scroll,
    slivers: [
      SliverPadding(
        padding: AppSpacing.of(context).all(20),
        sliver: SliverToBoxAdapter(
          child: Visibility(
            visible: controlsExpanded,
            maintainState: true,
            child: CollectionBrowseToolbar(
              query: query,
              onChanged: (_) => setState(() {}),
              onFilters: filterOptions,
              onView: viewOptions,
              count: matches.length,
              filters: {
                if (status != 'all')
                  status: () => setState(() => status = 'all'),
                if (author.isNotEmpty)
                  author: () => setState(() => author = ''),
              },
              onClearFilters: () => setState(() {
                status = 'all';
                author = '';
              }),
            ),
          ),
        ),
      ),
      if (matches.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching audiobooks.'),
          ),
        ),
      if (layout == 'grid' && display.artwork)
        SliverPadding(
          padding: AppSpacing.of(context).all(20),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: cardSize,
              mainAxisExtent: cardSize,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: matches.length,
            itemBuilder: (_, i) => AudiobookArtworkTile(
              title: matches[i].metadata.title,
              cover: matches[i].metadata.cover,
              onTap: () => open(matches[i]),
              menu: AudiobookActionMenu(
                book: matches[i],
                library: catalog,
                edit: () => edit(matches[i]),
                refresh: load,
              ),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: matches.length,
          itemBuilder: (_, i) => ListTile(
            dense: layout == 'compact',
            title: Text(matches[i].metadata.title),
            subtitle: Text(matches[i].metadata.author),
            onTap: () => open(matches[i]),
            trailing: AudiobookActionMenu(
              book: matches[i],
              library: catalog,
              edit: () => edit(matches[i]),
              refresh: load,
            ),
          ),
        ),
    ],
  );
  final query = TextEditingController();
  final scroll = ScrollController();
  final sections = SpaceController<Audiobook, MediaId>(identity: (b) => b.id)
    ..loading = true;
  List<Audiobook> get books => sections.items;
  Map<MediaId, AudiobookProgress> progress = {};
  Map<String, AudiobookSeriesMetadata> seriesMetadata = {};
  int get tab => sections.tab;
  set tab(int value) => sections.tab = value;
  bool get loading => sections.loading;
  set loading(bool value) => sections.loading = value;
  String? get error => sections.error;
  set error(String? value) => sections.error = value;
  SpaceDisplay get display => preferences.audiobooks;
  AudioLibrary get catalog => widget.library.audiobookCatalog();
  bool get local => widget.collectionId != null;
  SpaceScope get scope =>
      SpaceScope(MediaSubtype.audiobooks, collectionId: widget.collectionId);
  bool eligible(Audiobook book) => widget.library.collections.any(
    (c) =>
        c.id == book.id.collectionId &&
        scope.includes(
          c.catalogCollection,
          authorized: widget.library.canAccessCollection(c.id),
        ),
  );
  @override
  void initState() {
    super.initState();
    widget.library.addListener(changed);
    initialize();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> initialize() async {
    try {
      await preferences.load(widget.library.service.userPreferences);
      if (local) {
        final saved = await widget.library.spaces.read(
          MediaSubtype.audiobooks,
          widget.collectionId!,
        );
        display.restore(saved ?? SpaceDisplay().toJson());
      }
      if (!mounted) return;
      tab = 0;
      await load();
      if (mounted) await memory.restore();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not load space settings. Try again.';
        });
      }
    }
  }

  Future<void> load() async {
    final saved = <MediaId, AudiobookProgress>{};
    final metadata = <String, AudiobookSeriesMetadata>{};
    final applied = await sections.load(() async {
      final all = sections.eligible(await catalog.query(), eligible);
      for (final book in all) {
        final value = await widget.library
            .audiobookCatalog(collectionId: book.id.collectionId)
            .progress
            .read(book.id);
        if (value is AudiobookProgress) saved[book.id] = value;
      }
      for (final group in audiobookSeries(all)) {
        final value = await catalog.seriesMetadata(group.id);
        if (value != null) metadata[group.id] = value;
      }
      return all.where(eligible).toList();
    }, failure: 'Could not load audiobooks. Try again.');
    if (mounted) {
      setState(() {
        if (applied) {
          progress = saved;
          seriesMetadata = metadata;
        }
      });
    }
  }

  @override
  void dispose() {
    memory.dispose();
    widget.library.removeListener(changed);
    sections.dispose();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> edit(Audiobook book) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AudiobookEditorPage(
          library: catalog,
          files: book.files,
          existing: book,
        ),
      ),
    );
    await load();
  }

  Future<void> open(Audiobook book, {bool forcePlay = false}) async {
    if (!eligible(book)) {
      await load();
      return;
    }
    final owner = widget.library.collections.firstWhere(
      (c) => c.id == book.id.collectionId,
    );
    if (!local) widget.library.beginCollectionSession(owner.id);
    try {
      await openAudiobookTitle(
        context,
        catalog,
        owner,
        book,
        (rate) async {
          if (!eligible(book) || !mounted) return;
          final latest = (await catalog.query())
              .where((b) => b.id == book.id)
              .firstOrNull;
          if (latest == null || !mounted) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => AudiobookPlayerPage(
                book: latest,

                catalog: widget.library.audiobookCatalog(
                  collectionId: latest.id.collectionId,
                ),
                initialRate: rate,
              ),
            ),
          );
        },
        () => edit(book),
        forcePlay: forcePlay,
        origin: NavigationOrigin(
          routeId: 'audiobook-space',
          collectionId: widget.collectionId,
          query: query.text,
          tab: tab,
          scrollOffset: scroll.hasClients
              ? scroll.offset.clamp(0, double.infinity)
              : 0,
        ),
        restore: (origin) => restoreOrigin(
          context,
          origin,
          query: query,
          scroll: scroll,
          controls: () {
            if (mounted) setState(() => tab = origin.tab);
          },
        ),
      );
    } finally {
      if (!local) widget.library.endCollectionSession();
    }
    await load();
  }

  Future<void> series(MediaGroup<Audiobook> group) =>
      NavigationCoordinator.forOwner(widget.library.service.persistenceOwner)
          .run(
            'series:${group.id}',
            () => _series(group),
            origin: NavigationOrigin(
              routeId: 'audiobook-space',
              collectionId: widget.collectionId,
              query: query.text,
              tab: tab,
              scrollOffset: scroll.hasClients
                  ? scroll.offset.clamp(0, double.infinity)
                  : 0,
            ),
            restore: (origin) => restoreOrigin(
              context,
              origin,
              query: query,
              scroll: scroll,
              controls: () {
                if (mounted) setState(() => tab = origin.tab);
              },
            ),
          );
  Future<void> _series(MediaGroup<Audiobook> group) async {
    if (!group.children.every(eligible)) return;
    if (!local) {
      widget.library.beginCollectionSession(
        group.children.first.id.collectionId,
      );
    }
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AudiobookSeriesPage(
            group: group,
            library: catalog,
            openBook: open,
            playBook: (b) => open(b, forcePlay: true),
            editBook: edit,
          ),
        ),
      );
    } finally {
      if (!local) widget.library.endCollectionSession();
    }
    await load();
  }

  Future<void> settings() async {
    final draft = SpaceDisplay()..restore(display.toJson());
    final choices = books.where(eligible).toList();
    draft.pins.removeWhere(
      (key) => !choices.any((b) => audiobookShowcaseKey(b) == key),
    );
    String? failure;
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewPaddingOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Audiobooks settings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const AppGap(24),
              DropdownButtonFormField<String>(
                icon: const AppIcon(AppIconRole.expand),
                initialValue: draft.source == 'pinned' ? 'pinned' : 'recent',
                decoration: const InputDecoration(
                  labelText: 'Showcase artwork',
                ),
                items: const [
                  DropdownMenuItem(value: 'recent', child: Text('Automatic')),
                  DropdownMenuItem(
                    value: 'pinned',
                    child: Text('Selected titles'),
                  ),
                ],
                onChanged: saving
                    ? null
                    : (v) => update(() => draft.source = v!),
              ),
              if (draft.source == 'pinned') ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Select up to three titles. Use the arrows to change their order.',
                  ),
                ),
                for (var i = 0; i < draft.pins.length; i++)
                  ListTile(
                    title: Text(
                      choices
                          .firstWhere(
                            (b) => audiobookShowcaseKey(b) == draft.pins[i],
                          )
                          .metadata
                          .title,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Move up',
                          icon: const AppIcon(AppIconRole.sortAscending),
                          onPressed: saving || i == 0
                              ? null
                              : () => update(() {
                                  final key = draft.pins.removeAt(i);
                                  draft.pins.insert(i - 1, key);
                                }),
                        ),
                        IconButton(
                          tooltip: 'Remove selection',
                          icon: const AppIcon(AppIconRole.close),
                          onPressed: saving
                              ? null
                              : () => update(() => draft.pins.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                for (final book in choices.where(
                  (b) => !draft.pins.contains(audiobookShowcaseKey(b)),
                ))
                  ListTile(
                    title: Text(book.metadata.title),
                    subtitle: Text(audiobookSeriesTitle(book)),
                    trailing: const AppIcon(AppIconRole.add),
                    onTap: saving || draft.pins.length >= 3
                        ? null
                        : () => update(
                            () => draft.pins.add(audiobookShowcaseKey(book)),
                          ),
                  ),
              ],
              const AppGap(24),

              InterfaceSwitchListTile(
                title: const Text('Hide finished'),
                subtitle: const Text(
                  'Browsing only. Continue listening stays available.',
                ),
                value: draft.hideWatched,
                onChanged: saving
                    ? null
                    : (v) => update(() => draft.hideWatched = v),
              ),
              InterfaceSwitchListTile(
                title: const Text('Show artwork'),
                value: draft.artwork,
                onChanged: saving
                    ? null
                    : (v) => update(() => draft.artwork = v),
              ),
              InterfaceSwitchListTile(
                title: const Text('Show item and collection counts'),
                value: draft.counts,
                onChanged: saving
                    ? null
                    : (v) => update(() => draft.counts = v),
              ),

              if (failure != null) Text(failure!),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final old = display.toJson();
                        update(() => saving = true);
                        display.restore(draft.toJson());
                        try {
                          if (local) {
                            await widget.library.spaces.save(
                              MediaSubtype.audiobooks,
                              widget.collectionId!,
                              display.toJson(),
                            );
                          } else {
                            await preferences.save(
                              widget.library.service.userPreferences,
                            );
                          }
                          if (sheet.mounted) Navigator.pop(sheet);
                        } catch (_) {
                          display.restore(old);
                          if (sheet.mounted) {
                            update(() {
                              saving = false;
                              failure =
                                  'Could not save space settings. Try again.';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget grid(List<Audiobook> values) => display.artwork
      ? MediaArtworkGrid(
          children: [
            for (final book in values)
              AudiobookArtworkTile(
                title: book.metadata.title,
                menu: AudiobookActionMenu(
                  book: book,
                  library: catalog,
                  edit: () => edit(book),
                  refresh: load,
                ),
                cover: book.metadata.cover,
                onTap: () => open(book),
              ),
          ],
        )
      : Column(
          children: [
            for (final book in values)
              Card(
                child: ListTile(
                  title: Text(book.metadata.title),
                  trailing: AudiobookActionMenu(
                    book: book,
                    library: catalog,
                    edit: () => edit(book),
                    refresh: load,
                  ),
                  onTap: () => open(book),
                ),
              ),
          ],
        );
  Widget seriesGrid(List<MediaGroup<Audiobook>> groups) {
    String title(MediaGroup<Audiobook> group) =>
        seriesMetadata[group.id]?.title ?? group.title;
    String cover(MediaGroup<Audiobook> group) =>
        seriesMetadata[group.id]?.cover.isNotEmpty == true
        ? seriesMetadata[group.id]!.cover
        : group.children.first.metadata.cover;
    return display.artwork
        ? MediaArtworkGrid(
            children: [
              for (final group in groups)
                AudiobookArtworkTile(
                  title: title(group),
                  cover: cover(group),
                  onTap: () => series(group),
                ),
            ],
          )
        : Column(
            children: [
              for (final group in groups)
                Card(
                  child: ListTile(
                    title: Text(title(group)),
                    subtitle: Text('${group.children.length} audiobooks'),
                    trailing: const AppIcon(AppIconRole.disclosure),
                    onTap: () => series(group),
                  ),
                ),
            ],
          );
  }

  @override
  Widget build(BuildContext context) {
    memory.changed();
    sections.query = query.text;
    final available = sections.eligible(books, eligible);
    final browsing = sections.browsing(
      available,
      hideCompleted: display.hideWatched,
      completed: (b) => progress[b.id]?.finished == true,
    );
    final listening = available
        .where(
          (b) => progress[b.id] != null && progress[b.id]!.finished == false,
        )
        .toList();
    final matches = browsing
        .where(
          (b) =>
              audiobookSearchText(
                b,
                series: seriesMetadata[audiobookSeriesIdentity(b)],
              ).contains(query.text.trim().toLowerCase()) &&
              (author.isEmpty || b.metadata.author == author) &&
              (status == 'all' ||
                  (status == 'completed'
                      ? progress[b.id]?.finished == true
                      : status == 'progress'
                      ? progress[b.id] != null &&
                            progress[b.id]?.finished != true
                      : progress[b.id] == null)),
        )
        .toList();
    matches.sort((a, b) {
      final v = (sort == 'author' ? a.metadata.author : a.metadata.title)
          .toLowerCase()
          .compareTo(
            (sort == 'author' ? b.metadata.author : b.metadata.title)
                .toLowerCase(),
          );
      return descending ? -v : v;
    });
    return SpaceExitGuard(
      preferences: preferences,
      videos: false,
      name: 'Audiobooks',
      exitMessage: local ? 'Return to this collection?' : null,
      display: display,
      child: Scaffold(
        appBar: AppBar(
          bottom: CollectionExperienceHeader(
            expanded: controlsExpanded,
            onExpanded: () {
              if (controlsExpanded) FocusScope.of(context).unfocus();
              setState(() => controlsExpanded = !controlsExpanded);
            },
            onScope: () => CollectionScopeRouter.choose(
              context,
              widget.library.service.persistenceOwner,
              MediaSubtype.audiobooks,
            ),
            scope: local
                ? widget.library.collections
                      .firstWhere((c) => c.id == widget.collectionId)
                      .name
                : 'All collections',
            overview: tab == 0,
            onOverview: () => setState(() => tab = 0),
            onBrowse: () {
              if (local && Navigator.canPop(context)) {
                Navigator.maybePop(context);
              } else {
                setState(() => tab = 1);
              }
            },
          ),
          title: const Text('Audiobooks'),
          actions: [
            BrowseResetButton(memory: memory),
            IconButton(
              tooltip: 'Space settings',
              onPressed: loading ? null : settings,
              icon: const AppIcon(AppIconRole.settings),
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : tab != 0
            ? RefreshIndicator(onRefresh: load, child: browseView(matches))
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  controller: scroll,
                  padding: AppSpacing.of(context).all(20),
                  children: [
                    if (error != null) ...[
                      Text(error!),
                      TextButton(
                        onPressed: initialize,
                        child: const Text('Retry'),
                      ),
                    ],
                    if (available.isEmpty)
                      Text(
                        local
                            ? 'No audiobooks in this collection. Scan its folders to add titles.'
                            : 'No audiobooks. Include an unlocked audiobook collection in this space.',
                      ),
                    if (display.counts)
                      Text(
                        '${available.length} ${available.length == 1 ? 'audiobook' : 'audiobooks'} · ${available.map((b) => b.id.collectionId).toSet().length} ${available.map((b) => b.id.collectionId).toSet().length == 1 ? 'collection' : 'collections'}',
                      ),
                    const AppGap(16),
                    if (tab == 0) ...[
                      if (display.source == 'pinned' &&
                          audiobookShowcaseTitles(
                            available,
                            display,
                          ).isNotEmpty) ...[
                        Text(
                          'Showcase',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const AppGap(12),
                        grid(audiobookShowcaseTitles(available, display)),
                        const AppGap(24),
                      ],
                      Text(
                        'Continue listening',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const AppGap(12),
                      if (listening.isEmpty)
                        const Text('No audiobooks in progress.')
                      else
                        grid(listening),
                      const AppGap(24),
                      Text(
                        'Series',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const AppGap(12),
                      seriesGrid(audiobookSeries(browsing)),
                    ] else ...[
                      if (tab == 1) ...[
                        TextField(
                          controller: query,
                          decoration: const InputDecoration(
                            labelText: 'Search audiobooks',
                            prefixIcon: AppIcon(AppIconRole.search),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const AppGap(16),
                      ],
                      grid(tab == 1 ? matches : browsing),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

/// Callers supply only titles currently eligible for their space.
String audiobookShowcaseKey(Audiobook book) =>
    jsonEncode([book.id.collectionId, book.id.itemId]);
List<Audiobook> audiobookShowcaseTitles(
  List<Audiobook> eligible,
  SpaceDisplay display,
) =>
    SpaceController<Audiobook, String>(identity: audiobookShowcaseKey)
        .showcase(eligible, display.pins, pinned: display.source == 'pinned');
