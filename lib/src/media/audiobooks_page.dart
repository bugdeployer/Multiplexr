import 'audio_time.dart';
import 'audiobook_editor_page.dart';
import 'audiobook_player_page.dart';
export 'audiobook_editor_page.dart';
export 'audiobook_player_page.dart';
import '../media/shared_audio_mini_player.dart';
import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';
import '../experience/navigation/browse_memory.dart';
import '../experience/collection/collection_layout.dart';
import '../features/catalog/application/collection_presenter.dart';
import '../features/catalog/application/space_queries.dart';
import 'video_projections.dart';
import '../features/metadata/application/metadata_failure_message.dart';
import '../experience/navigation/navigation_coordinator.dart';
import '../experience/navigation/navigation_origin.dart';
import 'navigation_origin_controls.dart';
import 'media_ui_patterns.dart';
import '../experience/actions/catalog_actions.dart';
import '../experience/actions/media_actions.dart';
import '../library/folder_health.dart';

import 'package:flutter/material.dart';

import '../library/library_models.dart';
import '../library/library_controller.dart';

import 'package:app_shell/app_shell.dart';

import 'audio_library.dart';
import 'audio_models.dart';
import 'audio_player.dart';
import 'contracts.dart';
import 'grouping.dart';
import 'audiobook_cover.dart';
import 'audiobook_management.dart';
import 'audiobook_metadata.dart';
import 'audiobook_details.dart';
import 'audiobook_space.dart';
import '../library/collection_form.dart';

class AudiobooksPage extends StatefulWidget {
  const AudiobooksPage({
    super.key,
    required this.catalog,
    this.libraryController,
    this.collectionId,
    this.scan = false,
    this.showJobsOnOpen = false,
  });
  final AudioLibrary catalog;
  final LibraryController? libraryController;
  final String? collectionId;
  final bool scan, showJobsOnOpen;
  @override
  State<AudiobooksPage> createState() => _AudiobooksPageState();
}

class _AudiobooksPageState extends State<AudiobooksPage> {
  bool controlsExpanded = false;
  late final memory = BrowseMemory(
    preferences: widget.catalog.userPreferences,
    query: search,
    scroll: scroll,
    alive: () => mounted,
    contentReady: () => !busy,
    capture: () => NavigationOrigin(
      routeId: 'audiobook-collection',
      collectionId: widget.collectionId,
      query: search.text,
      folder: folder,
      tag: tag ?? '',
      sort: browsing.sort,
      layout: browsing.descending ? 'reverse' : 'forward',
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
    ),
    defaults: () => NavigationOrigin(
      routeId: 'audiobook-collection',
      collectionId: widget.collectionId,
    ),
    apply: (origin) {
      if (mounted) {
        setState(() {
          folder = origin.folder;
          browsing.sort = origin.sort == 'author' ? 'author' : 'title';
          browsing.descending = origin.layout == 'reverse';
          tag = origin.tag.isEmpty ? null : origin.tag;
        });
      }
    },
  );

  late final library = widget.catalog;
  late final importer = library.audio;
  final browsing = CollectionController<Audiobook, MediaId>(
    identity: (b) => b.id,
  )..loading = true;
  List<Audiobook> get books => browsing.items;
  set books(List<Audiobook> value) => browsing.replace(value);
  Map<String, AudiobookSeriesMetadata> seriesDetails = {};
  bool get busy => browsing.loading;
  set busy(bool value) => browsing.loading = value;
  String? get error => browsing.error;
  set error(String? value) => browsing.error = value;
  String get folder => browsing.folder;
  set folder(String value) => browsing.folder = value;
  final search = TextEditingController();
  final scroll = ScrollController();
  String? get tag => browsing.tag.isEmpty ? null : browsing.tag;
  set tag(String? value) => browsing.tag = value ?? '';
  VideoCollection? get currentCollection => widget
      .libraryController
      ?.collections
      .where((c) => c.id == widget.collectionId)
      .firstOrNull;
  CatalogLayout get collectionLayout => switch (currentCollection?.view) {
    CatalogView.compact => CatalogLayout.compact,
    CatalogView.list || null => CatalogLayout.list,
    _ => CatalogLayout.grid,
  };
  bool eligible(Audiobook book) {
    final controller = widget.libraryController;
    if (controller == null) return library.canAccess(book.id.collectionId);
    final scope = SpaceScope(
      MediaSubtype.audiobooks,
      collectionId: widget.collectionId,
    );
    return controller.collections.any(
      (c) =>
          c.id == book.id.collectionId &&
          scope.includes(
            c.catalogCollection,
            authorized: controller.canAccessCollection(c.id),
          ),
    );
  }

