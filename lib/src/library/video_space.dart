import 'dart:convert';

import '../catalog/domain/classification.dart';
import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';
import '../experience/navigation/browse_memory.dart';
import '../experience/navigation/navigation_origin.dart';
import '../media/navigation_origin_controls.dart';
import '../media/video_navigation.dart';
import '../space_preferences.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'package:flutter/services.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'cinema_view.dart';
import 'player.dart';
import 'video_art.dart';
import 'queue_view.dart';
import 'video_scope.dart';

class MultiplexrVideoSpace extends StatefulWidget {
  const MultiplexrVideoSpace({
    super.key,
    required this.library,
    this.collectionId,
    this.spaceSettings,
    this.display,
    this.collectionName = 'All Videos',
    this.openCollection,
  });
  final LibraryController library;
  final Future<void> Function()? spaceSettings;
  final SpaceDisplay? display;
  final String? collectionId;
  final String collectionName;
  final Future<void> Function(VideoCollection)? openCollection;
  @override
  State<MultiplexrVideoSpace> createState() => _MultiplexrVideoSpaceState();
}

class _MultiplexrVideoSpaceState extends State<MultiplexrVideoSpace> {
  bool controlsExpanded = false;
  late final memory = BrowseMemory(
    preferences: widget.library.service.userPreferences,
    query: search,
    scroll: scroll,
    alive: () => mounted,
    capture: () => NavigationOrigin(
      routeId: 'videos',
      collectionId: widget.collectionId,
      query: search.text,
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
      sort: sort,
      layout: jsonEncode([layout, cardSize, descending]),
      filter: '$filter',
      folder: folder ?? '',
      tag: tag ?? '',
      tab: page,
    ),
    defaults: () => NavigationOrigin(
      routeId: 'videos',
      collectionId: widget.collectionId,
      tab: 0,
      sort: 'added',
    ),
    apply: (origin) {
      if (mounted) {
        setState(() {
          page = origin.tab.clamp(0, 2);
          try {
            final v = jsonDecode(origin.layout) as List;
            layout = {'grid', 'list', 'compact'}.contains(v[0])
                ? v[0] as String
                : 'list';
            cardSize = (v[1] as num).toDouble().clamp(120, 280);
            descending = v[2] as bool;
          } catch (_) {
            layout = 'list';
            cardSize = 240;
            descending = false;
          }
          sort = ['added', 'title', 'duration', 'played'].contains(origin.sort)
              ? origin.sort
              : 'added';
          customizedSort = origin.sort.isNotEmpty;
          filter = (int.tryParse(origin.filter) ?? 0).clamp(0, 4);
          folder = origin.folder.isEmpty ? null : origin.folder;
          tag = origin.tag.isEmpty ? null : origin.tag;
        });
      }
    },
  );

  final search = TextEditingController();
  final scroll = ScrollController();
  int page = 0, filter = 0;
  String sort = 'added', layout = 'list';
  double cardSize = 240;
  bool descending = false;
  String? folder, tag;
  bool launching = false, customizedSort = false;
  bool get global => widget.collectionId == null;
  List<VideoAsset> get scope =>
      videoSpaceItems(widget.library, collectionId: widget.collectionId);
  List<VideoAsset> get queue =>
      videoSpaceQueue(widget.library, collectionId: widget.collectionId);
  @override
  void initState() {
    super.initState();
    page = 0;
    memory.restore();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    widget.library.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void updateFeed(VoidCallback change) {
    setState(change);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    memory.dispose();
    widget.library.removeListener(refresh);
    search.dispose();
    scroll.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> openSource(VideoAsset asset) async {
    final source = widget.library.collections
        .where((c) => c.id == asset.collectionId)
        .firstOrNull;
    if (source == null) {
      message('This source collection no longer exists.');
      return;
    }
    await widget.openCollection?.call(source);
    if (mounted) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void openTitle(VideoAsset asset) {
    openVideoTitle(
      context,
      widget.library,
      asset,
      legacyDetails: false,
      origin: NavigationOrigin(
        routeId: 'videos',
        collectionId: widget.collectionId,
        query: search.text,
        sort: sort,
        filter: '$filter',
        folder: folder ?? '',
        tag: tag ?? '',
        tab: page,
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
              page = origin.tab;
              sort = origin.sort;
              filter = int.tryParse(origin.filter) ?? 0;
              folder = origin.folder.isEmpty ? null : origin.folder;
              tag = origin.tag.isEmpty ? null : origin.tag;
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
              play: (item, external) => external
                  ? widget.library.service.external(item)
                  : watch(item),
            ),
          ),
        );
      },
      play: () => watch(asset),
    );
  }

