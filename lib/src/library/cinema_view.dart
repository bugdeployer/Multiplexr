import '../experience/plugins/plugin_artwork_page.dart';
import '../features/catalog/application/extension_catalog.dart';

import 'dart:convert';

import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';
import '../media/source_recovery.dart';
import '../experience/navigation/browse_memory.dart';
import '../catalog/domain/classification.dart';
import 'video_scope.dart' show scopedVideoCollections;
import '../experience/navigation/navigation_coordinator.dart';
import '../media/video_projections.dart';
import '../experience/navigation/navigation_origin.dart';
import '../media/navigation_origin_controls.dart';
import '../media/video_navigation.dart';
import '../space_preferences.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'series.dart';
import 'series_view.dart';
import 'video_art.dart';

List<VideoAsset> continuingVideos(List<VideoAsset> items) =>
    seriesContinuation(items);
List<VideoAsset> recentlyAddedVideos(List<VideoAsset> items) =>
    (items.where((a) => a.addedAt > 0).toList()
          ..sort((a, b) => b.addedAt.compareTo(a.addedAt)))
        .take(20)
        .toList();

List<VideoCollection> cinemaCollections(LibraryController library) =>
    scopedVideoCollections(library, MediaSubtype.moviesTv);
List<VideoAsset> cinemaItems(
  LibraryController library, {
  String? collectionId,
}) => scopedVideoCollections(
  library,
  MediaSubtype.moviesTv,
  collectionId: collectionId,
).expand((c) => library.items(c.id)).toList();

List<String> videoGenres(VideoAsset asset) => (asset.metadata['genres'] ?? '')
    .split(RegExp(r'[,;|]'))
    .map((g) => g.trim())
    .where((g) => g.isNotEmpty)
    .toList();

