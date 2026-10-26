import '../features/catalog/application/reading_views.dart';
import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../features/catalog/application/space_queries.dart';
import '../experience/navigation/browse_memory.dart';
import '../experience/navigation/navigation_origin.dart';
import '../experience/actions/media_actions.dart';

import 'package:app_shell/app_shell.dart';

import '../media/media_ui_patterns.dart';
import '../space_preferences.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_management.dart';
import 'reading_app_controller.dart';
import 'reading_collection_page.dart';
import '../features/metadata/application/reading_metadata_target.dart';
import 'reading_metadata_page.dart';
import 'reading_workflow_widgets.dart';
import 'reader_opening.dart';
import 'comic_reader_page.dart';

Future<void> openReadingCollection(
  BuildContext context,
  ReadingAppController app,
  String id, {
  bool scan = false,
  bool showJobs = false,
}) async {
  if (!await app.unlock(id) || !context.mounted) return;
  try {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReadingAccessGuard(
          controller: app,
          collectionId: id,
          child: ReadingCollectionPage(
            library: app.library,
            collectionId: id,
            scanOnOpen: scan,
            showJobs: showJobs,
            openTitle: (context, title) =>
                openReadingTitle(context, app, title, immediate: true),
            openSpace: (context, id) => openReadingSpace(
              context,
              app,
              SpaceScope(
                app.bundle!.catalog.collections
                    .singleWhere((c) => c.id == id)
                    .subtype,
                collectionId: id,
              ),
            ),
          ),
        ),
      ),
    );
  } finally {
    app.endSession(id);
    await app.load();
  }
}

Future<void> openReadingSpace(
  BuildContext context,
  ReadingAppController app,
  SpaceScope scope,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ReadingAccessGuard(
        controller: app,
        collectionId: scope.collectionId,
        child: ReadingSpace(app: app, scope: scope),
      ),
    ),
  );
  await app.load();
}

