import '../experience/plugins/plugin_artwork_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../media/shared_audio_mini_player.dart';
import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';
import '../experience/navigation/browse_memory.dart';
import '../features/catalog/application/collection_presenter.dart';
import '../features/metadata/application/artwork_service.dart';
import '../features/metadata/application/metadata_contracts.dart';
import 'metadata_search_page.dart';
import '../experience/navigation/navigation_coordinator.dart';
import '../experience/navigation/navigation_origin.dart';
import '../media/navigation_origin_controls.dart';
import '../experience/actions/catalog_actions.dart';
import '../experience/actions/media_actions.dart';
import '../catalog/domain/classification.dart';
import '../media/video_navigation.dart';
import '../media/navigation_settings.dart';
import '../media/video_projections.dart';
import '../media/media_ui_patterns.dart';
import 'folder_health.dart';
import '../space_preferences.dart';
import 'video_scope.dart';
import 'series_management.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'package:flutter/services.dart';

import 'collection_form.dart';
import '../features/metadata/application/video_metadata_policy.dart';
import 'metadata_job.dart';
import 'tags.dart';
import 'video_art.dart';
import '../features/catalog/application/video_queries.dart';
import 'library_models.dart';
import 'library_controller.dart';
import 'series.dart';
import 'series_view.dart';
import 'player.dart';
import 'cinema_view.dart';
import 'video_space.dart';

class CollectionCatalog extends StatefulWidget {
  const CollectionCatalog({
    super.key,
    required this.library,
    required this.collectionId,
    required this.notifications,
    this.scanOnOpen = false,
    this.showJobsOnOpen = false,
    this.spacePreferences,
  });
  final LibraryController library;
  final String collectionId;
  final ShellPlatform notifications;
  final bool scanOnOpen, showJobsOnOpen;
  final SpacePreferences? spacePreferences;
  @override
  State<CollectionCatalog> createState() => _CollectionCatalogState();
}

class _CollectionCatalogState extends State<CollectionCatalog> {
  bool controlsExpanded = false;
  late final memory = BrowseMemory(
    preferences: widget.library.service.userPreferences,
    query: search,
    scroll: scroll,
    alive: () => mounted,
    capture: () => NavigationOrigin(
      routeId: 'collection',
      collectionId: widget.collectionId,
      query: search.text,
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
      folder: folder,
      sort: browsing.descending ? 'reverse' : 'forward',
    ),
    defaults: () => NavigationOrigin(
      routeId: 'collection',
      collectionId: widget.collectionId,
      folder: '',
      scrollOffset: 0,
    ),
    onReset: () => saveBrowsing({
      'folder': '',
      'filter': 'all',
      'sort': 'title',
      'scrollOffset': 0.0,
    }),
    apply: (origin) {
      if (mounted) {
        setState(() {
          folder = origin.folder;
          browsing.descending = origin.sort == 'reverse';
        });
      }
    },
  );

  late final VideoCollection initialCollection;
  VideoCollection get collection => widget.library.collections.firstWhere(
    (c) => c.id == widget.collectionId,
    orElse: () => initialCollection,
  );
  late CatalogView view = collection.view == CatalogView.netflix
      ? CatalogView.grid
      : collection.view;
  final search = TextEditingController();
  late final MetadataJob job;
  bool get matching => job.running;
  final scroll = ScrollController();
  final browsing = CollectionController<VideoAsset, String>(
    identity: (a) => a.id,
  );
  String get folder => browsing.folder;
  set folder(String value) => browsing.folder = value;
  bool get selecting => browsing.selecting;
  set selecting(bool value) => browsing.selecting = value;
  Set<String> get selected => browsing.selected;