  List<Audiobook> get visibleBooks {
    final allowFolders =
        widget.libraryController?.collections
            .where((c) => c.id == widget.collectionId)
            .firstOrNull
            ?.allowFolders ==
        true;
    final activeTag = books.any((b) => b.metadata.tags.contains(tag))
        ? tag
        : null;
    final query = search.text.trim().toLowerCase();
    browsing.query = search.text;
    browsing.layout = collectionLayout;
    return browsing.browse(
      compare: (a, b) =>
          (browsing.sort == 'author' ? a.metadata.author : a.metadata.title)
              .toLowerCase()
              .compareTo(
                (browsing.sort == 'author'
                        ? b.metadata.author
                        : b.metadata.title)
                    .toLowerCase(),
              ),
      matches: (b) =>
          eligible(b) &&
          (!allowFolders || folder.isEmpty || sourceFolder(b) == folder) &&
          (activeTag == null || b.metadata.tags.contains(activeTag)) &&
          audiobookSearchText(
            b,
            series: seriesDetails[audiobookSeriesIdentity(b)],
          ).contains(query),
    );
  }

  Future<void> matchAudiobook(Audiobook book) async {
    await findAudiobookMetadata(context, library, book);
    await load();
  }

  late final lookupJob =
      widget.libraryController?.metadataJobs.audiobook(widget.collectionId) ??
      browsing.ownJob(library.metadataJobFactory(widget.collectionId));
  bool get metadataRunning => lookupJob.running;
  bool get metadataCancelled => lookupJob.cancelled;
  int get metadataDone => lookupJob.done;
  int get metadataTotal => lookupJob.total;
  String get metadataJobKey => lookupJob.key;
  Future<void> fetchMetadata({bool retry = false, bool resume = false}) async {
    if (metadataRunning) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await lookupJob.run(retry: retry, resume: resume);
    } catch (e) {
      if (mounted) setState(() => error = metadataFailureMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> metadataJob({bool review = false}) async {
    await lookupJob.recover();
    final value = lookupJob.snapshot;
    final entries = Map<String, dynamic>.from(value['entries'] ?? {});
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (page) => Scaffold(
          appBar: AppBar(
            title: Text(
              review ? 'Review metadata matches' : 'Metadata job details',
            ),
          ),
          body: ListView(
            children: [
              if ((value['remaining'] as List? ?? []).isNotEmpty &&
                  !metadataRunning)
                ListTile(
                  title: const Text('Resume metadata lookup'),
                  onTap: () async {
                    Navigator.pop(page);
                    await fetchMetadata(resume: true);
                  },
                ),
              if (entries.isEmpty ||
                  (review &&
                      !entries.values.any(
                        (v) => (v as Map)['status'] == 'review',
                      )))
                ListTile(
                  title: Text(
                    review
                        ? 'No metadata matches awaiting review.'
                        : 'No metadata lookups yet.',
                  ),
                ),
              for (final entry in entries.entries)
                if (!review || (entry.value as Map)['status'] == 'review')
                  ListTile(
                    title: Text((entry.value as Map)['title'] ?? ''),
                    subtitle: Text(
                      (entry.value as Map)['error'] ??
                          (entry.value as Map)['status'],
                    ),
                    onTap: (entry.value as Map)['status'] != 'review'
                        ? null
                        : () async {
                            final book = (await library.query())
                                .where((b) => b.id.key == entry.key)
                                .firstOrNull;
                            if (book == null || !page.mounted) return;
                            final applied = await findAudiobookMetadata(
                              page,
                              library,
                              book,
                              candidates: [
                                for (final item
                                    in (entry.value as Map)['candidates'])
                                  Map<String, dynamic>.from(item),
                              ],
                            );
                            if (applied) {
                              await lookupJob.markApplied(entry.key);
                              if (page.mounted) Navigator.pop(page);
                            }
                          },
                  ),
            ],
          ),
        ),
      ),
    );
    await load();
  }