Future<void> openReadingTitle(
  BuildContext context,
  ReadingAppController app,
  ReadingTitle title, {
  bool immediate = false,
}) async {
  final generation = app.libraryGeneration;
  if (!app.canAccess(title.catalog.id.collectionId)) return;
  Future<void> read() async {
    var current = title;
    while (context.mounted && app.canAccess(current.catalog.id.collectionId)) {
      final opening = current;
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingAccessGuard(
            controller: app,
            collectionId: opening.catalog.id.collectionId,
            child: _ReaderEntry(app: app, title: opening),
          ),
        ),
      );
      await app.load();
      if (generation != app.libraryGeneration) return;
      if (!app.finished(current) || !context.mounted) return;
      final next = app.nextInSeries(current);
      if (next == null) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Next unread'),
          content: Text(
            '${next.catalog.metadata.title}\n${readingRoleLabel(next)} · ${next.format.name.toUpperCase()}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Open'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      current = next;
    }
  }

  final preferences = app.bundle!.management.collections
      .where((r) => r.collectionId == title.catalog.id.collectionId)
      .firstOrNull;
  if (immediate || preferences?.openAction == 'open') {
    await read();
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (detailsContext) => ReadingAccessGuard(
        controller: app,
        collectionId: title.catalog.id.collectionId,
        child: ReadingTitleDetailsPage(
          library: app.library,
          identity: title.catalog.id,
          open: read,
          actions: (action) async {
            if (!app.canAccess(title.catalog.id.collectionId)) return;
            final provider = app.library.metadataJobs.provider;
            final Widget page;
            if (action == MediaActionId.settings) {
              page = ReadingScopedSettingsPage(
                library: app.library,
                collectionId: title.catalog.id.collectionId,
                subtype: title.catalog.subtype,
                identity: title.catalog.id,
              );
            } else if (action == MediaActionId.chooseArtwork) {
              page = ReadingArtworkPage(
                library: app.library,
                identity: title.catalog.id,
                provider: provider,
              );
            } else if (action == MediaActionId.findMetadata) {
              final target = await ReadingMetadataTarget(
                app.library,
                title.catalog.id,
                provider,
              ).initialize();
              page = ReadingMetadataPage(target: target);
            } else {
              final fresh = (await app.library.read()).catalog.titles
                  .singleWhere((t) => t.catalog.id == title.catalog.id)
                  .catalog
                  .metadata;
              if (!detailsContext.mounted) return;
              await readingFields(
                detailsContext,
                title: 'Edit metadata',
                initial: {
                  'title': fresh.title,
                  'authors': fresh.authors.join('\n'),
                  'description': fresh.description,
                  'language': fresh.language,
                  'identifier': fresh.identifier,
                },
                multiline: {'authors', 'description'},
                labels: {
                  'title': 'Title',
                  'authors': 'Authors (one per line)',
                  'description': 'Description',
                  'language': 'Language',
                  'identifier': 'Identifier',
                },
                save: (v) => app.library.metadata(title.catalog.id, {
                  ...v,
                  'authors': v['authors']!
                      .split('\n')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toSet()
                      .toList(),
                }),
              );
              return;
            }
            if (!detailsContext.mounted) return;
            await Navigator.push(
              detailsContext,
              MaterialPageRoute<void>(
                builder: (_) => ReadingAccessGuard(
                  controller: app,
                  collectionId: title.catalog.id.collectionId,
                  child: page,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await app.load();
}

/// A nested navigator keeps reader-owned dialogs inside the live access boundary.
class _ReaderEntry extends StatefulWidget {
  const _ReaderEntry({required this.app, required this.title});
  final ReadingAppController app;
  final ReadingTitle title;
  @override
  State<_ReaderEntry> createState() => _ReaderEntryState();
}

class _ReaderEntryState extends State<_ReaderEntry> {
  final navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<void>(
    onPopWithResult: (_) => navigator.currentState?.maybePop(),
    child: Navigator(
      key: navigator,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (inner) => _ReaderLauncher(
          app: widget.app,
          title: widget.title,
          exit: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    ),
  );
}

class _ReaderLauncher extends StatefulWidget {
  const _ReaderLauncher({
    required this.app,
    required this.title,
    required this.exit,
  });
  final ReadingAppController app;
  final ReadingTitle title;
  final VoidCallback exit;
  @override
  State<_ReaderLauncher> createState() => _ReaderLauncherState();
}

class _ReaderLauncherState extends State<_ReaderLauncher> {
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => launch());
  }

  Future<void> launch() async {
    try {
      if (widget.title.catalog.subtype == MediaSubtype.ebook) {
        await openEbookReader(
          context,
          widget.app.library.readerHost,
          widget.title,
          authorized: widget.app.canAccess,
        );
      } else {
        await openComicReader(
          context,
          widget.app.library.readerHost,
          widget.title,
          authorized: widget.app.canAccess,
        );
      }
      if (mounted) widget.exit();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not open this title. Check Folder health.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: error == null
          ? const CircularProgressIndicator()
          : TextButton(onPressed: widget.exit, child: Text(error!)),
    ),
  );
}

class ReadingSpace extends StatefulWidget {
  const ReadingSpace({super.key, required this.app, required this.scope});
  final ReadingAppController app;
  final SpaceScope scope;
  @override
  State<ReadingSpace> createState() => _ReadingSpaceState();
}

class _ReadingSpaceState extends State<ReadingSpace> {
  bool controlsExpanded = false;
  final controller = SpaceController<ReadingTitle, CatalogIdentity>(
    identity: (t) => t.catalog.id,
  );
  final query = TextEditingController();
  final scroll = ScrollController();
  bool browsingReady = false;
  late final memory = BrowseMemory(
    preferences: app.service.userPreferences,
    query: query,
    scroll: scroll,
    alive: () => mounted,
    contentReady: () => browsingReady,
    capture: () => NavigationOrigin(
      routeId: 'reading-space:${widget.scope.subtype.name}',
      collectionId: widget.scope.collectionId,
      query: query.text,
      tab: controller.tab,
      tag: tag,
      folder: folder,
      filter: jsonEncode([
        status,
        author,
        language,
        list,
        cardSize,
        descending,
      ]),
      sort: sort,
      layout: layout,
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
    ),
    defaults: () => NavigationOrigin(
      routeId: 'reading-space:${widget.scope.subtype.name}',
      collectionId: widget.scope.collectionId,
      tab: 0,
    ),
    apply: (origin) {
      if (!mounted) return;
      setState(() {
        controller.tab = origin.tab.clamp(0, 2);
        sort = {'title', 'author', 'source'}.contains(origin.sort)
            ? origin.sort
            : 'title';
        layout = {'grid', 'list', 'compact'}.contains(origin.layout)
            ? origin.layout
            : 'list';
        cardSize = 180;
        descending = false;
        tag = origin.tag;
        folder = origin.folder;
        try {
          final values = jsonDecode(origin.filter) as List;
          status = values[0] as String;
          author = values[1] as String;
          language = values[2] as String;
          list = values[3] as String;
          if (values.length > 4 && values[4] is num) {
            cardSize = (values[4] as num).toDouble().clamp(100, 280);
          }
          if (values.length > 5 && values[5] is bool) {
            descending = values[5] as bool;
          }
          if (!{'all', 'unread', 'progress', 'completed'}.contains(status)) {
            status = 'all';
          }
        } catch (_) {
          status = 'all';
          author = '';
          language = '';
          list = '';
        }
        showFilters =
            tag.isNotEmpty ||
            folder.isNotEmpty ||
            status != 'all' ||
            author.isNotEmpty ||
            language.isNotEmpty;
      });
    },
  );
  final preferences = SpacePreferences();
  SpaceDisplay display = SpaceDisplay();
  String status = 'all',
      tag = '',
      author = '',
      language = '',
      folder = '',
      list = '';
  String sort = 'title', layout = 'list';
  double cardSize = 180;
  bool descending = false;
  String? error;
  bool allowExit = false, saving = false, showFilters = false;
  ReadingAppController get app => widget.app;
  String get label =>
      widget.scope.subtype == MediaSubtype.ebook ? 'Ebooks' : 'Comics';
  List<ReadingTitle> get eligible => app.eligible(widget.scope);
  @override
  void initState() {
    super.initState();
    app.addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) setState(() {});
  }

  Future<void> load() async {
    await app.load();
    await preferences.load(app.service.userPreferences);
    final global = widget.scope.subtype == MediaSubtype.ebook
        ? preferences.ebook
        : preferences.comics;
    final local = (app.bundle?.management.spaces ?? [])
        .where((r) => r.collectionId == widget.scope.collectionId)
        .firstOrNull;
    if (mounted) {
      setState(() {
        display = SpaceDisplay()
          ..restore(
            local == null
                ? global.toJson()
                : {
                    'source': local.source,
                    'artwork': local.artwork,
                    'counts': local.counts,
                    'confirmExit': local.confirmExit,
                    'hideWatched': local.hideWatched,
                    'startTab': local.startTab,
                    'pins': local.pins,
                  },
          );
        controller.tab = 0;
        browsingReady = true;
      });
      await memory.restore();
    }
  }

  @override
  void dispose() {
    app.removeListener(changed);
    memory.dispose();
    controller.dispose();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
      await app.load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save. Your previous values are retained.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> cacheSettings() async {
    await run(() async {
      final bytes = await app.library.cacheBytes();
      if (!mounted) return;
      final clear = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Reader cache'),
          content: Text(
            '${(bytes / 1048576).toStringAsFixed(1)} MiB of temporary reader files. Files used by open readers, source files and saved covers are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Clear unused cache'),
            ),
          ],
        ),
      );
      if (clear == true) {
        await app.library.clearIdleCache();
      }
    });
  }

  Future<void> settings() async {
    final draft = SpaceDisplay()..restore(display.toJson());
    final allowed = eligible.map((t) => readingKey(t.catalog.id)).toSet();
    draft.pins.removeWhere((key) => !allowed.contains(key));
    bool busy = false;
    String? failure;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: AppSpacing.of(context).all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$label space settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const AppGap(24),

                  DropdownButtonFormField<String>(
                    icon: const AppIcon(AppIconRole.expand),
                    initialValue: draft.source,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Showcase artwork',
                    ),
                    items: [
                      for (final v in [
                        'recent',
                        'favorites',
                        'progress',
                        'pinned',
                      ])
                        DropdownMenuItem(
                          value: v,
                          child: Text(
                            {
                              'recent': 'Recently added',
                              'favorites': 'Favorites',
                              'progress': 'Continue reading',
                              'pinned': 'Pinned titles',
                            }[v]!,
                          ),
                        ),
                    ],
                    onChanged: (v) => update(() => draft.source = v!),
                  ),
                  SwitchListTile(
                    title: const Text('Show artwork'),
                    value: draft.artwork,
                    onChanged: (v) => update(() => draft.artwork = v),
                  ),
                  SwitchListTile(
                    title: const Text('Show counts'),
                    value: draft.counts,
                    onChanged: (v) => update(() => draft.counts = v),
                  ),
                  SwitchListTile(
                    title: const Text('Hide completed in library'),
                    value: draft.hideWatched,
                    onChanged: (v) => update(() => draft.hideWatched = v),
                  ),

                  if (draft.pins.isNotEmpty)
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: draft.pins.length,
                      onReorderItem: (oldIndex, newIndex) => update(
                        () => draft.pins.insert(
                          newIndex,
                          draft.pins.removeAt(oldIndex),
                        ),
                      ),
                      itemBuilder: (context, index) => ListTile(
                        key: ValueKey('reading-pin:${draft.pins[index]}'),
                        title: Text(
                          '${index + 1}. ${eligible.where((t) => readingKey(t.catalog.id) == draft.pins[index]).first.catalog.metadata.title}',
                        ),
                      ),
                    ),
                  const Text('Pin up to three showcase titles'),
                  for (final t in eligible)
                    CheckboxListTile(
                      title: Text(t.catalog.metadata.title),
                      value: draft.pins.contains(readingKey(t.catalog.id)),
                      onChanged:
                          draft.pins.length >= 3 &&
                              !draft.pins.contains(readingKey(t.catalog.id))
                          ? null
                          : (v) => update(() {
                              final key = readingKey(t.catalog.id);
                              if (v == true && draft.pins.length < 3) {
                                draft.pins.add(key);
                              } else if (v != true) {
                                draft.pins.remove(key);
                              }
                            }),
                    ),

                  if (failure != null) Text(failure!),
                  const AppGap(24),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            update(() {
                              busy = true;
                              failure = null;
                            });
                            try {
                              ReadingManagement.validateDisplay(draft.toJson());
                              if (widget.scope.local) {
                                await app.library.saveSpace(
                                  widget.scope.collectionId!,
                                  draft.toJson(),
                                );
                              } else {
                                final target =
                                    widget.scope.subtype == MediaSubtype.ebook
                                    ? preferences.ebook
                                    : preferences.comics;
                                final before = target.toJson();
                                target.restore(draft.toJson());
                                try {
                                  await preferences.save(
                                    app.service.userPreferences,
                                  );
                                } catch (_) {
                                  target.restore(before);
                                  rethrow;
                                }
                              }
                              if (mounted) setState(() => display = draft);
                              if (sheet.mounted) Navigator.pop(sheet);
                            } catch (_) {
                              if (sheet.mounted) {
                                update(() {
                                  busy = false;
                                  failure =
                                      'Could not save space settings. Retry.';
                                });
                              }
                            }
                          },
                    child: Text(busy ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> deleteList(ReadingListView row) async {
    await readingFields(
      context,
      title: 'Delete reading list?',
      initial: {},
      saveLabel: 'Delete',
      message:
          'Remove “${row.name}”? The titles and their reading progress are kept.',
      save: (_) async {
        await app.deleteList(row.collectionId, row.id);
        if (mounted) {
          setState(() {
            if (list == '${row.collectionId}:${row.id}') list = '';
          });
        }
      },
    );
  }

  Future<void> editList({ReadingListView? existing}) async {
    final owners = app.bundle!.catalog.collections
        .where((c) => eligible.any((t) => t.catalog.id.collectionId == c.id))
        .toList();
    if (owners.isEmpty) return;
    String owner = existing?.collectionId ?? owners.first.id;
    final name = TextEditingController(text: existing?.name ?? '');
    final selected = (existing?.titles as List? ?? []).cast<String>().toSet();
    String? failure;
    bool working = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              existing == null ? 'New reading list' : 'Edit reading list',
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'List name'),
                    ),
                    if (existing == null)
                      DropdownButtonFormField<String>(
                        icon: const AppIcon(AppIconRole.expand),
                        initialValue: owner,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Collection',
                        ),
                        items: [
                          for (final c in owners)
                            DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: working
                            ? null
                            : (v) => update(() {
                                owner = v!;
                                selected.clear();
                              }),
                      ),
                    for (final t in eligible.where(
                      (t) => t.catalog.id.collectionId == owner,
                    ))
                      CheckboxListTile(
                        title: Text(t.catalog.metadata.title),
                        value: selected.contains(t.catalog.id.entityId),
                        onChanged: working
                            ? null
                            : (v) => update(() {
                                if (v == true) {
                                  selected.add(t.catalog.id.entityId);
                                } else {
                                  selected.remove(t.catalog.id.entityId);
                                }
                              }),
                      ),
                    if (failure != null) Text(failure!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: working ? null : () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: working
                    ? null
                    : () async {
                        if (name.text.trim().isEmpty) {
                          update(() => failure = 'Enter a list name.');
                          return;
                        }
                        update(() => working = true);
                        try {
                          await app.saveList(
                            owner,
                            existing?.id ??
                                'list-${DateTime.now().microsecondsSinceEpoch}',
                            name.text.trim(),
                            selected.toList(),
                          );
                          if (dialog.mounted) Navigator.pop(dialog);
                        } catch (_) {
                          if (dialog.mounted) {
                            update(() {
                              working = false;
                              failure =
                                  'Could not save. Your draft is retained.';
                            });
                          }
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
    }
    await app.load();
  }

  bool favorite(ReadingTitle t) =>
      (app.bundle!.management.entity(t.catalog.id).tags as List).any(
        (v) => v.toString().toLowerCase() == 'favorite',
      );
  Widget coverTile(ReadingTitle t, {bool next = false}) => InkWell(
    onTap: () =>
        next ? previewNext(t) : run(() => openReadingTitle(context, app, t)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (display.artwork)
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ReadingCover(
              library: app.library,
              reference: app.cover(t),
              crop:
                  app.bundle!.management.entity(t.catalog.id).coverMode ==
                  'crop',
            ),
          ),
        const AppGap(8),
        Text(
          t.catalog.metadata.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          t.catalog.metadata.authors.join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
  Widget tile(ReadingTitle t, {bool next = false}) => ListTile(
    dense: controller.tab != 0 && layout == 'compact',
    leading: display.artwork
        ? SizedBox(
            width: 40,
            height: 60,
            child: ReadingCover(
              library: app.library,
              reference: app.cover(t),
              crop:
                  app.bundle!.management.entity(t.catalog.id).coverMode ==
                  'crop',
            ),
          )
        : const AppIcon(AppIconRole.reading),
    title: Text(t.catalog.metadata.title),
    subtitle: Text(
      '${t.catalog.metadata.authors.join(', ')}${!t.catalog.sources.single.available
          ? ' · Source missing'
          : app.finished(t)
          ? ' · Completed'
          : app.started(t)
          ? ' · In progress'
          : ''}',
    ),
    onTap: () =>
        next ? previewNext(t) : run(() => openReadingTitle(context, app, t)),
    trailing: PopupMenuButton<String>(
      tooltip: 'Title actions',
      icon: const AppIcon(AppIconRole.menu),
      onSelected: (v) => run(() async {
        if (v == 'favorite') {
          await app.library.tags(
            t.catalog.id.collectionId,
            [t.catalog.id],
            ['Favorite'],
            operation: favorite(t) ? 'remove' : 'add',
          );
        }
        if (v == 'finished') {
          final before = app.finished(t);
          await app.library.finished(t.catalog.id.collectionId, [
            t.catalog.id,
          ], !before);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(before ? 'Marked unread' : 'Marked completed'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => unawaited(
                    run(
                      () => app.library.finished(t.catalog.id.collectionId, [
                        t.catalog.id,
                      ], before),
                    ),
                  ),
                ),
              ),
            );
          }
        }
      }),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: Text(favorite(t) ? 'Remove favorite' : 'Favorite'),
        ),
        PopupMenuItem(
          value: 'finished',
          child: Text(app.finished(t) ? 'Mark unread' : 'Mark completed'),
        ),
      ],
    ),
  );
  Future<void> previewNext(ReadingTitle title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Next unread'),
        content: Text(
          '${title.catalog.metadata.title}\n${readingRoleLabel(title)} · ${title.format.name.toUpperCase()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await run(() => openReadingTitle(context, app, title, immediate: true));
    }
  }

  List<ReadingTitle> filtered() {
    final b = app.bundle!;
    final lists = app.lists(widget.scope);
    final chosen = lists
        .where((r) => '${r.collectionId}:${r.id}' == list)
        .firstOrNull;
    final needle = query.text.trim().toLowerCase();
    return controller
        .browsing(
          eligible,
          hideCompleted: display.hideWatched,
          completed: app.finished,
        )
        .where((t) {
          final m = t.catalog.metadata,
              tags = b.management.entity(t.catalog.id).tags as List;
          return (needle.isEmpty ||
                  [
                    m.title,
                    ...m.authors,
                    m.description,
                    m.identifier,
                  ].join(' ').toLowerCase().contains(needle)) &&
              (tag.isEmpty || tags.contains(tag)) &&
              (author.isEmpty || m.authors.contains(author)) &&
              (language.isEmpty || m.language == language) &&
              (folder.isEmpty || t.catalog.sources.single.rootUri == folder) &&
              (status == 'all' ||
                  status == 'completed' && app.finished(t) ||
                  status == 'unread' && !app.finished(t) && !app.started(t) ||
                  status == 'progress' && !app.finished(t) && app.started(t)) &&
              (list.isEmpty ||
                  chosen != null &&
                      chosen.collectionId == t.catalog.id.collectionId &&
                      (chosen.titles as List).contains(t.catalog.id.entityId));
        })
        .toList()
      ..sort(
        (a, b) => chosen == null
            ? a.catalog.metadata.title.toLowerCase().compareTo(
                b.catalog.metadata.title.toLowerCase(),
              )
            : (chosen.titles as List)
                  .indexOf(a.catalog.id.entityId)
                  .compareTo(
                    (chosen.titles as List).indexOf(b.catalog.id.entityId),
                  ),
      );
  }

  Future<void> viewOptions() async {
    final choice = await showCollectionView(
      context,
      layout: layout,
      sort: sort,
      cardSize: cardSize,
      descending: descending,
      sorts: const {
        'title': 'Title',
        'author': 'Author',
        'source': 'Source order',
      },
    );
    if (choice != null && mounted) {
      setState(() {
        layout = choice.layout;
        sort = choice.sort;
        cardSize = choice.cardSize;
        descending = choice.descending;
      });
    }
  }

  Future<void> filterOptions() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (_, update) {
        final titles = eligible;
        Widget facet(
          String label,
          String selected,
          Iterable<String> values,
          ValueChanged<String> change, {
          String all = '',
        }) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: values.contains(selected) || selected == all
                ? selected
                : all,
            decoration: InputDecoration(labelText: label),
            items: [
              DropdownMenuItem(value: all, child: const Text('All')),
              for (final v in values.toSet().where(
                (v) => v.isNotEmpty && v != all,
              ))
                DropdownMenuItem(
                  value: v,
                  child: Text(
                    label == 'Folder'
                        ? app.bundle!.catalog.collections
                                  .expand((c) => c.roots)
                                  .where((r) => r.uri == v)
                                  .firstOrNull
                                  ?.name ??
                              'Source folder'
                        : v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => change(value));
                update(() {});
              }
            },
          ),
        );
        return FractionallySizedBox(
          heightFactor: .7,
          child: ListView(
            padding: AppSpacing.of(context).all(24),
            children: [
              Text('Filters', style: Theme.of(sheet).textTheme.titleLarge),
              facet(
                'Reading status',
                status,
                ['unread', 'progress', 'completed'],
                (v) => status = v,
                all: 'all',
              ),
              facet(
                'Tag',
                tag,
                titles.expand(
                  (t) =>
                      (app.bundle!.management.entity(t.catalog.id).tags as List)
                          .cast<String>(),
                ),
                (v) => tag = v,
              ),
              facet(
                'Author',
                author,
                titles.expand((t) => t.catalog.metadata.authors),
                (v) => author = v,
              ),
              facet(
                'Language',
                language,
                titles.map((t) => t.catalog.metadata.language),
                (v) => language = v,
              ),
              facet(
                'Folder',
                folder,
                titles.map((t) => t.catalog.sources.single.rootUri ?? ''),
                (v) => folder = v,
              ),
              FilledButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    memory.changed();
    if (app.bundle == null) {
      return Scaffold(
        appBar: AppBar(title: Text(label)),
        body: Center(
          child: TextButton(
            onPressed: app.load,
            child: Text(
              app.error == null ? 'Loading…' : 'Could not load · Retry',
            ),
          ),
        ),
      );
    }
    final titles = eligible, lists = app.lists(widget.scope);
    final continuing = titles
        .where(
          (t) =>
              app.started(t) &&
              !app.finished(t) &&
              t.catalog.sources.single.available,
        )
        .toList();
    final favorites = titles.where(favorite).toList();
    final source = display.source == 'favorites'
        ? favorites
        : display.source == 'progress'
        ? continuing
        : titles.reversed.toList();
    final showcase = controller.showcase(
      source,
      display.pins
          .map(
            (key) => titles
                .where((t) => readingKey(t.catalog.id) == key)
                .firstOrNull
                ?.catalog
                .id,
          )
          .whereType<CatalogIdentity>(),
      pinned: display.source == 'pinned',
    );
    final visibleIds = titles.map((t) => t.catalog.id).toSet();
    final visibleGroups = app.bundle!.catalog.memberships
        .where((m) => visibleIds.contains(m.child))
        .map((m) => m.parent)
        .toSet();
    final browse = filtered();
    if (sort != 'source') {
      browse.sort(
        (a, b) =>
            (sort == 'author'
                    ? a.catalog.metadata.authors.join(', ')
                    : a.catalog.metadata.title)
                .toLowerCase()
                .compareTo(
                  (sort == 'author'
                          ? b.catalog.metadata.authors.join(', ')
                          : b.catalog.metadata.title)
                      .toLowerCase(),
                ),
      );
    }
    if (descending) {
      final reversed = browse.reversed.toList();
      browse
        ..clear()
        ..addAll(reversed);
    }
    return PopScope(
      canPop: true,
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
              app.service.persistenceOwner,
              widget.scope.subtype,
            ),
            scope: widget.scope.local
                ? app.bundle!.catalog.collections
                      .firstWhere((c) => c.id == widget.scope.collectionId)
                      .name
                : 'All collections',
            overview: controller.tab == 0,
            onOverview: () => setState(() => controller.tab = 0),
            onBrowse: () {
              if (widget.scope.local && Navigator.canPop(context)) {
                Navigator.maybePop(context);
              } else {
                setState(() => controller.tab = 2);
              }
            },
          ),
          title: Text('${widget.scope.local ? 'Local ' : ''}$label'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Space actions',
              icon: const AppIcon(AppIconRole.menu),
              itemBuilder: (_) => [
                if (eligible.isNotEmpty)
                  const PopupMenuItem(
                    value: 'defaults',
                    child: Text('Application reader defaults'),
                  ),
                const PopupMenuItem(
                  value: 'cache',
                  child: Text('Reader cache'),
                ),
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Reset browsing'),
                ),
              ],
              onSelected: (value) {
                if (value == 'reset') {
                  confirmBrowseReset(context, memory);
                  return;
                }
                if (value == 'cache') {
                  cacheSettings();
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReadingAccessGuard(
                      controller: app,
                      collectionId: eligible.first.catalog.id.collectionId,
                      child: ReadingScopedSettingsPage(
                        library: app.library,
                        collectionId: eligible.first.catalog.id.collectionId,
                        subtype: widget.scope.subtype,
                        application: true,
                      ),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Space settings',
              onPressed: saving ? null : settings,
              icon: const AppIcon(AppIconRole.settings),
            ),
          ],
        ),
        body: CustomScrollView(
          key: PageStorageKey(
            'reading-space:${widget.scope.subtype.name}:${widget.scope.collectionId}',
          ),
          controller: scroll,
          slivers: [
            SliverPadding(
              padding: AppSpacing.of(context).all(20),
              sliver: SliverList.list(
                children: [
                  if (error != null) Text(error!),
                  if (display.counts)
                    Text(
                      '${titles.length} titles · ${titles.where(app.finished).length} completed',
                    ),
                  if (controller.tab == 0) ...[
                    if (display.artwork && showcase.isNotEmpty)
                      SizedBox(
                        height: 180,
                        child: Row(
                          children: [
                            for (final t in showcase)
                              Expanded(
                                child: InkWell(
                                  onTap: () => run(
                                    () => openReadingTitle(context, app, t),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: ReadingCover(
                                      library: app.library,
                                      reference: app.cover(t),
                                      crop:
                                          app.bundle!.management
                                              .entity(t.catalog.id)
                                              .coverMode ==
                                          'crop',
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    MediaRail(
                      title: 'Continue reading',
                      items: continuing
                          .take(20)
                          .map((t) => coverTile(t))
                          .toList(),
                    ),
                    MediaRail(
                      title: 'Next unread',
                      items: app
                          .nextUnread(widget.scope)
                          .take(20)
                          .map((t) => coverTile(t, next: true))
                          .toList(),
                    ),
                    if (titles.any(
                      (t) =>
                          app.bundle!.management
                              .entity(t.catalog.id)
                              .lastOpened >
                          0,
                    ))
                      MediaRail(
                        title: 'Recently opened',
                        items:
                            (titles
                                    .where(
                                      (t) =>
                                          app.bundle!.management
                                              .entity(t.catalog.id)
                                              .lastOpened >
                                          0,
                                    )
                                    .toList()
                                  ..sort(
                                    (a, b) =>
                                        (app.bundle!.management
                                                .entity(b.catalog.id)
                                                .lastOpened)
                                            .compareTo(
                                              app.bundle!.management
                                                  .entity(a.catalog.id)
                                                  .lastOpened,
                                            ),
                                  ))
                                .take(20)
                                .map((t) => coverTile(t))
                                .toList(),
                      ),
                    MediaRail(
                      title: 'Recently added',
                      items: titles.reversed
                          .take(20)
                          .map((t) => coverTile(t))
                          .toList(),
                    ),
                    MediaRail(
                      title: 'Favorites',
                      items: favorites
                          .take(20)
                          .map((t) => coverTile(t))
                          .toList(),
                    ),
                  ] else ...[
                    Visibility(
                      visible: controlsExpanded,
                      maintainState: true,
                      child: CollectionBrowseToolbar(
                        query: query,
                        onChanged: (_) => setState(() {}),
                        onFilters: filterOptions,
                        onView: viewOptions,
                        count: browse.length,
                        filters: {
                          if (status != 'all')
                            status: () => setState(() => status = 'all'),
                          if (tag.isNotEmpty)
                            '#$tag': () => setState(() => tag = ''),
                          if (author.isNotEmpty)
                            author: () => setState(() => author = ''),
                          if (language.isNotEmpty)
                            language: () => setState(() => language = ''),
                          if (folder.isNotEmpty)
                            'Source folder': () => setState(() => folder = ''),
                        },
                        onClearFilters: () => setState(() {
                          status = 'all';
                          tag = '';
                          author = '';
                          language = '';
                          folder = '';
                        }),
                      ),
                    ),
                    if (controller.tab == 2) ...[
                      const Text('Reading lists'),
                      TextButton.icon(
                        onPressed: () => editList(),
                        icon: const AppIcon(AppIconRole.add),
                        label: const Text('New reading list'),
                      ),
                      for (final r in lists)
                        ListTile(
                          title: Text(r.name),
                          subtitle: Text('${(r.titles as List).length} titles'),
                          selected: list == '${r.collectionId}:${r.id}',
                          onTap: () => setState(
                            () => list = list == '${r.collectionId}:${r.id}'
                                ? ''
                                : '${r.collectionId}:${r.id}',
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const AppIcon(AppIconRole.menu),
                            onSelected: (v) => v == 'edit'
                                ? editList(existing: r)
                                : deleteList(r),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit list'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete list'),
                              ),
                            ],
                          ),
                        ),
                      const Text('Series'),
                      for (final group in app.bundle!.catalog.groups.where(
                        (g) =>
                            visibleGroups.contains(g.id) &&
                            (query.text.trim().isEmpty ||
                                g.metadata.title.toLowerCase().contains(
                                  query.text.trim().toLowerCase(),
                                )),
                      ))
                        ListTile(
                          leading: const AppIcon(AppIconRole.reading),
                          title: Text(group.metadata.title),
                          onTap: () => run(() async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ReadingAccessGuard(
                                  controller: app,
                                  collectionId: group.id.collectionId,
                                  child: ReadingCollectionPage(
                                    library: app.library,
                                    collectionId: group.id.collectionId,
                                    groupId: group.id,
                                    openTitle: (context, title) =>
                                        openReadingTitle(
                                          context,
                                          app,
                                          title,
                                          immediate: true,
                                        ),
                                    openSpace: (context, id) =>
                                        openReadingSpace(
                                          context,
                                          app,
                                          SpaceScope(
                                            widget.scope.subtype,
                                            collectionId: id,
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      const Text('Collections'),
                      for (final c in app.bundle!.catalog.collections.where(
                        (c) => widget.scope.includes(
                          c,
                          authorized: app.canAccess(c.id),
                        ),
                      ))
                        ListTile(
                          title: Text(c.name),
                          onTap: () =>
                              openReadingCollection(context, app, c.id),
                        ),
                    ],
                    if (browse.isEmpty) const Text('No matching titles.'),
                  ],
                  if (titles.isEmpty)
                    const Text(
                      'No reading titles here. Add a folder to a collection and review its scan in Folder health.',
                    ),
                ],
              ),
            ),
            if (controller.tab != 0 && layout == 'grid')
              SliverPadding(
                padding: AppSpacing.of(context).all(20),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: cardSize,
                    mainAxisExtent: cardSize * 1.5 + 110,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: browse.length,
                  itemBuilder: (_, i) => coverTile(browse[i]),
                ),
              )
            else if (controller.tab != 0)
              SliverList.builder(
                itemCount: browse.length,
                itemBuilder: (context, index) => tile(browse[index]),
              ),
            const SliverToBoxAdapter(child: AppGap(16)),
          ],
        ),
      ),
    );
  }
}