  late final spacePreferences = widget.spacePreferences ?? SpacePreferences();
  Future<void> editSpace(bool videos) => showSpaceSettings(
    context,
    spacePreferences,
    widget.library.service,
    videos,
    eligible: videos
        ? videoSpaceItems(widget.library)
        : groupedTitles(cinemaItems(widget.library)),
  );
  Future<void> enterVideoSpace() => enterSpace(true);
  Future<void> enterCinema() => enterSpace(false);
  Future<void> enterSpace(bool videos) async {
    await spacePreferences.load(widget.library.service.userPreferences);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SpaceExitGuard(
          preferences: spacePreferences,
          videos: videos,
          child: videos
              ? MultiplexrVideoSpace(
                  library: widget.library,
                  collectionId: collection.id,
                  collectionName: collection.name,
                  display: spacePreferences.videos,
                  spaceSettings: () => editSpace(true),
                )
              : MultiplexrCinema(
                  library: widget.library,
                  collectionId: collection.id,
                  collectionName: collection.name,
                  display: spacePreferences.cinema,
                  spaceSettings: () => editSpace(false),
                  editEpisode: editMetadata,
                  matchEpisode: review,
                  play: (asset, external) => play(asset, external: external),
                ),
        ),
      ),
    );
  }

  VideoSubtype metadataSubtype(VideoAsset asset) => asset.mediaSubtype;

  VideoAsset lookupAsset(VideoAsset asset) =>
      collection.subtype == VideoSubtype.videos &&
          asset.metadataSource == 'filename'
      ? VideoAsset.fromJson({
          ...asset.toJson(),
          'metadata': inferMetadata(asset.filename, VideoSubtype.movies),
        }, VideoSubtype.movies)
      : asset;
  int get matchDone => job.done;
  int get matchTotal => job.total;
  String? matchSummary;
  String? get error => browsing.error;
  set error(String? value) => browsing.error = value;
  @override
  void initState() {
    super.initState();
    initialCollection = widget.library.collections.firstWhere(
      (c) => c.id == widget.collectionId,
    );
    job = widget.library.metadataJobs.video(collection)..addListener(changed);
    job
        .recover()
        .then((_) {
          if (mounted && widget.showJobsOnOpen) metadataStatus();
        })
        .catchError((Object _) {
          if (mounted) {
            setState(() => error = 'Could not load metadata recovery state.');
          }
        });
    folder = collection.folder;
    memory.restore();
    widget.library.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(
          collection.scrollOffset.clamp(0, scroll.position.maxScrollExtent),
        );
      }
    });
    if (widget.scanOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => scan());
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    memory.dispose();
    job.removeListener(changed);
    final offset = scroll.hasClients ? scroll.offset : 0.0;
    if (widget.library.collections.any((c) => c.id == widget.collectionId)) {
      widget.library
          .saveBrowsing(collection.id, {
            'scrollOffset': offset,
            'folder': folder,
          })
          .catchError((Object _) {});
    }
    scroll.dispose();
    widget.library.removeListener(changed);
    browsing.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    if (widget.library.scanning.contains(collection.id)) return;
    setState(() => error = null);
    try {
      await widget.library.scan(collection.id);
      final warnings = widget.library.warnings[collection.id] ?? [];
      try {
        await widget.notifications.postNotification(
          warnings.isEmpty ? 'completed' : 'errors',
          collection.locked ? 'Collection scan' : collection.name,
          collection.locked
              ? 'Scan finished. Open the collection for details.'
              : warnings.isEmpty
              ? '${widget.library.items(collection.id).length} videos indexed.'
              : warnings.join('\n'),
        );
      } catch (_) {
        /* Notification preferences must not fail a scan. */
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not scan this collection. Check folder access and try again.',
        );
      }
    }
  }

  Future<void> metadataStatus() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: ListView(
          padding: AppSpacing.of(context).all(24),
          children: [
            Text('Metadata job', style: Theme.of(context).textTheme.titleLarge),
            const AppGap(12),
            Text(job.summary),
            if (job.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(job.lastError!),
              ),
            if (job.resumable)
              const Text(
                'Unfinished work is saved on this device. Resume from the collection menu when you are ready.',
              ),
            for (final failure in job.failures.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.library
                          .items(collection.id)
                          .where((a) => a.id == failure.key)
                          .firstOrNull
                          ?.title ??
                      'Unavailable item',
                ),
                subtitle: Text(failure.value),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> matchAll({
    bool resume = false,
    bool failedOnly = false,
    Set<String>? assetIds,
  }) async {
    if (matching) return;
    setState(() {
      error = null;
      matchSummary = null;
    });
    try {
      await job.run(failedOnly: failedOnly, assetIds: assetIds, resume: resume);
      if (mounted) setState(() => matchSummary = job.summary);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError ? e.message.toString() : 'Metadata job could not finish. Saved matches are preserved. Retry remaining items.',
        );
      }
    }
  }

  Future<void> play(VideoAsset asset, {bool? external}) async {
    if (!asset.available) {
      setState(
        () => error = 'This file is unavailable. Reconnect its folder in collection settings and scan again.',
      );
      return;
    }
    if (asset.watched) {
      await widget.library.watch(asset, 'restart');
      asset = widget.library
          .items(collection.id)
          .firstWhere((a) => a.id == asset.id);
    }
    if (!mounted) return;
    try {
      if (external ?? collection.player == PlaybackTarget.external) {
        await widget.library.service.external(asset);
      } else {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplexrPlayer(
              asset: asset,
              host: widget.library.videoPlayback,
              landscapeOnly: collection.subtype != VideoSubtype.videos,
              library: widget.library,
            ),
          ),
        );
        await widget.library.load();
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> editMetadata(VideoAsset asset) async {
    final fields =
        metadataFields[collection.subtype == VideoSubtype.videos
            ? VideoSubtype.videos
            : metadataSubtype(asset)]!;
    final controls = {
      for (final key in fields.keys)
        key: TextEditingController(text: asset.metadata[key]),
    };
    final form = GlobalKey<FormState>();
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.viewInsetsOf(context).bottom +
                  (View.of(context).viewPadding.bottom /
                      View.of(context).devicePixelRatio) +
                  24,
            ),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Edit ${metadataSubtype(asset) == VideoSubtype.tv ? 'episode' : 'video'} metadata',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final entry in fields.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextFormField(
                        controller: controls[entry.key],
                        decoration: InputDecoration(
                          labelText: entry.value,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: entry.key == 'description' ? 3 : 1,
                        validator: (value) {
                          if (entry.key == 'title' &&
                              (value ?? '').trim().isEmpty) {
                            return 'Enter a title.';
                          }
                          if ([
                                'year',
                                'season',
                                'episode',
                              ].contains(entry.key) &&
                              value?.isNotEmpty == true) {
                            final n = int.tryParse(value!);
                            if (n == null ||
                                n < 0 ||
                                (entry.key == 'episode' && n == 0)) {
                              return 'Enter a valid number.';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  const AppGap(20),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!form.currentState!.validate()) return;
                            setSheet(() => saving = true);
                            try {
                              await widget.library.update(
                                VideoAsset.fromJson({
                                  ...asset.toJson(),
                                  'metadata': {
                                    ...asset.metadata,
                                    for (final entry in controls.entries)
                                      entry.key: entry.value.text.trim(),
                                  },
                                  'metadataSource': 'manual',
                                  'metadataStatus': '',
                                  if (controls['series'] != null &&
                                      controls['series']!.text.trim() !=
                                          asset.metadata['series']) ...{
                                    'seriesId': null,
                                    'providerId': null,
                                  },
                                  if (controls.containsKey('episode'))
                                    'episodeId': null,
                                }, collection.subtype),
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Could not save metadata.'),
                                  ),
                                );
                              }
                            } finally {
                              if (sheetContext.mounted) {
                                setSheet(() => saving = false);
                              }
                            }
                          },
                    child: Text(saving ? 'Saving…' : 'Save metadata'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    // The bottom-sheet exit animation can still reference its controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final control in controls.values) {
      control.dispose();
    }
  }

  Future<void> review(VideoAsset asset) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VideoMetadataSearchPage(
          library: widget.library,
          asset: asset,
          query: metadataQuery(lookupAsset(asset), metadataSubtype(asset)),
        ),
      ),
    );
  }

  Future<void> openSeries(SeriesRecord series) =>
      NavigationCoordinator.forOwner(widget.library.service.persistenceOwner)
          .run(
            'series:${series.id}',
            () async {
              if (!widget.library.canAccessCollection(
                series.assets.first.collectionId,
              )) {
                return;
              }
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SeriesDetails(
                    library: widget.library,
                    series: series,
                    play: (asset, external) => play(asset, external: external),
                    editEpisode: editMetadata,
                    matchEpisode: review,
                  ),
                ),
              );
            },
            origin: NavigationOrigin(
              routeId: 'catalog',
              collectionId: collection.id,
              query: search.text,
              folder: folder,
              sort: collection.sort,
              filter: collection.filter,
              layout: view.name,
              scrollOffset: scroll.hasClients
                  ? scroll.offset.clamp(0, double.infinity)
                  : 0,
            ),
            restore: (origin) =>
                restoreOrigin(context, origin, query: search, scroll: scroll),
          );
  void selectAssets(List<VideoAsset> assets) {
    setState(() {
      selecting = true;
      if (assets.every((a) => selected.contains(a.id))) {
        selected.removeAll(assets.map((a) => a.id));
      } else {
        selected.addAll(assets.map((a) => a.id));
      }
    });
  }

  Future<void> bulkAction(String action) async {
    if (!CatalogActionRegistry.permitted(
      CatalogActionScope.selection,
      action,
      MediaActionContext(
        authorized: widget.library.canAccessCollection(collection.id),
        capabilities: appSubtypes
            .definition(collection.mediaSubtype)
            .capabilities,
      ),
    )) {
      return;
    }
    final assets = widget.library
        .items(collection.id)
        .where((a) => selected.contains(a.id))
        .toList();
    if (assets.isEmpty) return;
    try {
      if (action == 'tags') {
        await editVideoTags(context, widget.library, assets);
      } else if (action == 'metadata') {
        await matchAll(assetIds: assets.map((a) => a.id).toSet());
      } else {
        await widget.library.flags(
          assets,
          {
                'unwatched': 'watched',
                'unfavorite': 'favorite',
                'unwatchLater': 'watchLater',
              }[action] ??
              action,
          !['unwatched', 'unfavorite', 'unwatchLater'].contains(action),
        );
      }
      if (mounted) {
        setState(() {
          selecting = false;
          selected.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not complete the selection action. Try again.',
        );
      }
    }
  }

  Future<void> showView() async {
    final choice = await showCollectionView(
      context,
      layout: collection.view == CatalogView.list
          ? 'list'
          : collection.view == CatalogView.compact
          ? 'compact'
          : 'grid',
      sort: collection.sort,
      sorts: catalogSorts,
      cardSize: collection.cardSize,
      descending: browsing.descending,
    );
    if (choice != null && mounted) {
      setState(() => browsing.descending = choice.descending);
      await saveBrowsing({
        'view': choice.layout,
        'sort': choice.sort,
        'cardSize': choice.cardSize,
      });
    }
  }

  Future<void> showFilters() async {
    var sort = collection.sort;
    var filter =
        collection.subtype == VideoSubtype.videos &&
            ['movies', 'tv'].contains(collection.filter)
        ? 'all'
        : collection.filter;
    final values = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: AppSpacing.of(context).all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filters', style: Theme.of(context).textTheme.titleLarge),
              const AppGap(24),
              DropdownButtonFormField<String>(
                icon: const AppIcon(AppIconRole.expand),
                key: ValueKey(filter),
                initialValue: filter,
                decoration: const InputDecoration(labelText: 'Show'),
                items: [
                  for (final e in catalogFilters.entries)
                    if (collection.subtype != VideoSubtype.videos ||
                        !['movies', 'tv'].contains(e.key))
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => update(() => filter = v!),
              ),
              const AppGap(16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => update(() {
                      filter = 'all';
                    }),
                    child: const Text('Reset'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, {
                      'sort': sort,
                      'filter': filter,
                      'scrollOffset': 0.0,
                    }),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (values != null && mounted) {
      await saveBrowsing(values);
      if (scroll.hasClients) scroll.jumpTo(0);
    }
  }

  Future<void> saveBrowsing(Map<String, dynamic> values) async {
    try {
      final offset = scroll.hasClients
          ? scroll.offset
          : collection.scrollOffset;
      await widget.library.saveBrowsing(collection.id, {
        'scrollOffset': offset,
        ...values,
      });
      await widget.library.load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save browsing preferences. Try again.',
        );
      }
    }
  }

  Future<void> watchAction(VideoAsset asset, String action) async {
    try {
      await widget.library.watch(asset, action);
      if (action == 'restart' && mounted) {
        await play(
          widget.library
              .items(collection.id)
              .firstWhere((a) => a.id == asset.id),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not update watch status. Try again.');
      }
    }
  }

  Future<void> chooseArtwork(VideoAsset asset, {SeriesRecord? series}) async {
    var kind = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose artwork'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'postersDevice'),
            child: const Text('Poster from device'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'backdropsDevice'),
            child: const Text('Backdrop from device'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'posters'),
            child: const Text('Poster'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'backdrops'),
            child: const Text('Backdrop'),
          ),
        ],
      ),
    );
    if (kind == null) return;
    final device = kind.endsWith('Device');
    kind = kind.replaceAll('Device', '');
    final artworkService = ArtworkService();
    final cancellation = MetadataCancellation();
    try {
      String? selected;
      if (device) {
        selected = await widget.library.imports.cover();
        if (selected == null || !mounted) return;
        selected = await artworkService.select(
          ArtworkCandidate(
            location: selected,
            role: kind == 'posters' ? ArtworkRole.poster : ArtworkRole.backdrop,
            source: ArtworkSource.device,
            ownerId: series?.id ?? asset.id,
          ),
          cancellation,
        );
      } else {
        if (!mounted) {
          return;
        }
        selected = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => PluginArtworkPage(
              collection: asset.collectionId,
              kind: asset.mediaSubtype == VideoSubtype.tv
                  ? ExtensionMedia.television
                  : ExtensionMedia.movie,
              titleId: asset.id,
              title: asset.title,
              role: kind == 'posters' ? 'poster' : 'backdrop',
            ),
          ),
        );
      }
      if (selected != null) {
        await widget.library.videoArtwork.select(
          series == null ? [asset] : series.assets,
          kind,
          selected,
          series: series != null,
          cancelled: () => !mounted,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not load artwork. Check your connection and retry.',
        );
      }
    }
  }

  Future<void> sourceStatus() =>
      showFolderHealth(context, collection, settings);

  void parentFolder() {
    if (folder.isEmpty) return;
    final parts = splitFolder(folder);
    final path = parts.length > 1 ? parts[1] : '';
    if (path.isEmpty) {
      openFolder('');
      return;
    }
    final segments = path.split('/')..removeLast();
    segments.removeLast();
    openFolder(
      folderToken(
        parts.first,
        segments.isEmpty ? '' : '${segments.join('/')}/',
      ),
    );
  }

  void openFolder(String next) {
    setState(() => folder = next);
    if (scroll.hasClients) scroll.jumpTo(0);
    saveBrowsing({'folder': next, 'scrollOffset': 0.0});
  }

  Widget folderTile(String name, String token, int count, bool grid) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => openFolder(token),
      child: grid
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  AppIconRole.folder,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count videos',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : ListTile(
              leading: AppIcon(
                AppIconRole.folder,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(name),
              subtitle: Text('$count videos'),
              trailing: const AppIcon(AppIconRole.disclosure),
            ),
    ),
  );

  Future<void> settings({String? initialSection}) async {
    final initialSubtype = collection.subtype;
    final initialExtensions = (collection.extensions.toList()..sort()).join(
      ',',
    );
    final initialRoots = collection.roots
        .map((r) => '${r.uri}:${r.contentSubtype}')
        .join();
    final updated = await collectionDialog(
      context,
      widget.library,
      existing: collection,
      initialSection: initialSection,
    );
    if (mounted &&
        !widget.library.collections.any((c) => c.id == widget.collectionId)) {
      Navigator.pop(context);
      return;
    }
    if (updated != null && mounted) {
      job.collection = updated;
      setState(() {
        view = updated.view;
        folder = updated.allowFolders ? updated.folder : '';
      });
      if (updated.roots.isNotEmpty &&
          (updated.roots.map((r) => '${r.uri}:${r.contentSubtype}').join() !=
                  initialRoots ||
              (updated.extensions.toList()..sort()).join(',') !=
                  initialExtensions ||
              updated.subtype != initialSubtype)) {
        folder = '';
        await saveBrowsing({'folder': '', 'scrollOffset': 0.0});
        await scan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    memory.changed();
    browsing.replace(widget.library.items(collection.id));
    browsing.query = search.text;
    browsing.sort = collection.sort;
    browsing.filter = collection.filter;
    browsing.layout = view == CatalogView.compact
        ? CatalogLayout.compact
        : view == CatalogView.list
        ? CatalogLayout.list
        : CatalogLayout.grid;
    final filtered = browseVideos(
      widget.library.items(collection.id),
      query: search.text,
      filter: collection.filter,
      sort: collection.sort,
      controller: browsing,
    );
    var items = filtered;
    final folders = <({String name, String token, int count})>[];
    if (collection.allowFolders &&
        search.text.isEmpty &&
        !['review', 'failed'].contains(collection.filter)) {
      if (folder.isEmpty) {
        for (final root in collection.roots) {
          final count = filtered.where((a) => a.rootUri == root.uri).length;
          if (count > 0 || collection.filter == 'all') {
            folders.add((
              name: root.name,
              token: folderToken(root.uri, ''),
              count: count,
            ));
          }
        }
        items = filtered
            .where(
              (a) =>
                  a.rootUri.isEmpty ||
                  !collection.roots.any((r) => r.uri == a.rootUri),
            )
            .toList();
      } else {
        final parts = splitFolder(folder);
        final root = parts.first;
        final path = parts.length > 1 ? parts[1] : '';
        final inside = filtered
            .where((a) => a.rootUri == root && a.relativePath.startsWith(path))
            .toList();
        final names = <String, int>{};
        for (final a in inside) {
          final rest = a.relativePath.substring(path.length);
          if (rest.contains('/')) {
            names.update(
              rest.split('/').first,
              (n) => n + 1,
              ifAbsent: () => 1,
            );
          }
        }
        for (final name in names.keys.toList()..sort()) {
          folders.add((
            name: name,
            token: folderToken(root, '$path$name/'),
            count: names[name]!,
          ));
        }
        items = inside
            .where((a) => !a.relativePath.substring(path.length).contains('/'))
            .toList();
      }
    }
    final series = collection.subtype == VideoSubtype.videos
        ? <SeriesRecord>[]
        : buildSeries(items);
    final displayed = collection.subtype == VideoSubtype.videos
        ? items
        : browseVideos([
            ...items.where((a) => a.mediaSubtype != VideoSubtype.tv),
            ...series.map((s) => s.card),
          ], sort: collection.sort);
    final seriesCards = {for (final s in series) s.card.id: s};
    final totalEntries = folders.length + displayed.length;
    final grid = view != CatalogView.list && view != CatalogView.compact;
    Widget entry(int i) => i < folders.length
        ? folderTile(folders[i].name, folders[i].token, folders[i].count, grid)
        : tile(
            displayed[i - folders.length],
            grid,
            series: seriesCards[displayed[i - folders.length].id],
            compact: view == CatalogView.compact,
            posterOnly: view == CatalogView.posterWall,
          );
    final scanning = widget.library.scanning.contains(collection.id);
    final missingMetadata = widget.library
        .items(collection.id)
        .where(
          (a) =>
              a.metadataSource == 'filename' &&
              a.available &&
              a.metadataStatus != 'review',
        )
        .length;
    final warnings = widget.library.warnings[collection.id] ?? [];
    return PopScope(
      canPop: !selecting && (!collection.allowFolders || folder.isEmpty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (selecting) {
            setState(() {
              selecting = false;
              selected.clear();
            });
          } else {
            parentFolder();
          }
        }
      },
      child: Scaffold(
        bottomNavigationBar: SharedAudioMiniPlayer(
          owner: widget.library.service.persistenceOwner,
        ),
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
                    widget.library.service.persistenceOwner,
                    collection.mediaSubtype,
                  ),
                  scope: collection.name,
                  overview: false,
                  onOverview: () =>
                      enterSpace(collection.subtype == VideoSubtype.videos),
                  onBrowse: () {},
                ),
          leading: selecting
              ? IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: () => setState(() {
                    selecting = false;
                    selected.clear();
                  }),
                  icon: const AppIcon(AppIconRole.close),
                )
              : collection.allowFolders && folder.isNotEmpty
              ? IconButton(
                  tooltip: 'Back to parent folder',
                  onPressed: parentFolder,
                  icon: const AppIcon(AppIconRole.back),
                )
              : null,
          title: Text(
            selecting ? '${selected.length} selected' : collection.name,
          ),
          actions: [
            if (selecting) ...[
              IconButton(
                tooltip: 'Select all visible',
                onPressed: () =>
                    setState(() => selected.addAll(items.map((a) => a.id))),
                icon: const AppIcon(AppIconRole.selectAll),
              ),
              PopupMenuButton<String>(
                icon: const AppIcon(AppIconRole.menu),
                tooltip: 'Selection actions',
                onSelected: bulkAction,
                itemBuilder: (_) => catalogActionMenu(
                  [
                    for (final entry in {
                      'tags': 'Edit tags',
                      'watched': 'Mark watched',
                      'unwatched': 'Mark unwatched',
                      'favorite': 'Add to Favorites',
                      'watchLater': 'Add to Watch later',
                      'unfavorite': 'Remove from Favorites',
                      'unwatchLater': 'Remove from Watch later',
                      'clearMatches': 'Clear online matches',
                      'metadata': 'Fetch missing metadata',
                    }.entries)
                      PopupMenuItem(
                        value: entry.key,
                        enabled: selected.isNotEmpty && !matching,
                        child: Text(entry.value),
                      ),
                  ],
                  scope: CatalogActionScope.selection,
                  context: MediaActionContext(
                    authorized: widget.library.canAccessCollection(
                      collection.id,
                    ),
                    capabilities: appSubtypes
                        .definition(collection.mediaSubtype)
                        .capabilities,
                  ),
                ),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Collection settings',
                onPressed: scanning || matching ? null : settings,
                icon: const AppIcon(AppIconRole.settings),
              ),
              CollectionActionsMenu(
                icon: const AppIcon(AppIconRole.menu),
                tooltip: 'Collection actions',
                onSelected: (v) {
                  if (!CatalogActionRegistry.permitted(
                    CatalogActionScope.collection,
                    v,
                    MediaActionContext(
                      authorized: widget.library.canAccessCollection(
                        collection.id,
                      ),
                      capabilities: appSubtypes
                          .definition(collection.mediaSubtype)
                          .capabilities,
                    ),
                  )) {
                    return;
                  }
                  if (v == 'settings') settings();
                  if (v == 'playerSettings') {
                    settings(initialSection: 'Playback');
                  }
                  if (v == 'tags') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CollectionTags(
                          library: widget.library,
                          collectionId: collection.id,
                        ),
                      ),
                    );
                  }
                  if (v == 'resume') matchAll(resume: true);
                  if (v == 'metadataStatus') metadataStatus();
                  if (v == 'select') setState(() => selecting = true);
                  if (v == 'groupSeries') {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SeriesGroupingPage(
                          library: widget.library,
                          collectionId: collection.id,
                        ),
                      ),
                    );
                  }
                  if (v == 'videoSpace') enterVideoSpace();
                  if (v == 'cinemaSpace') enterCinema();
                  if (v == 'scan') scan();
                  if (v == 'match') matchAll();
                  if (v == 'retry') matchAll(failedOnly: true);
                  if (v == 'health') sourceStatus();
                  if (v == 'review') {
                    search.clear();
                    folder = '';
                    saveBrowsing({'filter': 'review', 'folder': ''});
                  }
                },
                itemBuilder: (_) => catalogActionMenu(
                  [
                    const PopupMenuItem(
                      value: 'settings',
                      child: Text('Settings'),
                    ),
                    const PopupMenuItem(
                      value: 'tags',
                      child: Text('Manage tags'),
                    ),
                    const PopupMenuItem(
                      value: 'playerSettings',
                      child: Text('Player settings'),
                    ),
                    if (collection.subtype != VideoSubtype.videos)
                      const PopupMenuItem(
                        value: 'cinemaSpace',
                        child: Text('Enter Cinema space'),
                      ),
                    if (job.resumable)
                      PopupMenuItem(
                        value: 'resume',
                        enabled: !scanning,
                        child: Text(
                          'Resume metadata (${job.remaining.length} remaining)',
                        ),
                      ),
                    if (collection.subtype != VideoSubtype.videos)
                      const PopupMenuItem(
                        value: 'groupSeries',
                        child: Text('Manage series grouping'),
                      ),
                    const PopupMenuItem(
                      value: 'select',
                      child: Text('Select videos'),
                    ),
                    if (collection.subtype == VideoSubtype.videos)
                      const PopupMenuItem(
                        value: 'videoSpace',
                        child: Text('Enter Multiplexr video space'),
                      ),
                    PopupMenuItem(
                      value: 'scan',
                      enabled:
                          !scanning && !matching && collection.roots.isNotEmpty,
                      child: const Text('Scan folders'),
                    ),
                    PopupMenuItem(
                      value: 'match',
                      enabled: !matching && !scanning && missingMetadata > 0,
                      child: Text('Fetch missing metadata ($missingMetadata)'),
                    ),
                    PopupMenuItem(
                      value: 'retry',
                      enabled:
                          !matching &&
                          !scanning &&
                          widget.library
                              .items(collection.id)
                              .any((a) => a.metadataStatus == 'failed'),
                      child: const Text('Retry failed metadata'),
                    ),
                    const PopupMenuItem(
                      value: 'review',
                      child: Text('Review metadata matches'),
                    ),
                    const PopupMenuItem(
                      value: 'metadataStatus',
                      child: Text('Metadata job details'),
                    ),
                    const PopupMenuItem(
                      value: 'health',
                      child: Text('Folder health'),
                    ),
                  ],
                  scope: CatalogActionScope.collection,
                  context: MediaActionContext(
                    authorized: widget.library.canAccessCollection(
                      collection.id,
                    ),
                    capabilities: appSubtypes
                        .definition(collection.mediaSubtype)
                        .capabilities,
                  ),
                ),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            if (!matching && (job.resumable || job.lastError != null))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        job.lastError ??
                            'Metadata paused · ${job.remaining.length} remaining',
                      ),
                    ),
                    if (job.resumable)
                      TextButton(
                        onPressed: scanning
                            ? null
                            : () => matchAll(resume: true),
                        child: const Text('Resume'),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Visibility(
                visible: controlsExpanded,
                maintainState: true,
                child: CollectionBrowseToolbar(
                  query: search,
                  onChanged: (_) => setState(() {}),
                  onFilters: showFilters,
                  onView: showView,
                  count: items.length,
                  filters: {
                    if (collection.filter != 'all')
                      catalogFilters[collection.filter] ?? collection.filter:
                          () => saveBrowsing({'filter': 'all'}),
                  },
                  onClearFilters: () => saveBrowsing({'filter': 'all'}),
                ),
              ),
            ),
            if (collection.allowFolders &&
                folder.isNotEmpty &&
                search.text.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Parent folder',
                      onPressed: parentFolder,
                      icon: const AppIcon(AppIconRole.sortAscending),
                    ),
                    Expanded(
                      child: Text(
                        '${collection.roots.where((r) => r.uri == splitFolder(folder).first).firstOrNull?.name ?? 'Folder'}/${splitFolder(folder).last}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => openFolder(''),
                      child: const Text('Roots'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${collection.subtype.label} · ${widget.library.items(collection.id).length} ${widget.library.items(collection.id).length == 1 ? 'item' : 'items'}',
                ),
              ),
            ),
            if (scanning || matching) ...[
              LinearProgressIndicator(
                value: matching && matchTotal > 0
                    ? matchDone / matchTotal
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  scanning
                      ? 'Indexing ${widget.library.scanProgress[collection.id]?["found"] ?? 0} videos… ${widget.library.scanProgress[collection.id]?["folder"] ?? ""}'
                      : 'Metadata · batch ${job.batch}/${job.batches} · $matchDone / $matchTotal',
                ),
              ),
            ],
            if (scanning || matching)
              TextButton.icon(
                onPressed: () async {
                  if (matching) {
                    job.cancel();
                  } else {
                    await widget.library.cancelScan(collection.id);
                  }
                },
                icon: const AppIcon(AppIconRole.stop),
                label: Text(
                  matching && job.cancelled
                      ? 'Finishing current request…'
                      : 'Cancel',
                ),
              ),
            if (matchSummary != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(matchSummary!),
              ),
            if (error != null)
              Padding(
                padding: AppSpacing.of(context).all(16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final warning in warnings)
              Padding(padding: const EdgeInsets.all(8), child: Text(warning)),
            Expanded(
              child: totalEntries == 0
                  ? Center(
                      child: Padding(
                        padding: AppSpacing.of(context).all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(AppIconRole.videoLibrary, size: 40),
                            const AppGap(16),
                            Text(
                              search.text.isNotEmpty
                                  ? 'No matching videos'
                                  : scanning
                                  ? 'Finding videos…'
                                  : 'No videos in this view',
                            ),
                            const AppGap(12),
                            if (!scanning && search.text.isEmpty)
                              OutlinedButton(
                                onPressed: collection.roots.isEmpty
                                    ? settings
                                    : scan,
                                child: Text(
                                  collection.roots.isEmpty
                                      ? 'Add root folder'
                                      : 'Scan folders',
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : !grid
                  ? ListView.builder(
                      controller: scroll,
                      key: PageStorageKey('${collection.id}-$view-$folder'),
                      itemCount: totalEntries,
                      padding: AppSpacing.of(context).all(16),
                      itemBuilder: (_, i) => entry(i),
                    )
                  : GridView.builder(
                      controller: scroll,
                      key: PageStorageKey('${collection.id}-$view-$folder'),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: collection.cardSize,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent:
                            collection.cardSize *
                            (view == CatalogView.posterWall ? 1.45 : 1.5),
                      ),
                      padding: AppSpacing.of(context).all(20),
                      itemCount: totalEntries,
                      itemBuilder: (_, i) => entry(i),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget tile(
    VideoAsset asset,
    bool grid, {
    bool compact = false,
    bool posterOnly = false,
    SeriesRecord? series,
  }) {
    final members = series?.assets ?? [asset];
    void open() {
      if (selecting) {
        selectAssets(members);
      } else if (series != null) {
        openSeries(series);
      } else {
        openVideoTitle(
          context,
          widget.library,
          asset,
          legacyDetails: false,
          origin: NavigationOrigin(
            routeId: 'catalog',
            collectionId: collection.id,
            query: search.text,
            sort: collection.sort,
            filter: collection.filter,
            folder: folder,
            layout: view.name,
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
                });
              }
            },
          ),
          details: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => VideoTitleDetails(
                  asset: asset,
                  library: widget.library,
                  subtype: asset.mediaSubtype,
                  play: (item, external) => play(item, external: external),
                ),
              ),
            );
          },
          play: () => play(asset),
        );
      }
    }

    final actions = PopupMenuButton<String>(
      tooltip: 'Options for ${asset.title}',
      icon: AppIcon(
        AppIconRole.menu,
        color: posterOnly ? Colors.white : null,
        shadows: posterOnly
            ? const [Shadow(color: Colors.black87, blurRadius: 4)]
            : null,
      ),
      onSelected: (v) {
        if (!widget.library.canAccessCollection(asset.collectionId)) return;
        if (!CatalogActionRegistry.permitted(
          series == null ? CatalogActionScope.title : CatalogActionScope.group,
          v,
          MediaActionContext(
            authorized: widget.library.canAccessCollection(asset.collectionId),
            capabilities: appSubtypes
                .definition(collection.mediaSubtype)
                .capabilities,
          ),
        )) {
          return;
        }
        final commonAction = switch (v) {
          'settings' => MediaActionId.settings,
          'edit' => MediaActionId.editMetadata,
          'artwork' => MediaActionId.chooseArtwork,
          'match' => MediaActionId.findMetadata,
          _ => null,
        };
        if (commonAction != null &&
            !MediaActionRegistry.permitted(
              commonAction,
              MediaActionContext(
                authorized: widget.library.canAccessCollection(
                  asset.collectionId,
                ),
                capabilities: appSubtypes
                    .definition(collection.mediaSubtype)
                    .capabilities,
                hasSettings: series == null,
              ),
            )) {
          return;
        }
        if (v == 'settings') {
          showMediaNavigationSettings(
            context,
            widget.library.service,
            MediaNavigationSettings.key(asset.collectionId, asset.mediaId.key),
            'Title',
            showRate: false,
          );
        }
        if (v == 'internal') {
          if (series != null) {
            openSeries(series);
          } else {
            play(asset, external: false);
          }
        }
        if (v == 'external') {
          if (series != null) {
            openSeries(series);
          } else {
            play(asset, external: true);
          }
        }
        if (v == 'edit') {
          if (series != null) {
            openSeries(series);
          } else {
            editMetadata(asset);
          }
        }
        if (v == 'match') {
          if (series != null) {
            openSeries(series);
          } else {
            review(asset);
          }
        }
        if (['watched', 'unwatched'].contains(v) && series != null) {
          widget.library.flags(members, 'watched', v == 'watched').catchError((
            Object _,
          ) {
            if (mounted) setState(() => error = 'Could not save watch status.');
          });
        } else if (v == 'hide' && series != null) {
          widget.library.flags(members, 'hideContinue', true).catchError((
            Object _,
          ) {
            if (mounted) {
              setState(() => error = 'Could not update Continue watching.');
            }
          });
        } else if (v == 'restart' && series != null) {
          openSeries(series);
        } else if (['watched', 'unwatched', 'restart', 'hide'].contains(v)) {
          watchAction(asset, v);
        }
        if (v == 'tags') editVideoTags(context, widget.library, members);
        if (v == 'artwork') chooseArtwork(asset, series: series);
        if (v == 'favorite') {
          widget.library
              .flags(members, 'favorite', !members.any((a) => a.favorite))
              .catchError((Object _) {
                if (mounted) setState(() => error = 'Could not save favorite.');
              });
        }
        if (v == 'watchLater') {
          widget.library
              .flags(members, 'watchLater', !members.any((a) => a.watchLater))
              .catchError((Object _) {
                if (mounted) {
                  setState(() => error = 'Could not save Watch later.');
                }
              });
        }
      },
      itemBuilder: (_) => catalogActionMenu(
        [
          ...mediaMetadataActions(
            settings: series == null,
            authorized: widget.library.canAccessCollection(asset.collectionId),
            find: 'match',
            canEdit: !matching,
            canArtwork: !matching,
            canFind: !matching,
          ),
          const PopupMenuItem(value: 'tags', child: Text('Edit tags')),
          PopupMenuItem(
            value: 'favorite',
            child: Text(
              members.any((a) => a.favorite)
                  ? 'Remove from Favorites'
                  : 'Add to Favorites',
            ),
          ),
          PopupMenuItem(
            value: 'watchLater',
            child: Text(
              members.any((a) => a.watchLater)
                  ? 'Remove from Watch later'
                  : 'Add to Watch later',
            ),
          ),
          const PopupMenuItem(
            value: 'internal',
            child: Text('Play in Multiplexr'),
          ),
          const PopupMenuItem(
            value: 'external',
            child: Text('Play in external player'),
          ),
          PopupMenuItem(
            value: asset.watched ? 'unwatched' : 'watched',
            child: Text(asset.watched ? 'Mark unwatched' : 'Mark watched'),
          ),
          PopupMenuItem(
            value: 'restart',
            child: Text(
              series == null ? 'Play from beginning' : 'Choose an episode',
            ),
          ),
          if (series == null
              ? asset.inProgress
              : members.any((a) => a.inProgress))
            const PopupMenuItem(
              value: 'hide',
              child: Text('Remove from Continue watching'),
            ),
        ],
        scope: series == null
            ? CatalogActionScope.title
            : CatalogActionScope.group,
        context: MediaActionContext(
          authorized: widget.library.canAccessCollection(collection.id),
          capabilities: appSubtypes
              .definition(collection.mediaSubtype)
              .capabilities,
        ),
      ),
    );
    final subtitle = series != null
        ? series.summary
        : metadataSubtype(asset) == VideoSubtype.tv
        ? '${asset.metadata['series'] ?? ''} · S${asset.metadata['season'] ?? '?'} E${asset.metadata['episode'] ?? '?'}'
        : [
            asset.metadata['year'],
            if (asset.durationMs > 0)
              '${(asset.durationMs / 60000).ceil()} min',
          ].whereType<String>().join(' · ');
    Widget art() => Stack(
      fit: StackFit.expand,
      children: [
        VideoArtwork(asset: asset, posterFirst: true),
        if (!selecting &&
            (asset.watched ||
                !asset.available ||
                asset.metadataStatus.isNotEmpty))
          Positioned(
            left: 6,
            top: 6,
            child: Tooltip(
              message: !asset.available
                  ? 'File unavailable'
                  : asset.watched
                  ? 'Watched'
                  : asset.metadataStatus == 'review'
                  ? 'Needs metadata review'
                  : 'Metadata failed',
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: AppIcon(
                  !asset.available
                      ? AppIconRole.folderUnavailable
                      : asset.watched
                      ? AppIconRole.confirm
                      : AppIconRole.info,
                  size: 18,
                ),
              ),
            ),
          ),
      ],
    );
    if (!grid) {
      return MediaItemSelection(
        selected: selecting
            ? members.every((a) => selected.contains(a.id))
            : null,
        onToggle: () => selectAssets(members),
        reserveLeading: !grid,
        child: Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            dense: compact,
            visualDensity: compact
                ? VisualDensity.compact
                : VisualDensity.standard,
            onTap: open,
            onLongPress: () => selectAssets(members),
            selected: members.every((a) => selected.contains(a.id)),
            leading: selecting
                ? null
                : compact
                ? const AppIcon(AppIconRole.play)
                : SizedBox(width: 48, height: 64, child: art()),
            title: Text(
              asset.title,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(subtitle.isEmpty ? asset.filename : subtitle),
            trailing: actions,
          ),
        ),
      );
    }
    if (posterOnly) {
      return MediaItemSelection(
        selected: selecting
            ? members.every((a) => selected.contains(a.id))
            : null,
        onToggle: () => selectAssets(members),
        reserveLeading: !grid,
        child: Tooltip(
          message: asset.title,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: open,
              onLongPress: () => selectAssets(members),
              child: Stack(
                children: [
                  Positioned.fill(child: art()),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: .9),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 32, 8),
                        child: Text(
                          asset.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: interfaceRadius(context, 24),
                      child: actions,
                    ),
                  ),
                  if (asset.positionMs > 0 && asset.durationMs > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: (asset.positionMs / asset.durationMs).clamp(
                          0,
                          1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return MediaItemSelection(
      selected: selecting
          ? members.every((a) => selected.contains(a.id))
          : null,
      onToggle: () => selectAssets(members),
      reserveLeading: !grid,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          onLongPress: () => selectAssets(members),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: art()),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        asset.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    actions,
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text(
                  subtitle.isEmpty ? asset.filename : subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (asset.positionMs > 0 && asset.durationMs > 0)
                LinearProgressIndicator(
                  value: (asset.positionMs / asset.durationMs).clamp(0, 1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