  Future<void> watch(VideoAsset selected) async {
    if (launching) return;
    launching = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      var asset = scope
          .where(
            (a) =>
                a.id == selected.id && a.collectionId == selected.collectionId,
          )
          .firstOrNull;
      if (asset == null || !asset.available) {
        message(
          'File unavailable. Check its source collection and scan again.',
        );
        return;
      }
      if (asset.watched) {
        await widget.library.watch(asset, 'restart');
        asset = scope
            .where(
              (a) =>
                  a.id == selected.id &&
                  a.collectionId == selected.collectionId,
            )
            .firstOrNull;
        if (asset == null || !asset.available) return;
      }
      if (queue.any(
        (a) => widget.library.queueKey(a) == widget.library.queueKey(asset!),
      )) {
        await widget.library.removeQueued(asset);
      }
      if (!mounted) return;
      final current = asset;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplexrPlayer(
            asset: current,
            host: widget.library.videoPlayback,
            watchPage: true,
            related: scope,
            library: widget.library,
            globalVideos: global,
            openSource: global && widget.openCollection != null
                ? openSource
                : null,
          ),
        ),
      );
      await widget.library.load();
    } catch (_) {
      message('Could not open this video. Check its source and try again.');
    } finally {
      launching = false;
    }
  }

  Future<void> viewOptions() async {
    final value = await showCollectionView(
      context,
      layout: layout,
      sort: sort,
      sorts: const {
        'added': 'Newest first',
        'title': 'Title',
        'duration': 'Duration',
        'played': 'Last played',
      },
      cardSize: cardSize,
      descending: descending,
    );
    if (value != null && mounted) {
      updateFeed(() {
        layout = value.layout;
        sort = value.sort;
        cardSize = value.cardSize;
        descending = value.descending;
        customizedSort = true;
      });
    }
  }

  Future<void> options() async {
    final folders = <String, String>{
      for (final a in scope)
        videoFolderKey(a): videoFolderLabel(a, widget.library, global: global),
    };
    final tags = <String, String>{
      for (final a in scope)
        for (final t in videoTags(a)) t.toLowerCase(): t,
    };
    var nextFolder = folders.containsKey(folder) ? folder : null;
    var nextTag = tags.containsKey(tag?.toLowerCase()) ? tag : null;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                const AppGap(20),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  key: ValueKey('folder-$nextFolder'),
                  initialValue: nextFolder ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Folder'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All folders'),
                    ),
                    for (final e
                        in folders.entries.toList()
                          ..sort((a, b) => a.value.compareTo(b.value)))
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) =>
                      update(() => nextFolder = v == '' ? null : v),
                ),
                const AppGap(20),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  key: ValueKey('tag-$nextTag'),
                  initialValue: nextTag?.toLowerCase() ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tag'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All tags')),
                    for (final e
                        in tags.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key)))
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => update(() => nextTag = v == '' ? null : v),
                ),
                const AppGap(24),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => update(() {
                        nextFolder = null;
                        nextTag = null;
                      }),
                      child: const Text('Reset'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      updateFeed(() {
        folder = nextFolder;
        tag = nextTag;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    memory.changed();
    final source = scope;
    final activeFolder = source.any((a) => videoFolderKey(a) == folder)
        ? folder
        : null;
    final activeTag =
        source.any(
          (a) => videoTags(a).any((t) => t.toLowerCase() == tag?.toLowerCase()),
        )
        ? tag
        : null;
    final category = page == 2 || (page == 0 && filter == 1)
        ? 'progress'
        : page == 0 && filter == 3
        ? 'favorite'
        : page == 0 && filter == 4
        ? 'watchLater'
        : 'all';
    final visible = browseVideoFeed(
      widget.display?.hideWatched == true && category == 'all'
          ? source.where((a) => !a.watched).toList()
          : source,
      query: page == 1 ? search.text : '',
      filter: category,
      sort: customizedSort
          ? sort
          : page == 2 || (page == 0 && filter == 1)
          ? 'played'
          : 'added',
      folder: activeFolder,
      tag: activeTag,
    );
    if (page != 0 && descending) {
      final reversed = visible.reversed.toList();
      visible
        ..clear()
        ..addAll(reversed);
    }
    return Scaffold(
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
            MediaSubtype.videos,
          ),
          scope: widget.collectionId == null
              ? 'All collections'
              : widget.collectionName,
          overview: page == 0,
          onOverview: () => updateFeed(() => page = 0),
          onBrowse: () {
            if (widget.collectionId != null && Navigator.canPop(context)) {
              Navigator.maybePop(context);
            } else {
              updateFeed(() => page = 1);
            }
          },
        ),
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Videos',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              widget.collectionName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          BrowseResetButton(memory: memory),
          IconButton(
            tooltip: 'Search videos',
            onPressed: () => updateFeed(() {
              page = 1;
              controlsExpanded = true;
            }),
            icon: const AppIcon(AppIconRole.search),
          ),
          IconButton(
            tooltip: 'Video queue',
            onPressed: () => showVideoQueue(
              context,
              widget.library,
              watch,
              items: () => queue,
            ),
            icon: const AppIcon(AppIconRole.playlistAdd),
          ),
          if (widget.spaceSettings != null)
            IconButton(
              tooltip: 'Space settings',
              onPressed: () async {
                await widget.spaceSettings!();
                if (mounted) setState(() {});
              },
              icon: const AppIcon(AppIconRole.settings),
            ),
          IconButton(
            tooltip: 'Exit video space',
            onPressed: () => Navigator.maybePop(context),
            icon: const AppIcon(AppIconRole.close),
          ),
        ],
      ),
      body: Column(
        children: [
          if (page == 1 && controlsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Visibility(
                visible: controlsExpanded,
                maintainState: true,
                child: CollectionBrowseToolbar(
                  query: search,
                  onChanged: (_) => updateFeed(() {}),
                  onFilters: options,
                  onView: viewOptions,
                  count: visible.length,
                  filters: {
                    if (activeFolder != null)
                      'Source folder': () => updateFeed(() => folder = null),
                    if (activeTag != null)
                      '#$activeTag': () => updateFeed(() => tag = null),
                  },
                  onClearFilters: () => updateFeed(() {
                    folder = null;
                    tag = null;
                  }),
                ),
              ),
            ),
          if (page == 0 && controlsExpanded)
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 0, 8),
                    child: Row(
                      children: [
                        if (page == 0)
                          for (final e in [
                            'All videos',
                            'Continue watching',
                            'Recently added',
                            'Favorites',
                            'Watch later',
                          ].asMap().entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(e.value),
                                selected: filter == e.key,
                                onSelected: (_) => updateFeed(() {
                                  filter = e.key;
                                  if (filter == 2) {
                                    sort = 'added';
                                    customizedSort = false;
                                  }
                                }),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Feed options',
                  onPressed: options,
                  icon: AppIcon(
                    AppIconRole.settings,
                    color: activeFolder != null || activeTag != null
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ],
            ),
          if (page == 0 && (activeFolder != null || activeTag != null))
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  if (activeFolder != null)
                    InputChip(
                      label: Text(
                        videoFolderLabel(
                          source.firstWhere(
                            (a) => videoFolderKey(a) == activeFolder,
                          ),
                          widget.library,
                          global: global,
                        ),
                      ),
                      onDeleted: () => updateFeed(() => folder = null),
                    ),
                  if (activeTag != null)
                    InputChip(
                      label: Text('#$activeTag'),
                      onDeleted: () => updateFeed(() => tag = null),
                    ),
                ],
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: AppSpacing.of(context).all(24),
                      child: Text(
                        page == 1
                            ? 'No matching videos'
                            : page == 2 || filter == 1
                            ? 'No videos in progress'
                            : 'No videos match this feed.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : page != 0 && layout == 'grid'
                ? GridView.builder(
                    controller: scroll,
                    padding: AppSpacing.of(context).all(16),
                    itemCount: visible.length,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: cardSize,
                      mainAxisExtent: cardSize * 9 / 16 + 100,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                    ),
                    itemBuilder: (_, i) => InkWell(
                      onTap: () => openTitle(visible[i]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: VideoArtwork(asset: visible[i]),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              visible[i].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : page != 0 && layout == 'compact'
                ? ListView.builder(
                    controller: scroll,
                    itemCount: visible.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: SizedBox(
                        width: 72,
                        height: 42,
                        child: VideoArtwork(asset: visible[i]),
                      ),
                      title: Text(visible[i].title),
                      onTap: () => openTitle(visible[i]),
                    ),
                  )
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView.separated(
                        controller: scroll,
                        key: PageStorageKey(
                          'video-feed-${widget.collectionId ?? 'global'}',
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const AppGap(24),
                        itemBuilder: (_, index) {
                          final a = visible[index];
                          return VideoFeedCard(
                            key: ValueKey(widget.library.queueKey(a)),
                            asset: a,
                            source: videoFolderLabel(
                              a,
                              widget.library,
                              global: global,
                            ),
                            onTap: () => openTitle(a),
                            trailing: VideoActions(
                              asset: a,
                              library: widget.library,
                              openSource:
                                  global && widget.openCollection != null
                                  ? () => openSource(a)
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