  bool get selecting => browsing.selecting;
  set selecting(bool value) => browsing.selecting = value;
  Set<MediaId> get selected => browsing.selected;
  String sourceFolder(Audiobook book) => book.id.itemId.startsWith('folder:')
      ? Uri.decodeComponent(
          book.id.itemId.substring(7).split(':').skip(1).join(':'),
        )
      : 'Imported files';
  @override
  void initState() {
    super.initState();
    memory.restore();
    lookupJob.addListener(lookupChanged);

    widget.libraryController?.addListener(collectionsChanged);
    if (widget.scan) {
      scan();
    } else {
      load().then((_) {
        if (mounted && widget.showJobsOnOpen) metadataJob();
      });
    }
  }

  void lookupChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    memory.dispose();
    widget.libraryController?.removeListener(collectionsChanged);
    lookupJob.removeListener(lookupChanged);
    browsing.dispose();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void collectionsChanged() {
    if (mounted && !busy) load();
  }

  Future<void> openBook(Audiobook book, {bool forcePlay = false}) async {
    if (!eligible(book)) {
      await load();
      return;
    }
    final controller = widget.libraryController;
    final global = widget.collectionId == null;
    if (global && controller != null) {
      final owner = controller.collections
          .where(
            (c) =>
                c.id == book.id.collectionId &&
                c.isAudio &&
                !c.locked &&
                c.includeInGlobalAudio,
          )
          .firstOrNull;
      if (owner == null) {
        await load();
        return;
      }
      controller.beginCollectionSession(owner.id);
    }
    try {
      final owner = controller?.collections
          .where((c) => c.id == book.id.collectionId)
          .firstOrNull;
      if (!mounted) return;
      await openAudiobookTitle(
        context,
        library,
        owner,
        book,
        (rate) async {
          final latest = (await library.query())
              .where((b) => b.id == book.id)
              .firstOrNull;
          if (!mounted || latest == null) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => AudiobookPlayerPage(
                book: latest,
                catalog: library,
                initialRate: rate,
              ),
            ),
          );
        },
        () => editBook(book),
        forcePlay: forcePlay,
        origin: NavigationOrigin(
          routeId: 'audiobooks',
          collectionId: widget.collectionId,
          query: search.text,
          folder: folder,
          tag: tag ?? '',
          scrollOffset: scroll.hasClients
              ? scroll.offset.clamp(0, double.infinity)
              : 0,
        ),
        restore: (origin) => restoreOrigin(
          context,
          origin,
          query: search,
          scroll: scroll,
          controls: () {
            if (mounted) {
              setState(() {
                folder = origin.folder;
                tag = origin.tag.isEmpty ? null : origin.tag;
              });
            }
          },
        ),
      );
    } finally {
      if (global) controller?.endCollectionSession();
    }
  }

  Future<void> load() async {
    final details = <String, AudiobookSeriesMetadata>{};
    final applied = await browsing.load(() async {
      final values = await library.query();
      for (final group in audiobookSeries(values)) {
        final saved = await library.seriesMetadata(group.id);
        if (saved != null) details[group.id] = saved;
      }
      final scope = SpaceScope(
        MediaSubtype.audiobooks,
        collectionId: widget.collectionId,
      );
      final controller = widget.libraryController;
      final allowed = controller?.collections
          .where(
            (c) => scope.includes(
              c.catalogCollection,
              authorized: controller.canAccessCollection(c.id),
            ),
          )
          .map((c) => c.id)
          .toSet();
      return values
          .where((b) => allowed == null || allowed.contains(b.id.collectionId))
          .toList()
        ..sort((a, b) => naturalAudioOrder(a.metadata.title, b.metadata.title));
    }, failure: 'Could not load the audiobook library.');
    if (mounted) {
      setState(() {
        if (applied) seriesDetails = details;
      });
    }
  }

  Future<void> scan() async {
    if (widget.collectionId == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final controller = widget.libraryController;
      final List<String> warnings;
      if (controller != null) {
        await controller.scan(widget.collectionId!);
        warnings = controller.warnings[widget.collectionId!] ?? [];
      } else {
        warnings = await library.scanSources(
          widget.collectionId!,
          requestId: 'audio-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      await load();
      if (mounted && warnings.isNotEmpty) {
        setState(() => error = warnings.join('\n'));
      }
    } catch (_) {
      await widget.libraryController?.load();
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not scan audiobook sources. Existing audiobooks were kept.';
        });
      }
    }
  }

  Future<void> editBook(Audiobook book, {bool reconnect = false}) async {
    List<AudioFile> selected = [];
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var files = book.files;
      if (reconnect) {
        final result = await importer.pickFiles();
        if (result == null || !mounted) return;
        if (result.errors.isNotEmpty ||
            result.files.length != book.files.length) {
          throw StateError(
            'Select all ${book.files.length} chapter files. Every selected file must be readable.',
          );
        }
        files = result.files;
        selected = result.files;
      }
      await importer.refresh();
      if (importer.state.id == book.id) {
        await importer.execute(const AudioCommand.action(AudioAction.stop));
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AudiobookEditorPage(
            library: library,
            files: files,
            existing: book,
            reconnect: reconnect,
          ),
        ),
      );
      await load();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'Could not open book settings.',
        );
      }
    } finally {
      if (selected.isNotEmpty) {
        await importer.releaseUnusedFiles(selected).catchError((Object _) {});
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Audiobook book) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove book?'),
        content: Text(
          'Remove “${book.metadata.title}” from this library? Source files are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await importer.refresh();
      if (importer.state.id == book.id) {
        await importer.execute(const AudioCommand.action(AudioAction.stop));
      }
      await library.remove(book);
      await importer.releaseUnusedFiles(book.files).catchError((Object _) {});
      await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not remove the book.';
          busy = false;
        });
      }
    }
  }

  MediaActionContext get actionContext => MediaActionContext(
    authorized:
        widget.collectionId == null || library.canAccess(widget.collectionId!),
    capabilities: appSubtypes.definition(MediaSubtype.audiobooks).capabilities,
  );
  Future<void> collectionAction(String action) async {
    if (action == 'reset') {
      await confirmBrowseReset(context, memory);
      return;
    }
    if (!CatalogActionRegistry.permitted(
      selecting ? CatalogActionScope.selection : CatalogActionScope.collection,
      action,
      actionContext,
    )) {
      return;
    }
    try {
      switch (action) {
        case 'settings':
          await collectionSettings();
        case 'playerSettings':
          await collectionSettings(initialSection: 'Playback');
        case 'audioSpace':
          final owner = widget.collectionId;
          final controller = widget.libraryController;
          if (owner != null && controller != null) {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AudiobookSpace(library: controller, collectionId: owner),
              ),
            );
          }
          await load();
        case 'scan':
          await scan();
        case 'selectAll':
          setState(() {
            selected.addAll(visibleBooks.map((b) => b.id));
          });
        case 'clearSelection':
          setState(selected.clear);
        case 'select':
          setState(() {
            selecting = true;
            selected.clear();
          });
        case 'tags':
          await manageAudiobookTags(context, library);
          await load();
        case 'tagSelected':
          await tagSelectedAudiobooks(
            context,
            library,
            books.where((b) => selected.contains(b.id)).toList(),
          );
          await load();
        case 'fetchMetadata':
          await fetchMetadata();
        case 'retryMetadata':
          await fetchMetadata(retry: true);
        case 'reviewMetadata':
          await metadataJob(review: true);
        case 'metadataJob':
          await metadataJob();
        case 'health':
          await folderHealth();
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save this change. Please try again.');
      }
    }
  }

  void toggleBook(Audiobook book) => setState(() {
    if (!selected.add(book.id)) selected.remove(book.id);
  });

  Future<void> collectionSettings({String? initialSection}) async {
    final controller = widget.libraryController;
    final existing = controller?.collections
        .where((c) => c.id == widget.collectionId)
        .firstOrNull;
    if (controller == null || existing == null) return;
    await collectionDialog(
      context,
      controller,
      existing: existing,
      initialSection: initialSection,
    );
    if (!mounted) return;
    if (!controller.collections.any((c) => c.id == widget.collectionId)) {
      Navigator.pop(context);
      return;
    }
    await load();
  }

  Future<void> folderHealth() async {
    final collection = widget.libraryController?.collections
        .where((c) => c.id == widget.collectionId)
        .firstOrNull;
    if (collection == null) return;
    await showFolderHealth(context, collection, collectionSettings);
  }

  Widget audiobookActions(Audiobook book) => AudiobookActionMenu(
    book: book,
    library: library,
    edit: () => editBook(book),
    refresh: load,
    addTags: () => editAudiobookTags(context, library, book),
    remove: () => remove(book),
  );

  Widget audiobookCard(
    Audiobook book, {
    required bool grid,
    required bool compact,
  }) {
    final summary = [
      if (book.metadata.author.isNotEmpty) book.metadata.author,
      '${book.chapterMarkers.length} ${book.chapterMarkers.length == 1 ? 'chapter' : 'chapters'}',
      audioTime(book.durationMs),
    ].join(' · ');
    void tap() {
      if (selecting) {
        toggleBook(book);
      } else {
        openBook(book);
      }
    }

    if (!grid) {
      return MediaItemSelection(
        selected: selecting ? selected.contains(book.id) : null,
        onToggle: () => toggleBook(book),
        reserveLeading: true,
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            dense: compact,
            leading: selecting
                ? null
                : SizedBox(
                    width: 48,
                    height: 48,
                    child: AudiobookCover(cover: book.metadata.cover),
                  ),
            title: Text(book.metadata.title),
            subtitle: Text(summary),
            trailing: audiobookActions(book),
            onTap: tap,
          ),
        ),
      );
    }
    return AudiobookArtworkTile(
      title: book.metadata.title,
      menu: selecting ? null : audiobookActions(book),
      cover: book.metadata.cover,
      onTap: tap,
      selected: selecting ? selected.contains(book.id) : null,
    );
  }

  Future<void> openSeries(MediaGroup<Audiobook> group) =>
      NavigationCoordinator.forOwner(library.owner).run(
        'series:${group.id}',
        () => _openSeries(group),
        origin: NavigationOrigin(
          routeId: 'audiobooks',
          collectionId: widget.collectionId,
          query: search.text,
          folder: folder,
          tag: tag ?? '',
          layout: collectionLayout.name,
          scrollOffset: scroll.hasClients
              ? scroll.offset.clamp(0, double.infinity)
              : 0,
        ),
        restore: (origin) => restoreOrigin(
          context,
          origin,
          query: search,
          scroll: scroll,
          controls: () {
            folder = origin.folder;
            tag = origin.tag.isEmpty ? null : origin.tag;
          },
        ),
      );
  Future<void> _openSeries(MediaGroup<Audiobook> group) async {
    if (!group.children.every(eligible)) {
      await load();
      return;
    }
    final controller = widget.libraryController;
    final global = widget.collectionId == null;
    if (global) {
      controller?.beginCollectionSession(group.children.first.id.collectionId);
    }
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => AudiobookSeriesPage(
            group: group,
            library: library,
            openBook: openBook,
            playBook: (b) => openBook(b, forcePlay: true),
            editBook: (b) => editBook(b),
          ),
        ),
      );
    } finally {
      if (global) controller?.endCollectionSession();
    }
    await load();
  }

  Future<void> showView() async {
    final choice = await showCollectionView(
      context,
      layout: collectionLayout.name,
      sort: browsing.sort,
      sorts: const {'title': 'Title', 'author': 'Author'},
      cardSize: currentCollection?.cardSize ?? 180,
      descending: browsing.descending,
    );
    if (choice == null || widget.collectionId == null) return;
    browsing.sort = choice.sort;
    browsing.descending = choice.descending;
    await widget.libraryController!.saveBrowsing(widget.collectionId!, {
      'view': choice.layout,
      'cardSize': choice.cardSize,
    });
    await widget.libraryController?.load();
    if (mounted) setState(() {});
  }

  Future<void> showFilters() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (_, update) => SingleChildScrollView(
        padding: AppSpacing.of(context).all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filters', style: Theme.of(sheet).textTheme.titleLarge),
            const AppGap(20),
            if (books.any((b) => b.metadata.tags.isNotEmpty)) ...[
              DropdownButtonFormField<String>(
                icon: const AppIcon(AppIconRole.expand),
                isExpanded: true,
                key: ValueKey(
                  books.expand((b) => b.metadata.tags).toSet().join('|'),
                ),
                initialValue: books.any((b) => b.metadata.tags.contains(tag))
                    ? tag
                    : '',
                decoration: const InputDecoration(labelText: 'Tag'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All tags')),
                  for (final value
                      in (books.expand((b) => b.metadata.tags).toSet().toList()
                        ..sort()))
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) =>
                    setState(() => tag = value == '' ? null : value),
              ),
              const AppGap(16),
            ],
            if (widget.libraryController?.collections
                    .where((c) => c.id == widget.collectionId)
                    .firstOrNull
                    ?.allowFolders ==
                true)
              DropdownButtonFormField<String>(
                icon: const AppIcon(AppIconRole.expand),
                isExpanded: true,
                key: ValueKey(books.map(sourceFolder).toSet().join('|')),
                initialValue: books.any((b) => sourceFolder(b) == folder)
                    ? folder
                    : '',
                decoration: const InputDecoration(labelText: 'Source folder'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All folders')),
                  for (final source in books.map(sourceFolder).toSet())
                    DropdownMenuItem(value: source, child: Text(source)),
                ],
                onChanged: (value) => setState(() => folder = value ?? ''),
              ),

            const AppGap(20),
            FilledButton(
              onPressed: () => Navigator.pop(sheet),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    memory.changed();
    return Scaffold(
      bottomNavigationBar: SharedAudioMiniPlayer(owner: library.owner),
      appBar: AppBar(
        bottom: selecting
            ? null
            : CollectionExperienceHeader(
                expanded: controlsExpanded,
                onExpanded: () {
                  if (controlsExpanded) FocusScope.of(context).unfocus();
                  setState(() => controlsExpanded = !controlsExpanded);
                },
                onScope: () => CollectionScopeRouter.choose(
                  context,
                  library.owner,
                  MediaSubtype.audiobooks,
                ),
                scope: currentCollection?.name ?? 'All collections',
                overview: false,
                onOverview: () => collectionAction('audioSpace'),
                onBrowse: () {},
              ),
        title: Text(
          selecting
              ? '${selected.length} selected'
              : widget.libraryController?.collections
                        .where((c) => c.id == widget.collectionId)
                        .firstOrNull
                        ?.name ??
                    'Audiobooks',
        ),
        actions: [
          if (metadataRunning)
            IconButton(
              tooltip: 'Cancel metadata lookup',
              icon: const AppIcon(AppIconRole.stop),
              onPressed: lookupJob.cancel,
            ),
          if (selecting)
            IconButton(
              tooltip: 'Cancel selection',
              onPressed: () => setState(() {
                selecting = false;
                selected.clear();
              }),
              icon: const AppIcon(AppIconRole.close),
            ),
          if (!selecting &&
              widget.collectionId != null &&
              widget.libraryController != null)
            IconButton(
              tooltip: 'Collection settings',
              onPressed: busy ? null : collectionSettings,
              icon: const AppIcon(AppIconRole.settings),
            ),
          CollectionActionsMenu(
            icon: const AppIcon(AppIconRole.menu),
            tooltip: 'Collection actions',
            enabled: !busy,
            onSelected: collectionAction,
            itemBuilder: (_) => catalogActionMenu(
              selecting
                  ? [
                      PopupMenuItem(
                        value: 'tagSelected',
                        enabled: selected.isNotEmpty,
                        child: const Text('Add tags'),
                      ),
                      const PopupMenuItem(
                        value: 'selectAll',
                        child: Text('Select all'),
                      ),
                      const PopupMenuItem(
                        value: 'clearSelection',
                        child: Text('Clear selection'),
                      ),
                    ]
                  : [
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('Reset browsing'),
                      ),
                      if (widget.collectionId != null)
                        const PopupMenuItem(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                      if (widget.collectionId != null)
                        const PopupMenuItem(
                          value: 'tags',
                          child: Text('Manage tags'),
                        ),
                      if (widget.collectionId != null)
                        const PopupMenuItem(
                          value: 'playerSettings',
                          child: Text('Player settings'),
                        ),
                      if (widget.collectionId != null)
                        const PopupMenuItem(
                          value: 'audioSpace',
                          child: Text('Enter Audiobooks space'),
                        ),
                      const PopupMenuItem(
                        value: 'select',
                        child: Text('Select books'),
                      ),
                      if (selecting)
                        PopupMenuItem(
                          value: 'tagSelected',
                          enabled: selected.isNotEmpty,
                          child: const Text('Tag selected books'),
                        ),
                      if (widget.collectionId != null) ...[
                        const PopupMenuItem(
                          value: 'scan',
                          child: Text('Scan folders'),
                        ),
                        const PopupMenuItem(
                          value: 'fetchMetadata',
                          child: Text('Fetch missing metadata'),
                        ),
                        const PopupMenuItem(
                          value: 'retryMetadata',
                          child: Text('Retry failed metadata'),
                        ),
                        const PopupMenuItem(
                          value: 'reviewMetadata',
                          child: Text('Review metadata matches'),
                        ),
                        const PopupMenuItem(
                          value: 'metadataJob',
                          child: Text('Metadata job details'),
                        ),
                      ],
                      if (widget.collectionId != null)
                        const PopupMenuItem(
                          value: 'health',
                          child: Text('Folder health'),
                        ),
                    ],
              scope: selecting
                  ? CatalogActionScope.selection
                  : CatalogActionScope.collection,
              context: actionContext,
            ),
          ),
        ],
      ),
      body: busy && books.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (metadataRunning) ...[
                    const AppGap(20),
                    Text(
                      metadataCancelled
                          ? 'Stopping after this request…'
                          : 'Looking up metadata · $metadataDone of $metadataTotal',
                    ),
                    TextButton(
                      onPressed: metadataCancelled ? null : lookupJob.cancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                controller: scroll,
                padding: AppSpacing.of(context).all(20),
                children: [
                  if (busy) const LinearProgressIndicator(),
                  Visibility(
                    visible: controlsExpanded,
                    maintainState: true,
                    child: CollectionBrowseToolbar(
                      query: search,
                      onChanged: (_) => setState(() {}),
                      onFilters: showFilters,
                      onView: showView,
                      count: visibleBooks.length,
                      filters: {
                        ?tag: () => setState(() => tag = null),
                        if (folder.isNotEmpty)
                          'Folder': () => setState(() => folder = ''),
                      },
                      onClearFilters: () => setState(() {
                        tag = null;
                        folder = '';
                      }),
                    ),
                  ),
                  if (error != null) ...[
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('Retry')),
                  ],
                  if (books.isEmpty && error == null) ...[
                    const Text('No audiobooks'),
                    const AppGap(12),
                    const Text(
                      'Add root folders in collection settings, then scan for books.',
                    ),
                    const AppGap(20),
                    FilledButton.icon(
                      onPressed: widget.collectionId == null
                          ? null
                          : collectionSettings,
                      icon: const AppIcon(AppIconRole.add),
                      label: const Text('Collection settings'),
                    ),
                  ],
                  if (books.isNotEmpty && visibleBooks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No audiobooks in this view'),
                    ),
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('${selected.length} selected'),
                    ),
                  CollectionLayout(
                    layout: collectionLayout,
                    cardSize: currentCollection?.cardSize ?? 180,
                    builder: (context, width, grid, compact) {
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          if (!selecting)
                            for (final group in audiobookSeries(visibleBooks))
                              SizedBox(
                                width: width,
                                child: grid
                                    ? AudiobookArtworkTile(
                                        title:
                                            seriesDetails[group.id]?.title ??
                                            group.title,
                                        cover:
                                            seriesDetails[group.id]
                                                    ?.cover
                                                    .isNotEmpty ==
                                                true
                                            ? seriesDetails[group.id]!.cover
                                            : group
                                                  .children
                                                  .first
                                                  .metadata
                                                  .cover,
                                        onTap: () => openSeries(group),
                                      )
                                    : Card(
                                        child: ListTile(
                                          dense: compact,
                                          leading: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: AudiobookCover(
                                              cover:
                                                  seriesDetails[group.id]
                                                          ?.cover
                                                          .isNotEmpty ==
                                                      true
                                                  ? seriesDetails[group.id]!
                                                        .cover
                                                  : group
                                                        .children
                                                        .first
                                                        .metadata
                                                        .cover,
                                            ),
                                          ),
                                          title: Text(
                                            seriesDetails[group.id]?.title ??
                                                group.title,
                                          ),
                                          subtitle: Text(
                                            '${group.children.length} ${group.children.length == 1 ? 'audiobook' : 'audiobooks'}',
                                          ),
                                          trailing: const AppIcon(
                                            AppIconRole.disclosure,
                                          ),
                                          onTap: () => openSeries(group),
                                        ),
                                      ),
                              ),
                          for (final book in visibleBooks.where(
                            (b) => selecting,
                          ))
                            SizedBox(
                              width: width,
                              child: audiobookCard(
                                book,
                                grid: grid,
                                compact: compact,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