List<String> cinemaGenres(List<VideoAsset> items) {
  final names = <String, String>{};
  for (final a in items) {
    for (final genre in videoGenres(a)) {
      names.putIfAbsent(genre.toLowerCase(), () => genre);
    }
  }
  return names.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

List<VideoAsset> filterCinemaItems(
  List<VideoAsset> items, {
  String category = 'all',
  String? genre,
}) {
  final typed = items
      .where(
        (a) =>
            category == 'all' ||
            (category == 'series'
                ? a.mediaSubtype == VideoSubtype.tv
                : a.mediaSubtype == VideoSubtype.movies),
      )
      .toList();
  if (genre == null) return typed;
  bool matches(VideoAsset a) =>
      videoGenres(a).any((g) => g.toLowerCase() == genre.toLowerCase());
  // Keep a matching show's complete local episode list and watch progression.
  final matchingSeries = buildSeries(typed)
      .where((s) => !s.needsIdentification && s.assets.any(matches));
  final members = {
    for (final series in matchingSeries)
      for (final a in series.assets) '${a.collectionId}\n${a.id}',
  };
  return typed
      .where(
        (a) => matches(a) || members.contains('${a.collectionId}\n${a.id}'),
      )
      .toList();
}

/// Collection cinema and global cinema share their presentation and source records.
class MultiplexrCinema extends StatefulWidget {
  const MultiplexrCinema({
    super.key,
    required this.library,
    this.collectionId,
    this.spaceSettings,
    this.display,
    this.collectionName = 'All Movies & TV',
    required this.play,
    this.editEpisode,
    this.matchEpisode,
  });
  final LibraryController library;
  final Future<void> Function()? spaceSettings;
  final SpaceDisplay? display;
  final String? collectionId;
  final String collectionName;
  final Future<void> Function(VideoAsset)? editEpisode, matchEpisode;
  final Future<void> Function(VideoAsset, bool) play;
  @override
  State<MultiplexrCinema> createState() => _MultiplexrCinemaState();
}

class _MultiplexrCinemaState extends State<MultiplexrCinema> {
  bool controlsExpanded = false;
  late final memory = BrowseMemory(
    preferences: widget.library.service.userPreferences,
    query: search,
    scroll: scroll,
    alive: () => mounted,
    capture: () => NavigationOrigin(
      routeId: 'cinema',
      collectionId: widget.collectionId,
      query: search.text,
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
      filter: category,
      sort: sort,
      layout: jsonEncode([layout, cardSize, descending]),
      tag: genre ?? '',
      tab: page,
    ),
    defaults: () => NavigationOrigin(
      routeId: 'cinema',
      collectionId: widget.collectionId,
      tab: 0,
      filter: 'all',
    ),
    apply: (origin) {
      if (mounted) {
        setState(() {
          page = origin.tab.clamp(0, 2);
          sort = {'title', 'year'}.contains(origin.sort)
              ? origin.sort
              : 'title';
          try {
            final v = jsonDecode(origin.layout) as List;
            layout = {'grid', 'list', 'compact'}.contains(v[0])
                ? v[0] as String
                : 'grid';
            cardSize = (v[1] as num).toDouble().clamp(120, 280);
            descending = v[2] as bool;
          } catch (_) {
            layout = 'grid';
            cardSize = 180;
            descending = false;
          }
          category = ['all', 'movies', 'series'].contains(origin.filter)
              ? origin.filter
              : 'all';
          genre = origin.tag.isEmpty ? null : origin.tag;
        });
      }
    },
  );

  final search = TextEditingController();
  final scroll = ScrollController();
  int page = 0;
  String category = 'all', sort = 'title', layout = 'grid';
  double cardSize = 180;
  bool descending = false;
  String? genre;
  bool get global => widget.collectionId == null;
  Future<void> viewOptions() async {
    final value = await showCollectionView(
      context,
      layout: layout,
      sort: sort,
      sorts: const {'title': 'Title', 'year': 'Year'},
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

  Future<void> filterOptions(List<String> genres) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheet) => ListView(
      shrinkWrap: true,
      padding: AppSpacing.of(context).all(24),
      children: [
        Text('Filters', style: Theme.of(sheet).textTheme.titleLarge),
        ListTile(
          title: const Text('All genres'),
          trailing: genre == null ? const AppIcon(AppIconRole.confirm) : null,
          onTap: () {
            setState(() => genre = null);
            Navigator.pop(sheet);
          },
        ),
        for (final name in genres)
          ListTile(
            title: Text(name),
            trailing: genre == name ? const AppIcon(AppIconRole.confirm) : null,
            onTap: () {
              setState(() => genre = name);
              Navigator.pop(sheet);
            },
          ),
      ],
    ),
  );
  String? sourceName(VideoAsset asset) => global
      ? widget.library.collections
            .where((c) => c.id == asset.collectionId)
            .firstOrNull
            ?.name
      : null;
  @override
  void initState() {
    super.initState();
    page = 0;
    memory.restore();
    widget.library.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    memory.dispose();
    widget.library.removeListener(refresh);
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void openTitle(VideoAsset asset) {
    final group = seriesFor(asset, widget.library.items(asset.collectionId));
    if (group != null) {
      details(asset);
      return;
    }
    final owner = widget.library.collections
        .where((c) => c.id == asset.collectionId)
        .firstOrNull;
    openVideoTitle(
      context,
      widget.library,
      asset,
      legacyDetails: true,
      origin: NavigationOrigin(
        scrollOffset: scroll.hasClients
            ? scroll.offset.clamp(0, double.infinity)
            : 0,
        routeId: 'cinema',
        collectionId: widget.collectionId,
        query: search.text,
        tab: page,
        filter: category,
        sort: sort,
        layout: jsonEncode([layout, cardSize, descending]),
        tag: genre ?? '',
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
              category = origin.filter;
              genre = origin.tag.isEmpty ? null : origin.tag;
            });
          }
        },
      ),
      details: () => details(asset),
      play: () async {
        widget.play(asset, owner?.player == PlaybackTarget.external);
      },
    );
  }

  Future<void> details(VideoAsset asset) =>
      NavigationCoordinator.forOwner(widget.library.service.persistenceOwner)
          .run(
            'cinema-details:${asset.mediaId.key}',
            () => _details(asset),
            origin: NavigationOrigin(
              routeId: 'cinema',
              collectionId: widget.collectionId,
              query: search.text,
              tab: page,
              filter: category,
              sort: sort,
              layout: jsonEncode([layout, cardSize, descending]),
              tag: genre ?? '',
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
                    category = origin.filter;
                    genre = origin.tag.isEmpty ? null : origin.tag;
                  });
                }
              },
            ),
          );
  Future<void> _details(VideoAsset asset) async {
    final series = seriesFor(asset, widget.library.items(asset.collectionId));
    if (series != null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SeriesDetails(
            library: widget.library,
            series: series,
            play: widget.play,
            editEpisode: widget.editEpisode,
            matchEpisode: widget.matchEpisode,
          ),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => VideoTitleDetails(
          asset: asset,
          play: widget.play,
          library: widget.library,
          subtype: asset.mediaSubtype,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    memory.changed();
    final scopedItems = cinemaItems(
      widget.library,
      collectionId: widget.collectionId,
    )..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final typedItems = filterCinemaItems(scopedItems, category: category);
    final genres = cinemaGenres(typedItems);
    final activeGenre = genres
        .where((g) => g.toLowerCase() == genre?.toLowerCase())
        .firstOrNull;
    final items = filterCinemaItems(typedItems, genre: activeGenre);
    final allTitles = groupedTitles(items);
    final titles =
        allTitles
            .where((a) => widget.display?.hideWatched != true || !a.watched)
            .toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final continuing = continuingVideos(items)
        .map(
          (a) => a.mediaSubtype == VideoSubtype.tv
              ? VideoAsset.fromJson({
                  ...a.toJson(),
                  'metadata': {
                    ...a.metadata,
                    'title':
                        '${a.metadata["series"] ?? a.title} · S${seasonNumber(a)} E${episodeNumber(a)}',
                  },
                }, VideoSubtype.tv)
              : a,
        )
        .toList();
    final recent = recentlyAddedVideos(titles);
    final results = groupedTitles(
      items
          .where(
            (a) => '${a.title} ${a.filename} ${a.metadata['series'] ?? ''}'
                .toLowerCase()
                .contains(search.text.toLowerCase()),
          )
          .toList(),
    ).where((a) => widget.display?.hideWatched != true || !a.watched).toList();
    results.sort((a, b) {
      final comparison = sort == 'year'
          ? (a.metadata['year'] ?? '').compareTo(b.metadata['year'] ?? '')
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return descending ? -comparison : comparison;
    });
    final featured =
        continuing.firstOrNull ?? recent.firstOrNull ?? titles.firstOrNull;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Movies & TV',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      BrowseResetButton(memory: memory),
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
                        tooltip: 'Exit cinema',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const AppIcon(AppIconRole.close),
                      ),
                    ],
                  ),
                  Text(
                    widget.collectionName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            CollectionExperienceHeader(
              expanded: controlsExpanded,
              onExpanded: () {
                if (controlsExpanded) FocusScope.of(context).unfocus();
                setState(() => controlsExpanded = !controlsExpanded);
              },
              onScope: () => CollectionScopeRouter.choose(
                context,
                widget.library.service.persistenceOwner,
                MediaSubtype.moviesTv,
              ),
              scope: global ? 'All collections' : widget.collectionName,
              overview: page == 0,
              onOverview: () => setState(() => page = 0),
              onBrowse: () {
                if (!global && Navigator.canPop(context)) {
                  Navigator.maybePop(context);
                } else {
                  setState(() => page = 1);
                }
              },
            ),
            if (controlsExpanded)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    for (final entry in {
                      'all': 'All',
                      'movies': 'Movies',
                      'series': 'Series',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(entry.value),
                          selected: category == entry.key,
                          onSelected: (_) => setState(() {
                            category = entry.key;
                            genre = null;
                          }),
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Filter genres',
                      enabled: genres.isNotEmpty,
                      initialValue: activeGenre ?? '',
                      onSelected: (value) =>
                          setState(() => genre = value.isEmpty ? null : value),
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          value: '',
                          checked: activeGenre == null,
                          child: const Text('All genres'),
                        ),
                        for (final name in genres)
                          CheckedPopupMenuItem(
                            value: name,
                            checked: activeGenre == name,
                            child: Text(name),
                          ),
                      ],
                      child: Chip(
                        avatar: const AppIcon(AppIconRole.settings, size: 18),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(activeGenre ?? 'Genres'),
                            const AppGap.horizontal(4),
                            const AppIcon(AppIconRole.expand, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: page == 0
                  ? items.isEmpty
                        ? Center(
                            child: Text(
                              scopedItems.isNotEmpty
                                  ? 'No titles match these categories.'
                                  : global
                                  ? 'No Movies & TV titles yet. Add folders to a Movies & TV collection.'
                                  : 'This collection has no videos yet.',
                            ),
                          )
                        : ListView(
                            controller: scroll,
                            key: const PageStorageKey('cinema-home'),
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              if (featured != null)
                                _CinemaHero(
                                  asset: featured,
                                  play: () =>
                                      featured.mediaSubtype == VideoSubtype.tv
                                      ? details(featured)
                                      : widget.play(featured, false),
                                  details: () => details(featured),
                                  open: () => openTitle(featured),
                                  eyebrow: continuing.isNotEmpty
                                      ? 'PICK UP WHERE YOU LEFT OFF'
                                      : global
                                      ? 'ALL COLLECTIONS'
                                      : 'COLLECTION',
                                ),
                              if (continuing.isNotEmpty)
                                shelf('Continue watching', continuing),
                              if (recent.isNotEmpty)
                                shelf('Recently added', recent),
                              if (allTitles.any((a) => a.favorite))
                                shelf(
                                  'Favorites',
                                  allTitles.where((a) => a.favorite).toList(),
                                ),
                              if (allTitles.any((a) => a.watchLater))
                                shelf(
                                  'Watch later',
                                  allTitles.where((a) => a.watchLater).toList(),
                                ),
                              shelf('All titles', titles),
                            ],
                          )
                  : Column(
                      children: [
                        if (page == 1)
                          Padding(
                            padding: AppSpacing.of(context).all(20),
                            child: Visibility(
                              visible: controlsExpanded,
                              maintainState: true,
                              child: CollectionBrowseToolbar(
                                query: search,
                                onChanged: (_) => setState(() {}),
                                count: results.length,
                                onFilters: () => filterOptions(genres),
                                onView: viewOptions,
                                filters: {
                                  ?activeGenre: () =>
                                      setState(() => genre = null),
                                },
                                onClearFilters: () =>
                                    setState(() => genre = null),
                              ),
                            ),
                          ),
                        Expanded(
                          child: (page == 1 ? results : titles).isEmpty
                              ? const Center(child: Text('No matching titles'))
                              : layout != 'grid'
                              ? ListView.builder(
                                  controller: scroll,
                                  padding: AppSpacing.of(context).all(20),
                                  itemCount: results.length,
                                  itemBuilder: (_, i) => ListTile(
                                    dense: layout == 'compact',
                                    leading: SizedBox(
                                      width: 40,
                                      height: 60,
                                      child: _CinemaArt(results[i]),
                                    ),
                                    title: Text(results[i].title),
                                    subtitle: Text(
                                      sourceName(results[i]) ??
                                          results[i].metadata['year'] ??
                                          '',
                                    ),
                                    onTap: () => openTitle(results[i]),
                                  ),
                                )
                              : GridView.builder(
                                  controller: scroll,
                                  padding: AppSpacing.of(context).all(20),
                                  gridDelegate:
                                      SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: cardSize,
                                        mainAxisExtent:
                                            cardSize * 1.5 + (global ? 70 : 45),
                                        mainAxisSpacing: 16,
                                        crossAxisSpacing: 12,
                                      ),
                                  itemCount:
                                      (page == 1 ? results : titles).length,
                                  itemBuilder: (_, i) => _CinemaPoster(
                                    asset: (page == 1 ? results : titles)[i],
                                    onTap: openTitle,
                                    source: sourceName(
                                      (page == 1 ? results : titles)[i],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget shelf(String title, List<VideoAsset> assets) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      SizedBox(
        height: global ? 275 : 250,
        child: ListView.separated(
          key: PageStorageKey('cinema-$title'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: assets.length,
          separatorBuilder: (_, _) => const AppGap.horizontal(12),
          itemBuilder: (_, i) => SizedBox(
            width: 150,
            child: _CinemaPoster(
              asset: assets[i],
              onTap: openTitle,
              source: sourceName(assets[i]),
            ),
          ),
        ),
      ),
    ],
  );
}

class _CinemaArt extends StatelessWidget {
  const _CinemaArt(this.asset, {this.landscape = false});
  final VideoAsset asset;
  final bool landscape;
  @override
  Widget build(BuildContext context) =>
      VideoArtwork(asset: asset, posterFirst: !landscape);
}

class _CinemaPoster extends StatelessWidget {
  const _CinemaPoster({required this.asset, required this.onTap, this.source});
  final VideoAsset asset;
  final String? source;
  final void Function(VideoAsset) onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Details for ${asset.title}',
    child: InkWell(
      borderRadius: interfaceRadius(context, 18),
      onTap: () => onTap(asset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InterfaceClip(
              radius: 18,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CinemaArt(asset),
                  if (asset.positionMs > 0 && asset.durationMs > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
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
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              asset.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          if (source != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                source!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    ),
  );
}

class _CinemaHero extends StatelessWidget {
  const _CinemaHero({
    required this.asset,
    required this.play,
    required this.details,
    required this.eyebrow,
    required this.open,
  });
  final VideoAsset asset;
  final VoidCallback play, details, open;
  final String eyebrow;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: open,
      child: Stack(
        children: [
          Positioned.fill(child: _CinemaArt(asset, landscape: true)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.surface.withValues(alpha: .15),
                    colors.surface.withValues(alpha: .85),
                    Theme.of(context).scaffoldBackgroundColor,
                  ],
                  stops: const [0, .65, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 180, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const AppGap(12),
                Text(
                  asset.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const AppGap(8),
                Text(
                  [
                    asset.metadata['year'],
                    asset.metadata['genres'],
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if ((asset.metadata['description'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      asset.metadata['description']!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const AppGap(20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: play,
                      icon: const AppIcon(AppIconRole.play),
                      label: Text(
                        asset.positionMs > 0 && !asset.watched
                            ? 'Resume'
                            : 'Play',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: details,
                      icon: const AppIcon(AppIconRole.info),
                      label: const Text('Details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoTitleDetails extends StatefulWidget {
  const VideoTitleDetails({
    super.key,
    required this.asset,
    required this.play,
    required this.library,
    required this.subtype,
  });
  final VideoAsset asset;
  final LibraryController library;
  final VideoSubtype subtype;
  final Future<void> Function(VideoAsset, bool) play;
  @override
  State<VideoTitleDetails> createState() => VideoTitleDetailsState();
}

class VideoTitleDetailsState extends State<VideoTitleDetails> {
  late VideoAsset asset = widget.asset;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
  }

  Future<void> refreshArtwork() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => PluginArtworkPage(
            collection: asset.collectionId,
            kind: asset.mediaSubtype == VideoSubtype.tv
                ? ExtensionMedia.television
                : ExtensionMedia.movie,
            titleId: asset.id,
            title: asset.title,
            role: 'backdrop',
          ),
        ),
      );
      if (result == null || !mounted) return;
      await widget.library.videoArtwork.select(
        [asset],
        'backdrop',
        result,
        series: false,
        cancelled: () => !mounted,
      );
      final current = widget.library
          .items(asset.collectionId)
          .where((a) => a.id == asset.id)
          .firstOrNull;
      if (mounted && current != null) setState(() => asset = current);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not apply artwork. Reopen the picker and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> play(bool external) async {
    await widget.play(asset, external);
    if (!mounted) return;
    final latest = widget.library
        .items(asset.collectionId)
        .where((a) => a.id == asset.id)
        .firstOrNull;
    if (latest != null) setState(() => asset = latest);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final runtime = int.tryParse(asset.metadata['runtimeMinutes'] ?? '');
    final summary = [
      asset.metadata['year'],
      if (runtime != null)
        '${runtime ~/ 60 > 0 ? '${runtime ~/ 60}h ' : ''}${runtime % 60}m',
      if (asset.metadata['season'] != null)
        'Season ${asset.metadata['season']} · Episode ${asset.metadata['episode'] ?? '?'}',
    ].whereType<String>().where((v) => v.isNotEmpty).join('  ·  ');
    final genres = (asset.metadata['genres'] ?? '')
        .split(',')
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).width > 600 ? 400 : 300,
                  width: double.infinity,
                  child: _CinemaArt(asset, landscape: true),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.surface.withValues(alpha: .25),
                            colors.surface.withValues(alpha: .05),
                            Theme.of(context).scaffoldBackgroundColor,
                          ],
                          stops: const [0, .5, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 12,
                  child: SafeArea(
                    bottom: false,
                    child: IconButton.filledTonal(
                      tooltip: 'Back to cinema',
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.surface.withValues(alpha: .85),
                        foregroundColor: colors.onSurface,
                      ),
                      icon: const AppIcon(AppIconRole.back),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    asset.title,
                    style: Theme.of(context).textTheme.headlineLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        summary,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  if (genres.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final genre in genres)
                            Chip(
                              label: Text(genre),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                  if (!asset.available)
                    TextButton.icon(
                      onPressed: () => recoverCollectionSource(
                        context,
                        asset.collectionId,
                        controller: widget.library,
                        authorized: () => widget.library.canAccessCollection(
                          asset.collectionId,
                        ),
                      ),
                      icon: const AppIcon(AppIconRole.folderUnavailable),
                      label: const Text('Folder health'),
                    ),
                  const AppGap(20),
                  FilledButton.icon(
                    onPressed: () => play(false),
                    icon: const AppIcon(AppIconRole.play),
                    label: Text(
                      asset.positionMs > 0 && !asset.watched
                          ? 'Resume'
                          : 'Play',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => play(true),
                    icon: const AppIcon(AppIconRole.externalLink),
                    label: const Text('Open in external player'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await widget.library.watch(
                            asset,
                            asset.watched ? 'unwatched' : 'watched',
                          );
                          final latest = widget.library
                              .items(asset.collectionId)
                              .where((a) => a.id == asset.id)
                              .firstOrNull;
                          if (mounted && latest != null) {
                            setState(() => asset = latest);
                          }
                        },
                        icon: AppIcon(
                          asset.watched
                              ? AppIconRole.success
                              : AppIconRole.success,
                        ),
                        label: Text(asset.watched ? 'Watched' : 'Mark watched'),
                      ),
                      if (asset.positionMs > 0)
                        TextButton(
                          onPressed: () async {
                            await widget.library.watch(asset, 'restart');
                            final latest = widget.library
                                .items(asset.collectionId)
                                .where((a) => a.id == asset.id)
                                .firstOrNull;
                            if (mounted && latest != null) {
                              setState(() => asset = latest);
                              await play(false);
                            }
                          },
                          child: const Text('Play from beginning'),
                        ),
                      if (asset.inProgress)
                        TextButton(
                          onPressed: () async {
                            await widget.library.watch(asset, 'hide');
                            final latest = widget.library
                                .items(asset.collectionId)
                                .where((a) => a.id == asset.id)
                                .firstOrNull;
                            if (mounted && latest != null) {
                              setState(() => asset = latest);
                            }
                          },
                          child: const Text('Remove from Continue watching'),
                        ),
                      if (asset.backdrop == null)
                        TextButton(
                          onPressed: loading ? null : refreshArtwork,
                          child: const Text('Fetch missing artwork'),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await widget.library.flags(
                            [asset],
                            'favorite',
                            !asset.favorite,
                          );
                          if (mounted) {
                            setState(
                              () => asset = widget.library
                                  .items(asset.collectionId)
                                  .firstWhere((a) => a.id == asset.id),
                            );
                          }
                        },
                        icon: AppIcon(
                          asset.favorite
                              ? AppIconRole.favoriteSelected
                              : AppIconRole.favorite,
                        ),
                        label: const Text('Favorite'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await widget.library.flags(
                            [asset],
                            'watchLater',
                            !asset.watchLater,
                          );
                          if (mounted) {
                            setState(
                              () => asset = widget.library
                                  .items(asset.collectionId)
                                  .firstWhere((a) => a.id == asset.id),
                            );
                          }
                        },
                        icon: AppIcon(
                          asset.watchLater
                              ? AppIconRole.bookmarkSelected
                              : AppIconRole.bookmark,
                        ),
                        label: const Text('Watch later'),
                      ),
                    ],
                  ),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null)
                    Row(
                      children: [
                        Expanded(child: Text(error!)),
                        TextButton(
                          onPressed: refreshArtwork,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  if ((asset.metadata['tagline'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        asset.metadata['tagline']!,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                  if ((asset.metadata['description'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        asset.metadata['description']!,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(height: 1.6),
                      ),
                    ),
                  for (final field in {
                    'cast': 'Cast',
                    'director': 'Director',
                    'series': 'Series',
                    'airDate': 'Air date',
                    'tags': 'Tags',
                    'recordedDate': 'Recorded date',
                  }.entries)
                    if ((asset.metadata[field.key] ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field.value,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const AppGap(4),
                            Text(asset.metadata[field.key]!),
                          ],
                        ),
                      ),
                  const AppGap(12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('File details'),
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(asset.filename),
                        subtitle: Text(
                          [
                            if (asset.width > 0 && asset.height > 0)
                              '${asset.width} × ${asset.height}',
                            if (asset.durationMs > 0)
                              '${asset.durationMs ~/ 1000}s local file',
                          ].join(' · '),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
