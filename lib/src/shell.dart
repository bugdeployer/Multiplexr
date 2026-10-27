import 'experience/plugins/plugin_navigation_shell.dart';
import 'experience/plugins/package_manager_page.dart';
import 'experience/plugins/plugin_contribution_page.dart';
import 'experience/plugins/plugin_settings_page.dart';
import 'experience/plugins/plugin_manager.dart';
import 'media/session_mini_player.dart';
import 'features/catalog/application/music_catalog_commands.dart';
import 'settings/presentation/players_readers_page.dart';
import 'media/shared_audio_mini_player.dart';
import 'experience/app_session_scope.dart';
import 'experience/collection/collection_scope_router.dart';
import 'reading/reading_app_controller.dart';
import 'reading/reading_activity.dart';
import 'reading/reading_space.dart';
import 'reading/reading_workflow_widgets.dart' show ReadingCover;
import 'media/music_page.dart';
import 'media/media_cover.dart';
import 'experience/collection/job_status_page.dart';
import 'features/catalog/application/space_queries.dart';

import 'space_preferences.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, kProfileMode;

import 'package:app_shell/app_shell.dart';

import 'package:flutter/services.dart';

import 'settings.dart';
import 'library/library_models.dart';
import 'library/library_controller.dart';
import 'library/collection_form.dart';
import 'library/catalog.dart';
import 'library/cinema_view.dart';
import 'library/player.dart';
import 'library/series.dart';
import 'library/video_art.dart';
import 'library/video_space.dart';
import 'library/video_scope.dart';
import 'library/backup_page.dart';
import 'media/audiobooks_page.dart';
import 'media/audiobook_space.dart';
import 'media_space_card.dart';
import 'media/audiobook_cover.dart';
import 'media/contracts.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settings,
    required this.library,
    required this.sessions,
    this.plugins,
  });
  final SettingsController settings;
  final LibraryController library;
  final AppSessionScope sessions;
  final PluginManager? plugins;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final navigation = ShellNavigationController([
    'library',
    'spaces',
    'settings',
  ]);
  int get page => navigation.selectedIndex;
  set page(int value) => navigation.select(value);
  int settingsPage = 0;
  bool busy = false;
  final spacePreferences = SpacePreferences();
  late final sessions = widget.sessions;
  late final music = sessions.music;
  SettingsController get s => widget.settings;
  late final reading = sessions.reading;
  void readingChanged() {
    if (mounted) setState(() {});
  }

  void readingSecurityChanged() => reading.securityChanged();

  @override
  void initState() {
    super.initState();
    SharedAudioMiniPlayer.register(
      widget.library.service.persistenceOwner,
      music,
    );
    CollectionScopeRouter.register(
      widget.library.service.persistenceOwner,
      CollectionScopeRouter(
        options: (subtype) => [
          for (final c in widget.library.collections)
            if (c.mediaSubtype == subtype &&
                widget.library.canAccessCollection(c.id))
              CollectionScopeOption(c.id, c.name),
          for (final c in reading.bundle?.catalog.collections ?? [])
            if (c.subtype == subtype && reading.canAccess(c.id))
              CollectionScopeOption(c.id, c.name),
        ],
        open: (subtype, id) async {
          if (!mounted) return;
          if (subtype == MediaSubtype.ebook || subtype == MediaSubtype.comics) {
            if (id == null) {
              await openReadingSpace(context, reading, SpaceScope(subtype));
            } else {
              await openReadingCollection(context, reading, id);
            }
          } else if (id != null) {
            final c = widget.library.collections
                .where(
                  (c) =>
                      c.id == id &&
                      c.mediaSubtype == subtype &&
                      widget.library.canAccessCollection(c.id),
                )
                .firstOrNull;
            if (c != null) await openCollection(c);
          } else if (subtype == MediaSubtype.music) {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => MusicPage(
                  library: widget.library,
                  playback: music,
                  space: true,
                ),
              ),
            );
          } else if (subtype == MediaSubtype.audiobooks) {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => AudiobookSpace(library: widget.library),
              ),
            );
          } else if (subtype == MediaSubtype.videos) {
            await openGlobalVideos();
          } else {
            await openGlobalCinema();
          }
        },
      ),
    );
    reading.addListener(readingChanged);
    s.addListener(readingSecurityChanged);
    reading.load();
    music.attach().catchError((Object _) {
      // A saved queue can still be resumed explicitly from Music space.
    });
    spacePreferences.load(widget.library.service.userPreferences).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SharedAudioMiniPlayer.register(
      widget.library.service.persistenceOwner,
      null,
    );
    CollectionScopeRouter.register(
      widget.library.service.persistenceOwner,
      null,
    );
    s.removeListener(readingSecurityChanged);
    reading.removeListener(readingChanged);
    sessions.dispose();
    navigation.dispose();
    super.dispose();
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
    });
    try {
      await action();
    } on PlatformException catch (e) {
      if (mounted) {
        message(e.message ?? 'The device could not complete this action.');
      }
    } catch (_) {
      if (mounted) message('Could not save this change. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final label = page == 2
        ? [
            'SETTINGS',
            'APPEARANCE',
            'SECURITY',
            'NOTIFICATIONS',
            'METADATA',
            'BACKUP & RESTORE',
          ][settingsPage]
        : ['LIBRARY', 'SPACES'][page];
    return PopScope(
      canPop: s.locked || s.covered || page == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !s.locked && ModalRoute.of(context)?.isCurrent == true) {
          setState(() {
            if (settingsPage != 0) {
              settingsPage = 0;
            } else {
              page = 0;
            }
          });
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (s.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
              systemNavigationBarColor: s.base,
              systemNavigationBarIconBrightness: s.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
        child: Scaffold(
          body: !s.ready
              ? const Center(child: CircularProgressIndicator())
              : (s.locked || s.covered)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          AppIconRole.lock,
                          size: 40,
                          color: color.primary,
                        ),
                        const AppGap(24),
                        if (s.supported && !s.secureDevice)
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => run(
                                    s.deviceSettings.openSecuritySettings,
                                  ),
                            child: const Text('Set up device screen lock'),
                          ),
                        const Text(
                          'Multiplexr is locked',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const AppGap(12),
                        Text(
                          s.error ??
                              (s.useBiometrics
                                  ? 'Unlock with biometrics or your device screen lock.'
                                  : 'Unlock with your device screen lock.'),
                          textAlign: TextAlign.center,
                        ),
                        const AppGap(24),
                        FilledButton.icon(
                          onPressed: busy || s.error != null
                              ? null
                              : () => run(() async {
                                  if (!await s.unlock() && mounted) {
                                    message('Not unlocked. You can try again.');
                                  }
                                }),
                          icon: const AppIcon(AppIconRole.biometric),
                          label: Text(busy ? 'Authenticating…' : 'Unlock'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        key: ValueKey('page-$page-section-$settingsPage'),
                        padding: EdgeInsets.fromLTRB(
                          s.compact ? 16 : 24,
                          s.compact ? 20 : 30,
                          s.compact ? 16 : 24,
                          32,
                        ),
                        children: [
                          if (page == 2 && settingsPage != 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(48, 48),
                                  alignment: Alignment.centerLeft,
                                ),
                                onPressed: () =>
                                    setState(() => settingsPage = 0),
                                icon: const AppIcon(AppIconRole.back),
                                label: const Text('Settings'),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: page == 2 && settingsPage != 0
                                        ? 28
                                        : 32,
                                    fontWeight: FontWeight.w500,
                                    color: color.primary,
                                    letterSpacing: -.8,
                                  ),
                                ),
                              ),
                              if (page < 2)
                                IconButton(
                                  tooltip: 'Activity',
                                  icon: const AppIcon(AppIconRole.activity),
                                  onPressed: () => Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (activityContext) =>
                                          JobStatusPage(
                                            library: widget.library,
                                            additionalChanges: reading,
                                            additionalJobs: () =>
                                                readReadingActivity(
                                                  reading,
                                                  (id) => openReadingCollection(
                                                    activityContext,
                                                    reading,
                                                    id,
                                                    showJobs: true,
                                                  ),
                                                ),
                                            actionsFor: (status) => {
                                              if (!status.metadata &&
                                                  widget.library.scanning
                                                      .contains(
                                                        status.collection.id,
                                                      ))
                                                'Cancel scan': () =>
                                                    widget.library.cancelScan(
                                                      status.collection.id,
                                                    ),
                                              if (status.metadata &&
                                                  status.collection.kind ==
                                                      MediaKind.music &&
                                                  music
                                                      .jobFor(
                                                        status.collection.id,
                                                      )
                                                      .running)
                                                'Cancel metadata job':
                                                    () async {
                                                      music
                                                          .jobFor(
                                                            status
                                                                .collection
                                                                .id,
                                                          )
                                                          .cancel();
                                                    },
                                              if (status.metadata &&
                                                  status.remaining > 0 &&
                                                  status.collection.kind ==
                                                      MediaKind.music &&
                                                  !music
                                                      .jobFor(
                                                        status.collection.id,
                                                      )
                                                      .running)
                                                'Resume metadata job': () async {
                                                  final tracks = await widget
                                                      .library
                                                      .musicCatalog
                                                      .tracks(
                                                        SpaceScope(
                                                          MediaSubtype.music,
                                                          collectionId: status
                                                              .collection
                                                              .id,
                                                        ),
                                                      );
                                                  await music
                                                      .jobFor(
                                                        status.collection.id,
                                                      )
                                                      .start(
                                                        tracks,
                                                        resume: true,
                                                      );
                                                },
                                            },
                                            openCollection:
                                                (collection, metadata) =>
                                                    openCollection(
                                                      collection,
                                                      showJobs: metadata,
                                                    ),
                                          ),
                                    ),
                                  ),
                                ),
                              if (page < 2)
                                PopupMenuButton<int>(
                                  tooltip: 'View options',
                                  icon: const AppIcon(AppIconRole.compactGrid),
                                  initialValue: page == 1
                                      ? s.spacesView
                                      : s.libraryView,
                                  onSelected: (value) => run(
                                    () => s.setHomeView(
                                      spaces: page == 1,
                                      value: value,
                                    ),
                                  ),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 0,
                                      child: Text(
                                        page == 1 ? 'Showcase' : 'List',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 1,
                                      child: Text('Grid'),
                                    ),
                                    const PopupMenuItem(
                                      value: 2,
                                      child: Text('Compact'),
                                    ),
                                  ],
                                ),
                              if (page == 0)
                                IconButton.filledTonal(
                                  tooltip: 'New collection',
                                  onPressed:
                                      !s.supported ||
                                          !widget.library.ready ||
                                          widget.library.error != null
                                      ? null
                                      : createCollection,
                                  icon: s.pixel
                                      ? const AppIcon(AppIconRole.add, size: 20)
                                      : const AppIcon(AppIconRole.add),
                                ),
                            ],
                          ),
                          const AppGap(24),
                          if (page == 0) ...[...libraryContent()],
                          if (page == 1) ...spacesContent(),
                          if (page == 2) ...settingsContent(context),
                        ],
                      ),
                    ),
                  ),
                ),
          bottomNavigationBar: shellBottomBar(),
        ),
      ),
    );
  }

  Widget? shellBottomBar({VoidCallback? onNavigate}) =>
      !s.ready || s.locked || s.covered
      ? null
      : DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: .5),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SessionMiniPlayer(playback: music),
              ShellNavigationBar(
                animationDuration:
                    s.reduceMotion || MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppMotion.duration(context),
                selectedIndex: page,
                onDestinationSelected: (v) {
                  onNavigate?.call();
                  setState(() {
                    page = v;
                    settingsPage = 0;
                  });
                },
                destinations: [
                  NavigationDestination(
                    icon: const AppIcon(AppIconRole.library),
                    selectedIcon: const AppIcon(AppIconRole.library),
                    label: 'LIBRARY',
                  ),
                  NavigationDestination(
                    icon: const AppIcon(AppIconRole.spaces),
                    selectedIcon: const AppIcon(AppIconRole.spaces),
                    label: 'SPACES',
                  ),
                  NavigationDestination(
                    icon: const AppIcon(AppIconRole.settings),
                    label: 'SETTINGS',
                  ),
                ],
              ),
            ],
          ),
        );

  Future<void> openPackages() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (routeContext) => PluginNavigationShell(
        bottomBar: () =>
            shellBottomBar(onNavigate: () => Navigator.pop(routeContext)),
        page: PackageManagerPage(
          manager: widget.plugins!,
          settings: widget.settings,
          onBack: () => Navigator.pop(routeContext),
        ),
      ),
    ),
  );

  Future<void> createCollection() async {
    String? readingId;
    final collection = await collectionDialog(
      context,
      widget.library,
      readingNames: {
        for (final c in reading.bundle?.catalog.collections ?? [])
          c.name.toLowerCase(),
      },
      saveReading: (row, preferences) async {
        await reading.create(row, preferences: preferences);
        readingId = row['id'] as String;
      },
    );
    if (readingId != null && mounted) {
      await openReadingCollection(context, reading, readingId!, scan: true);
    } else if (collection != null && mounted) {
      await openCollection(collection, scan: collection.roots.isNotEmpty);
    }
  }

  Future<void> openCollection(
    VideoCollection collection, {
    bool scan = false,
    bool showJobs = false,
  }) async {
    widget.library.beginCollectionSession(collection.id);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => collection.kind == MediaKind.music
              ? MusicPage(
                  library: widget.library,
                  playback: music,
                  collectionId: collection.id,
                  scan: scan,
                  showJobs: showJobs,
                )
              : collection.isAudio
              ? AudiobooksPage(
                  catalog: widget.library.audiobookCatalog(
                    collectionId: collection.id,
                  ),
                  libraryController: widget.library,
                  collectionId: collection.id,
                  scan: scan,
                  showJobsOnOpen: showJobs,
                )
              : CollectionCatalog(
                  library: widget.library,
                  collectionId: collection.id,
                  notifications: s.platform,
                  scanOnOpen: scan,
                  showJobsOnOpen: showJobs,
                  spacePreferences: spacePreferences,
                ),
        ),
      );
    } finally {
      widget.library.endCollectionSession();
    }
  }

  Future<void> openGlobalCinema() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SpaceExitGuard(
        preferences: spacePreferences,
        videos: false,
        child: MultiplexrCinema(
          library: widget.library,
          play: playCinema,
          display: spacePreferences.cinema,
          spaceSettings: () => editSpace(false),
        ),
      ),
    ),
  );

  Future<void> openGlobalVideos() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SpaceExitGuard(
        preferences: spacePreferences,
        videos: true,
        child: MultiplexrVideoSpace(
          spaceSettings: () => editSpace(true),
          display: spacePreferences.videos,
          library: widget.library,
          openCollection: (collection) => openCollection(collection),
        ),
      ),
    ),
  );

  Future<void> playCinema(VideoAsset selected, bool external) async {
    try {
      final library = widget.library;
      var asset = cinemaItems(
        library,
        collectionId: selected.collectionId,
      ).where((a) => a.id == selected.id).firstOrNull;
      if (asset == null || !asset.available) {
        message(
          'This file is unavailable. Check its source collection and scan again.',
        );
        return;
      }
      if (asset.watched) {
        await library.watch(asset, 'restart');
        asset = cinemaItems(
          library,
          collectionId: selected.collectionId,
        ).where((a) => a.id == selected.id).firstOrNull;
        if (asset == null || !asset.available) return;
      }
      if (!mounted) return;
      if (external) {
        await library.service.external(asset);
      } else {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplexrPlayer(
              asset: asset!,
              host: library.videoPlayback,
              landscapeOnly: true,
              library: library,
            ),
          ),
        );
        await library.load();
      }
    } catch (_) {
      if (mounted) {
        message(
          'Could not start this video. Check its source or try another player.',
        );
      }
    }
  }

  List<Widget> spacesContent() {
    final library = widget.library;
    if (!library.ready) {
      return [const Center(child: CircularProgressIndicator())];
    }
    if (library.error != null) {
      return [
        Text(library.error!),
        TextButton(onPressed: library.load, child: const Text('Retry')),
      ];
    }
    final audioCount = library.collections
        .where(
          (c) =>
              c.kind == MediaKind.audiobook &&
              !c.locked &&
              c.includeInGlobalAudio,
        )
        .length;
    final audioSpace = compactSpaceCard(
      title: 'Audiobooks',
      icon: AppIconRole.reading,
      count: audioCount,
      onTap: openGlobalAudiobooks,
    );
    if (s.spacesView != 0) {
      final cards = [
        for (final videos in [false, true]) compactSpace(videos),
        audioSpace,
        for (final subtype in [MediaSubtype.ebook, MediaSubtype.comics])
          readingSpaceCard(subtype, compact: true),
        compactSpaceCard(
          title: 'Music',
          icon: AppIconRole.music,
          count: library.collections
              .where(
                (c) =>
                    c.kind == MediaKind.music &&
                    !c.locked &&
                    c.includeInGlobalAudio,
              )
              .length,
          onTap: openGlobalMusic,
        ),
      ];
      return s.spacesView == 1
          ? [homeGrid(cards)]
          : [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const AppGap(12),
                cards[i],
              ],
            ];
    }
    return [
      spaceCard(videos: false),
      const AppGap(24),
      spaceCard(videos: true),
      const AppGap(24),
      audiobookShowcase(),
      const AppGap(24),
      musicShowcase(),
      const AppGap(24),
      readingSpaceCard(MediaSubtype.ebook),
      const AppGap(24),
      readingSpaceCard(MediaSubtype.comics),
    ];
  }

  Future<void> openGlobalMusic() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MusicPage(library: widget.library, playback: music, space: true),
      ),
    );
    await spacePreferences.load(widget.library.service.userPreferences);
    if (mounted) setState(() {});
  }

  Widget musicShowcase() => FutureBuilder<MusicOverview>(
    future: widget.library.musicCatalog.overview(
      const SpaceScope(MediaSubtype.music),
    ),
    builder: (context, snapshot) {
      final data = snapshot.data;
      final tracks = data?.tracks ?? [];
      final albums = data?.albums ?? [];
      final extras = data?.extras ?? <String, dynamic>{};
      final display = spacePreferences.music;
      final ordered = orderedMusicAlbums(
        albums,
        extras,
        data?.history ?? {},
        display.source,
      );
      final selected =
          SpaceController<MusicAlbum, String>(identity: (a) => a.key).showcase(
            display.source == 'favorites'
                ? ordered.where(
                    (a) => a.tracks.any(
                      (t) =>
                          widget.library.musicCatalog.flags(
                            extras,
                            t.id,
                          )['favorite'] ==
                          true,
                    ),
                  )
                : ordered,
            display.pins,
            pinned: display.source == 'pinned',
          );
      final count = widget.library.collections
          .where(
            (c) =>
                c.kind == MediaKind.music &&
                !c.locked &&
                c.includeInGlobalAudio,
          )
          .length;
      return MediaSpaceCard(
        title: 'Music',
        icon: AppIconRole.music,
        artwork: [for (final album in selected) MediaCover(cover: album.cover)],
        counts: [
          '${albums.length} ${albums.length == 1 ? 'album' : 'albums'}',
          '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}',
          '$count ${count == 1 ? 'collection' : 'collections'}',
        ],
        emptyHint: 'Include an unlocked Music collection to get started.',
        onOpen: count == 0 ? null : openGlobalMusic,
        showArtwork: display.artwork,
        showCounts: display.counts,
        squareArtwork: true,
      );
    },
  );

  Future<void> openGlobalAudiobooks() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AudiobookSpace(library: widget.library),
      ),
    );
    await spacePreferences.load(widget.library.service.userPreferences);
    if (mounted) setState(() {});
  }

  Widget audiobookShowcase() => FutureBuilder(
    future: widget.library.audiobookCatalog().books(),
    builder: (context, snapshot) {
      final eligible = widget.library.collections
          .where(
            (c) =>
                c.kind == MediaKind.audiobook &&
                !c.locked &&
                c.includeInGlobalAudio,
          )
          .toList();
      final items = (snapshot.data ?? [])
          .where((b) => eligible.any((c) => c.id == b.id.collectionId))
          .toList();
      final display = spacePreferences.audiobooks;
      return MediaSpaceCard(
        title: 'Audiobooks',
        icon: AppIconRole.reading,
        artwork: [
          for (final book in audiobookShowcaseTitles(items, display))
            AudiobookCover(cover: book.metadata.cover),
        ],
        counts: [
          '${items.length} ${items.length == 1 ? 'audiobook' : 'audiobooks'}',
          '${eligible.length} ${eligible.length == 1 ? 'collection' : 'collections'}',
        ],
        emptyHint: 'Include an unlocked Audiobooks collection to get started.',
        onOpen: eligible.isEmpty ? null : openGlobalAudiobooks,
        showArtwork: display.artwork,
        showCounts: display.counts,
        squareArtwork: true,
      );
    },
  );

  Widget homeGrid(List<Widget> cards) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final card in cards)
          SizedBox(
            width: constraints.maxWidth < 320
                ? constraints.maxWidth
                : (constraints.maxWidth - 12) / 2,
            child: card,
          ),
      ],
    ),
  );

  Future<void> editSpace(bool videos) async {
    await showSpaceSettings(
      context,
      spacePreferences,
      widget.library.service,
      videos,
      eligible: videos
          ? videoSpaceItems(widget.library)
          : groupedTitles(cinemaItems(widget.library)),
    );
    if (mounted) setState(() {});
  }

  Widget compactSpace(bool videos) {
    final sources = videos
        ? globalVideoCollections(widget.library)
        : cinemaCollections(widget.library);
    return compactSpaceCard(
      title: videos ? 'Videos' : 'Cinema',
      icon: videos ? AppIconRole.video : AppIconRole.movies,
      count: sources.length,
      onTap: sources.isEmpty
          ? null
          : videos
          ? openGlobalVideos
          : openGlobalCinema,
    );
  }

  Widget compactSpaceCard({
    required String title,
    required AppIconRole icon,
    required int count,
    required VoidCallback? onTap,
  }) {
    final label = '$count ${count == 1 ? 'collection' : 'collections'}';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        customBorder: interfaceShape(context, radius: 24),
        child: Padding(
          padding: AppSpacing.of(context).all(16),
          child: s.spacesView == 1
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 164),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(icon, color: s.accent),
                      const AppGap(20),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const AppGap(8),
                      Text(label),
                    ],
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Row(
                    children: [
                      AppIcon(icon),
                      const AppGap.horizontal(16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title),
                            const AppGap(8),
                            Text(
                              label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const AppGap.horizontal(8),
                      const AppIcon(AppIconRole.disclosure),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget spaceCard({required bool videos}) {
    final library = widget.library;
    final eligible = videos
        ? globalVideoCollections(library)
        : cinemaCollections(library);
    final items = videos ? videoSpaceItems(library) : cinemaItems(library);
    final movies = items
        .where((a) => a.mediaSubtype == VideoSubtype.movies)
        .length;
    final shows = buildSeries(items)
        .where((s) => !s.needsIdentification)
        .length;
    final prefs = spacePreferences.forSpace(videos);
    final artwork = <VideoAsset>[];
    final seen = <String>{};
    final pinnable = videos ? items : groupedTitles(items);
    final candidates = prefs.source == 'pinned'
        ? SpaceController<VideoAsset, String>(identity: showcaseKey)
              .showcase(pinnable, prefs.pins, pinned: true)
        : (items.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt)));
    for (final a in candidates) {
      if (prefs.source == 'favorites' && !a.favorite) continue;
      if (prefs.source == 'progress' && (a.positionMs <= 0 || a.watched)) {
        continue;
      }
      final key =
          a.localPoster ??
          a.poster ??
          a.localBackdrop ??
          a.backdrop ??
          a.thumbnail;
      if (prefs.source == 'pinned' || (key != null && seen.add(key))) {
        artwork.add(a);
      }
      if (artwork.length == 3) break;
    }
    return MediaSpaceCard(
      title: videos ? 'Videos' : 'Cinema',
      icon: videos ? AppIconRole.videoLibrary : AppIconRole.movies,
      artwork: [
        for (final item in artwork)
          VideoArtwork(asset: item, posterFirst: !videos),
      ],
      counts: [
        if (videos || movies > 0)
          videos
              ? '${items.length} ${items.length == 1 ? 'video' : 'videos'}'
              : '$movies ${movies == 1 ? 'movie' : 'movies'}',
        if (!videos && shows > 0) '$shows series',
        '${eligible.length} ${eligible.length == 1 ? 'collection' : 'collections'}',
      ],
      emptyHint: videos
          ? 'Include an unlocked Videos collection to get started.'
          : 'Include an unlocked Movies & TV collection to get started.',
      onOpen: eligible.isEmpty
          ? null
          : videos
          ? openGlobalVideos
          : openGlobalCinema,
      showArtwork: prefs.artwork,
      showCounts: prefs.counts,
    );
  }

  Widget readingSpaceCard(MediaSubtype subtype, {bool compact = false}) {
    final scope = SpaceScope(subtype);
    final titles = reading.eligible(scope);
    final display = subtype == MediaSubtype.ebook
        ? spacePreferences.ebook
        : spacePreferences.comics;
    final label = subtype == MediaSubtype.ebook ? 'Ebooks' : 'Comics';
    final selected = display.source == 'pinned'
        ? [
            for (final pin in display.pins)
              ...titles.where((t) => readingKey(t.catalog.id) == pin),
          ].take(3).toList()
        : (display.source == 'favorites'
                  ? titles.where(
                      (t) =>
                          (reading.bundle!.management.entity(t.catalog.id).tags
                                  as List)
                              .any(
                                (v) => v.toString().toLowerCase() == 'favorite',
                              ),
                    )
                  : display.source == 'progress'
                  ? titles.where(
                      (t) => reading.started(t) && !reading.finished(t),
                    )
                  : titles.reversed)
              .take(3)
              .toList();
    Future<void> open() async {
      await openReadingSpace(context, reading, scope);
      await spacePreferences.load(widget.library.service.userPreferences);
      if (mounted) setState(() {});
    }

    if (compact) {
      return compactSpaceCard(
        title: label,
        icon: AppIconRole.reading,
        count: titles.length,
        onTap: open,
      );
    }
    return MediaSpaceCard(
      title: label,
      icon: AppIconRole.reading,
      artwork: [
        for (final t in selected)
          ReadingCover(
            library: reading.library,
            reference: reading.cover(t),
            crop:
                reading.bundle!.management.entity(t.catalog.id).coverMode ==
                'crop',
          ),
      ],
      counts: ['${titles.length} titles'],
      emptyHint: 'Add a reading collection to get started.',
      onOpen: open,
      showArtwork: display.artwork,
      showCounts: display.counts,
    );
  }

  List<Widget> libraryContent() {
    final library = widget.library;
    if (!library.ready) {
      return [const Center(child: CircularProgressIndicator())];
    }
    if (library.error != null) {
      return [
        Text(library.error!),
        TextButton(onPressed: library.load, child: const Text('Retry')),
      ];
    }
    final collections =
        <
          ({
            String id,
            String name,
            String label,
            bool locked,
            int count,
            int roots,
            Widget icon,
            VoidCallback open,
          })
        >[
          for (final c in library.collections)
            (
              id: c.id,
              name: c.name,
              label: c.mediaLabel,
              locked: c.locked,
              count: c.locked ? 0 : library.collectionItemCount(c),
              roots: c.roots.length,
              icon: c.isAudio
                  ? AppIcon(AppIconRole.reading, color: s.accent)
                  : s.pixel
                  ? AppIcon(AppIconRole.video, color: s.accent)
                  : AppIcon(
                      c.subtype == VideoSubtype.tv
                          ? AppIconRole.television
                          : c.subtype == VideoSubtype.movies
                          ? AppIconRole.movies
                          : AppIconRole.videoLibrary,
                      color: s.accent,
                    ),
              open: () => openCollection(c),
            ),
          for (final c in reading.bundle?.catalog.collections ?? [])
            (
              id: c.id,
              name: c.name,
              label: c.subtype == MediaSubtype.ebook ? 'Ebooks' : 'Comics',
              locked: c.access.locked,
              count: c.access.locked
                  ? 0
                  : reading.bundle!.catalog.titles
                        .where((t) => t.catalog.id.collectionId == c.id)
                        .length,
              roots: c.roots.length,
              icon: AppIcon(AppIconRole.reading, color: s.accent),
              open: () =>
                  run(() => openReadingCollection(context, reading, c.id)),
            ),
        ];
    if (collections.isEmpty && reading.error == null && !reading.ready) {
      return [const Text('Loading reading collections…')];
    }
    final cards = [
      for (final c in collections)
        Card(
          key: ValueKey('library-collection:${c.id}'),
          child: s.libraryView == 1
              ? InkWell(
                  borderRadius: interfaceRadius(context, 24),
                  onTap: c.open,
                  child: Padding(
                    padding: AppSpacing.of(context).all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        c.locked
                            ? AppIcon(AppIconRole.lock, color: s.accent)
                            : c.icon,
                        const AppGap(20),
                        Text(
                          c.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const AppGap(6),
                        Text(c.locked ? 'Locked' : '${c.count} items'),
                        Text(
                          c.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              : ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: s.libraryView == 2 ? 0 : 12,
                  ),
                  leading: c.icon,
                  title: Text(c.name),
                  subtitle: Text(
                    c.locked
                        ? '${c.label} · Locked'
                        : '${c.label} · ${c.count} ${c.count == 1 ? 'item' : 'items'} · ${c.roots} ${c.roots == 1 ? 'folder' : 'folders'}',
                  ),
                  trailing: AppIcon(
                    c.locked ? AppIconRole.lock : AppIconRole.disclosure,
                  ),
                  onTap: c.open,
                ),
        ),
    ];
    return [
      if (cards.isEmpty)
        empty(
          AppIconRole.library,
          'No collections',
          'Use + to create your first collection.',
        )
      else if (s.libraryView == 1)
        homeGrid(cards)
      else
        for (final card in cards)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
      if (reading.error != null)
        TextButton(
          onPressed: reading.load,
          child: const Text('Could not load reading collections · Retry'),
        ),
    ];
  }

  Widget empty(AppIconRole icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 90),
    child: Column(
      children: [
        AppIcon(
          icon,
          size: 40,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const AppGap(20),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const AppGap(8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
  Widget panel(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  List<Widget> settingsContent(BuildContext context) {
    if (settingsPage == 5) {
      return [
        LibraryBackupSettings(library: widget.library, platform: s.platform),
      ];
    }
    if (settingsPage == 4) {
      return [
        AppSection(
          title: 'Metadata providers',
          description: 'Add metadata and artwork providers through plugins.',
          children: [
            Padding(
              padding: AppSpacing.of(context).symmetric(horizontal: 16),
              child: Text(
                'Choose providers and review their access in Plugins & themes. Each plugin manages its own settings and approved connections.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const AppGap(16),
        if (widget.plugins != null)
          FilledButton(
            onPressed: () => openPackages(),
            child: const Text('Manage provider plugins'),
          ),
      ];
    }
    if (settingsPage == 0) {
      return [
        if (!s.supported)
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text(
              'Device controls and saved preferences are currently available on Android.',
            ),
          ),
        panel([
          ListTile(
            leading: const AppIcon(AppIconRole.play),
            title: const Text('Players & readers'),
            subtitle: const Text('Video, music, audiobooks, ebooks and comics'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => PlayersReadersPage(
                  preferences: widget.library.playerPreferences,
                  reading: reading.library,
                ),
              ),
            ),
          ),
          const Divider(height: 24),
          if (widget.plugins != null) ...[
            ListTile(
              leading: const AppIcon(AppIconRole.spaces),
              title: const Text('Plugins & themes'),
              subtitle: const Text('Extensions, themes and package access'),
              trailing: const AppIcon(AppIconRole.disclosure),
              onTap: () => openPackages(),
            ),
            const Divider(height: 24),
          ],
          if (widget.plugins != null)
            ListenableBuilder(
              listenable: widget.plugins!,
              builder: (context, _) => Column(
                children: [
                  for (final entry in widget.plugins!.registry.family(
                    'settings.section',
                  ))
                    Column(
                      children: [
                        ListTile(
                          leading: const AppIcon(AppIconRole.settings),
                          title: Text(entry.title),
                          subtitle: Text(entry.plugin.name),
                          trailing: const AppIcon(AppIconRole.disclosure),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PluginSettingsPage(
                                manager: widget.plugins!,
                                plugin: entry.plugin,
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                      ],
                    ),
                  for (final entry in widget.plugins!.registry.family(
                    'ui.destination',
                  ))
                    Column(
                      children: [
                        ListTile(
                          leading: const AppIcon(AppIconRole.spaces),
                          title: Text(entry.title),
                          subtitle: Text(entry.plugin.name),
                          trailing: const AppIcon(AppIconRole.disclosure),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PluginContributionPage(
                                manager: widget.plugins!,
                                contribution: entry,
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                      ],
                    ),
                ],
              ),
            ),
          ListTile(
            leading: const AppIcon(AppIconRole.backup),
            title: const Text('Backup & restore'),
            subtitle: const Text('Collections, metadata and history'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => setState(() => settingsPage = 5),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const AppIcon(AppIconRole.palette),
            title: const Text('Appearance'),
            subtitle: const Text('Colors, mode, layout and motion'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => setState(() => settingsPage = 1),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const AppIcon(AppIconRole.security),
            title: const Text('Security'),
            subtitle: const Text('App lock, biometrics and privacy'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => setState(() => settingsPage = 2),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const AppIcon(AppIconRole.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Permissions, categories and delivery'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => setState(() => settingsPage = 3),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const AppIcon(AppIconRole.metadata),
            title: const Text('Metadata'),
            subtitle: const Text('Installed metadata and artwork providers'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => setState(() => settingsPage = 4),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const AppIcon(AppIconRole.settings),
            title: const Text('Build info'),
            subtitle: const Text('App version and build details'),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Build info'),
                content: FutureBuilder<Map<String, String>>(
                  future: s.loadBuildInfo(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                        'Build information is unavailable on this device.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 48,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final info = snapshot.data!;
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in <String, String>{
                            'App': 'Multiplexr',
                            'Version': info['version'] ?? 'Unavailable',
                            'Build number': info['build'] ?? 'Unavailable',
                            'Package': info['package'] ?? 'Unavailable',
                            'Build mode': kReleaseMode
                                ? 'Release'
                                : kProfileMode
                                ? 'Profile'
                                : 'Debug',
                          }.entries) ...[
                            Text(
                              entry.key,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const AppGap(4),
                            SelectableText(entry.value),
                            const AppGap(16),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ];
    }
    return [
      ShellSettingsPanel(
        settings: s,
        section: ShellSettingsSection.values[settingsPage - 1],
        categories: const [
          ShellNotificationCategory(
            'completed',
            'Indexing completed',
            'When a collection finishes scanning.',
          ),
          ShellNotificationCategory(
            'errors',
            'Source errors',
            'Folder access and indexing failures.',
          ),
          ShellNotificationCategory(
            'activity',
            'Background activity',
            'Progress from background work.',
          ),
        ],
      ),
    ];
  }
}
