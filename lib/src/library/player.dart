import '../experience/plugins/plugin_session_actions.dart';
import '../features/playback/application/video_session.dart';
import '../features/playback/application/video_playback_host.dart';
import '../features/settings/application/player_preferences.dart';
import '../media/source_recovery.dart';

import 'package:app_shell/app_shell.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'library_models.dart';
import 'library_controller.dart';
import '../features/playback/application/video_engine.dart';
import 'watch_details.dart';
import 'series.dart';
import 'series_view.dart';
import 'video_scope.dart';

class MultiplexrPlayer extends StatefulWidget {
  const MultiplexrPlayer({
    super.key,
    required this.asset,
    required this.host,
    this.landscapeOnly = false,
    this.watchPage = false,
    this.related = const [],
    this.library,
    this.globalVideos = false,
    this.startFullscreen = false,
    this.openSource,
  });
  final VideoAsset asset;
  final VideoPlaybackHost host;
  final bool landscapeOnly;
  final bool watchPage;
  final List<VideoAsset> related;
  final LibraryController? library;
  final bool globalVideos, startFullscreen;
  final Future<void> Function(VideoAsset)? openSource;
  @override
  State<MultiplexrPlayer> createState() => _MultiplexrPlayerState();
}

class _MultiplexrPlayerState extends State<MultiplexrPlayer>
    with WidgetsBindingObserver {
  late final player = widget.host.createEngine();
  static const sessionPolicy = SessionPolicy();
  late final session = widget.host.session(
    widget.asset,
    authorized: () =>
        widget.library?.canAccessCollection(widget.asset.collectionId) ?? true,
  );
  final controls = GlobalKey<MultiplexrControlsState>();
  final videoFrame = GlobalKey();
  PlayerOptions playerOptions = PlayerOptions.decode(PlayerKind.video, null);
  bool get completionPending => session.completionPending;
  set completionPending(bool value) => session.completionPending = value;
  bool leaving = false;
  bool _invalidated = false;
  bool replacingWatch = false;
  late bool fullscreen = widget.landscapeOnly || widget.startFullscreen;
  @override
  void initState() {
    super.initState();
    session.bindDrain(() async {
      if (mounted) setState(() => _invalidated = true);
      await player.pause();
      await player.setBackground(false);
    });
    WidgetsBinding.instance.addObserver(this);
    player.addListener(changed);
    widget.library?.addListener(libraryChanged);
    widget.host.window.addListener(windowChanged);
    configureScreen();
    unawaited(loadPlayerOptions());
  }

  Future<void> loadPlayerOptions() async {
    final preferences = widget.host.preferences;
    final value = await preferences.loadForPlayback(PlayerKind.video);
    if (mounted) setState(() => playerOptions = value);
  }

  void windowChanged() {
    if (!mounted) return;
    player
        .controlsVisible(!widget.host.window.active)
        .catchError((Object _) {});
    setState(() {});
    if (!widget.host.window.active && !widget.host.window.backgrounded) {
      configureScreen();
      if (completionPending) finished();
    }
  }

  Future<void> configureScreen() async {
    await SystemChrome.setPreferredOrientations(
      fullscreen
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : widget.watchPage
          ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : DeviceOrientation.values,
    );
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void libraryChanged() {
    if (widget.library?.canAccessCollection(widget.asset.collectionId) ==
        false) {
      player.pause().catchError((Object _) {});
    }
    if (mounted) {
      setState(() {});
      if (completionPending) finished();
    }
  }

  void changed() {
    if (leaving) return;
    final update = session.observe(
      positionMs: player.state.position.inMilliseconds,
      durationMs: player.state.duration.inMilliseconds,
      completed: player.state.completed,
    );
    if (update.completion) finished();
    if (update.checkpoint) persist().catchError((Object _) {});
  }

  List<VideoAsset> get availableRelated => widget.library == null
      ? widget.related
      : widget.watchPage
      ? videoSpaceItems(
          widget.library!,
          collectionId: widget.globalVideos ? null : widget.asset.collectionId,
        )
      : widget.library!.items(widget.asset.collectionId);
  List<VideoAsset> get scopedQueue => widget.library == null
      ? []
      : videoSpaceQueue(
          widget.library!,
          collectionId: widget.globalVideos ? null : widget.asset.collectionId,
        );
  VideoAsset? get queuedNext => widget.watchPage
      ? scopedQueue
            .where(
              (a) =>
                  a.id != widget.asset.id ||
                  a.collectionId != widget.asset.collectionId,
            )
            .firstOrNull
      : null;
  EpisodeRecord? get episodeNext =>
      !widget.watchPage && widget.asset.mediaSubtype == VideoSubtype.tv
      ? nextEpisodeRecord(widget.asset, availableRelated)
      : null;
  Future<void> finished() async {
    try {
      final next = await session.finish(
        checkpoint: persist,
        reload: () async => widget.library?.load(),
        active: () => mounted && !leaving,
        foreground: () =>
            WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        pictureInPicture: () => widget.host.window.active,
        autoplayNext: () =>
            widget.library?.collections
                .where((c) => c.id == widget.asset.collectionId)
                .firstOrNull
                ?.autoplayNext ==
            true,
        queued: () => queuedNext,
        episodeVersions: () => episodeNext?.versions ?? [],
      );
      if (next != null && mounted && !leaving) await watchNext(next);
    } catch (_) {
      // Replay and next actions remain available after a failed checkpoint.
    }
  }

  Future<void> playNextAvailable() async {
    if (queuedNext != null) {
      await watchNext(queuedNext!);
      return;
    }
    final episode = episodeNext;
    if (episode != null) {
      final choice = await chooseVersion(context, episode);
      if (choice != null) await watchNext(choice);
    }
  }

  Future<void> persist() => session.save(
    positionMs: player.state.position.inMilliseconds,
    durationMs: player.state.duration.inMilliseconds,
    completed: player.state.completed,
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (sessionPolicy.shouldPause(
        authorized:
            widget.library?.canAccessCollection(widget.asset.collectionId) ??
            true,
        foreground: false,
        backgroundAllowed: player.state.background,
        pictureInPicture:
            widget.host.window.active ||
            (player.state.autoPip && player.state.playing),
      )) {
        player.pause().catchError((Object _) {});
      }
      persist().catchError((Object _) {});
    } else if (!widget.host.window.active) {
      configureScreen();
      if (completionPending) finished();
    }
  }

  Future<void> external() async {
    try {
      await session.handoff(
        pause: player.pause,
        checkpoint: persist,
        disableBackground: () => player.setBackground(false),
        launch: () => widget.host.external(widget.asset),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open an external player. Install one and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> toggleFullscreen() async {
    if (widget.landscapeOnly) return;
    setState(() => fullscreen = !fullscreen);
    await configureScreen();
  }

  Future<void> leave({bool fromBack = false}) async {
    if (controls.currentState?.unlockIfLocked() == true) return;
    if (fromBack && fullscreen && !widget.landscapeOnly) {
      await toggleFullscreen();
      return;
    }
    if (leaving) return;
    leaving = true;
    try {
      await player.pause();
      await persist();
      await player.setBackground(false);
    } catch (_) {}
    if (widget.watchPage) await widget.library?.load();
    if (mounted) Navigator.pop(context);
  }

  Future<void> openSourceCollection() async {
    await player.pause();
    await persist();
    await widget.openSource?.call(widget.asset);
    if (!mounted) return;
    if (widget.globalVideos &&
        !availableRelated.any(
          (a) =>
              a.id == widget.asset.id &&
              a.collectionId == widget.asset.collectionId,
        )) {
      await leave();
    } else {
      await configureScreen();
    }
  }

  Future<void> watchNext(VideoAsset asset) async {
    if (leaving) return;
    if (widget.watchPage &&
        !availableRelated.any(
          (a) => a.id == asset.id && a.collectionId == asset.collectionId,
        )) {
      return;
    }
    if (!asset.available) {
      if (widget.library != null) {
        showUnavailableSource(context, widget.library!, asset.collectionId);
      }
      return;
    }
    leaving = true;
    try {
      if (asset.watched) await widget.library?.watch(asset, 'restart');
      if (widget.library?.queuedVideos.any(
            (a) => a.id == asset.id && a.collectionId == asset.collectionId,
          ) ==
          true) {
        await widget.library!.removeQueued(asset);
      }
      await player.pause();
      try {
        await persist();
      } catch (_) {}
      await widget.library?.load();
      if (!mounted) return;
      replacingWatch = true;
      final related = availableRelated;
      final latest = related
          .where(
            (a) => a.id == asset.id && a.collectionId == asset.collectionId,
          )
          .firstOrNull;
      if (latest == null || !latest.available) {
        leaving = false;
        return;
      }
      Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplexrPlayer(
            asset: latest,
            host: widget.host,
            watchPage: widget.watchPage,
            landscapeOnly: widget.landscapeOnly,
            related: related,
            library: widget.library,
            globalVideos: widget.globalVideos,
            startFullscreen: fullscreen,
            openSource: widget.openSource,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        leaving = false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start the next video. Try again.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    session.dispose();
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(changed);
    widget.host.window.removeListener(windowChanged);
    widget.library?.removeListener(libraryChanged);
    player.dispose();
    if (!replacingWatch) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(
        widget.watchPage
            ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
            : DeviceOrientation.values,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _invalidated
      ? Scaffold(
          appBar: AppBar(title: const Text('Playback closed')),
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Library changed · Back'),
            ),
          ),
        )
      : PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) leave(fromBack: true);
          },
          child: Scaffold(
            backgroundColor: widget.watchPage && !fullscreen
                ? Theme.of(context).scaffoldBackgroundColor
                : Colors.black,
            body: Padding(
              padding: EdgeInsets.only(
                top:
                    widget.watchPage &&
                        !fullscreen &&
                        !widget.host.window.active
                    ? MediaQuery.paddingOf(context).top
                    : 0,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pip = widget.host.window.active;
                  final embedded = widget.watchPage && !fullscreen && !pip;
                  final height = embedded
                      ? (constraints.maxWidth * 9 / 16)
                            .clamp(0.0, constraints.maxHeight * .6)
                            .toDouble()
                      : constraints.maxHeight;
                  return Column(
                    children: [
                      SizedBox(
                        key: videoFrame,
                        width: double.infinity,
                        height: height,
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: embedded,
                          removeBottom: embedded,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AndroidView(
                                key: const ValueKey('video-surface'),
                                viewType: 'multiplexr/video',
                                creationParams: {
                                  'uri': widget.asset.uri,
                                  'positionMs': widget.asset.positionMs,
                                  'assetId': widget.asset.id,
                                  'collectionId': widget.asset.collectionId,
                                  'title': widget.asset.title,
                                },
                                creationParamsCodec:
                                    const StandardMessageCodec(),
                                onPlatformViewCreated: (id) {
                                  widget.host
                                      .started(widget.asset)
                                      .catchError((Object _) {});
                                  player.attach(id);
                                },
                              ),
                              if (!pip)
                                MultiplexrControls(
                                  key: controls,
                                  player: player,
                                  title: widget.asset.title,
                                  backSeconds: playerOptions.backSeconds,
                                  forwardSeconds: playerOptions.forwardSeconds,
                                  fullscreen: toggleFullscreen,
                                  external: external,
                                  back: () => leave(fromBack: widget.watchPage),
                                  isFullscreen: fullscreen,
                                  landscapeOnly: widget.landscapeOnly,
                                  compact: embedded,
                                  floatingAvailable: true,
                                  next:
                                      queuedNext != null || episodeNext != null
                                      ? playNextAvailable
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (embedded)
                        Expanded(
                          child: WatchDetails(
                            asset:
                                widget.library
                                    ?.items(widget.asset.collectionId)
                                    .where((a) => a.id == widget.asset.id)
                                    .firstOrNull ??
                                widget.asset,
                            library: widget.library,
                            onWatchAction: widget.library == null
                                ? null
                                : (action) async {
                                    await widget.library!.watch(
                                      widget.asset,
                                      action,
                                    );
                                    if (action == 'restart' ||
                                        action == 'unwatched') {
                                      await player.seek(Duration.zero);
                                    }
                                    if (action == 'restart' &&
                                        !player.state.playing) {
                                      await player.playOrPause();
                                    }
                                  },
                            related: availableRelated,
                            queueItems: () => scopedQueue,
                            openSource: widget.openSource == null
                                ? null
                                : openSourceCollection,
                            onSelect: watchNext,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
}

String videoTime(Duration value) {
  final hours = value.inHours;
  return '${hours > 0 ? '$hours:' : ''}${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class MultiplexrControls extends StatefulWidget {
  const MultiplexrControls({
    super.key,
    required this.player,
    required this.fullscreen,
    required this.external,
    this.back,
    this.title = '',
    this.backSeconds = 10,
    this.forwardSeconds = 10,
    this.isFullscreen = false,
    this.landscapeOnly = false,
    this.compact = false,
    this.floatingAvailable = false,
    this.next,
  });
  final VideoEngine player;
  final Future<void> Function() fullscreen, external;
  final Future<void> Function()? next;
  final VoidCallback? back;
  final bool floatingAvailable;
  final String title;
  final int backSeconds, forwardSeconds;
  final bool isFullscreen, landscapeOnly, compact;
  @override
  State<MultiplexrControls> createState() => MultiplexrControlsState();
}

class MultiplexrControlsState extends State<MultiplexrControls> {
  VideoEngine get player => widget.player;
  Timer? hideTimer, feedbackTimer;
  bool visible = true, locked = false;
  int openSheets = 0;
  bool get sheetOpen => openSheets > 0;
  double? scrub;
  double subtitleScale = 1;
  bool subtitleBackground = false;
  String? feedback;
  bool wasPlaying = false;
  @override
  void initState() {
    super.initState();
    player.addListener(changed);
    wasPlaying = player.state.playing;
    armTimer();
  }

  void changed() {
    if (!mounted) return;
    if ((!player.state.playing ||
            player.state.completed ||
            player.state.error != null) &&
        !locked &&
        !visible) {
      visible = true;
      player.controlsVisible(true).catchError((Object _) {});
    }
    if (player.state.playing && !wasPlaying) armTimer();
    wasPlaying = player.state.playing;
    setState(() {});
  }

  void armTimer() {
    hideTimer?.cancel();
    if (!WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .accessibleNavigation &&
        !locked &&
        !sheetOpen &&
        scrub == null &&
        player.state.playing) {
      hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted &&
            !WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .accessibleNavigation) {
          setVisible(false);
        }
      });
    }
  }

  void setVisible(bool value) {
    if (!mounted || locked) return;
    setState(() => visible = value);
    player.controlsVisible(value).catchError((Object _) {});
    if (value) armTimer();
  }

  bool unlockIfLocked() {
    if (!locked) return false;
    setState(() {
      locked = false;
      visible = true;
    });
    player.controlsVisible(true).catchError((Object _) {});
    armTimer();
    return true;
  }

  void lock() {
    hideTimer?.cancel();
    setState(() {
      locked = true;
      visible = false;
    });
    player.controlsVisible(false).catchError((Object _) {});
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    feedbackTimer?.cancel();
    player.removeListener(changed);
    super.dispose();
  }

  Future<void> action(Future<void> Function() operation) async {
    armTimer();
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PlatformException
                  ? error.message ?? 'This playback option is unavailable.'
                  : 'This playback option is unavailable for this video.',
            ),
          ),
        );
      }
    }
  }

  Future<void> seekBy(int seconds) async {
    if (locked || player.state.duration <= Duration.zero) return;
    await action(
      () => player.seek(
        Duration(
          milliseconds: (player.state.position.inMilliseconds + seconds * 1000)
              .clamp(0, player.state.duration.inMilliseconds),
        ),
      ),
    );
    if (!mounted) return;
    setState(
      () => feedback = seconds < 0
          ? '−${seconds.abs()} seconds'
          : '+$seconds seconds',
    );
    feedbackTimer?.cancel();
    feedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => feedback = null);
    });
  }

  Future<void> sheet(
    String title,
    Widget Function(BuildContext, StateSetter) contents,
  ) async {
    hideTimer?.cancel();
    openSheets++;
    final colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface.withValues(alpha: .94),
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .75,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const AppGap(16),
                  contents(context, update),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    openSheets--;
    if (mounted) {
      setState(() {});
      armTimer();
    }
  }

  Future<void> speed() => sheet(
    'Playback speed',
    (context, update) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final rate in [.25, .5, .75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0])
          ChoiceChip(
            label: Text(rate == 1 ? 'Normal' : '$rate×'),
            selected: player.state.rate == rate,
            onSelected: (_) async {
              await action(() => player.setRate(rate));
              if (context.mounted) update(() {});
            },
          ),
      ],
    ),
  );
  Future<void> tracks(bool audio) {
    subtitleScale = player.state.subtitleScale;
    subtitleBackground = player.state.subtitleBackground;
    return sheet(audio ? 'Audio tracks' : 'Subtitles', (context, update) {
      final values = audio
          ? player.state.tracks.audio
          : player.state.tracks.subtitle;
      final selected = audio
          ? player.state.track.audio.id
          : player.state.track.subtitle.id;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (values.where((t) => t.id != 'auto' && t.id != 'no').isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No embedded tracks found in this video.'),
            ),
          for (final track in values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                track.id == 'auto'
                    ? 'Automatic'
                    : track.id == 'no'
                    ? (audio ? 'Mute audio track' : 'Off')
                    : [track.title, track.language]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · ')
                          .isNotEmpty
                    ? [track.title, track.language]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · ')
                    : 'Track ${track.id}',
              ),
              trailing: selected == track.id
                  ? const AppIcon(AppIconRole.confirm)
                  : null,
              onTap: () async {
                await action(
                  () => audio
                      ? player.setAudioTrack(track)
                      : player.setSubtitleTrack(track),
                );
                if (context.mounted) update(() {});
              },
            ),
          if (!audio) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const AppIcon(AppIconRole.openFile),
              title: Text(
                player.state.externalSubtitle == null
                    ? 'Add subtitle file'
                    : 'Replace subtitle file',
              ),
              subtitle: Text(
                player.state.externalSubtitle ??
                    'SRT, VTT, ASS or SSA · up to 5 MB',
              ),
              onTap: () async {
                await action(player.addSubtitle);
                if (context.mounted) update(() {});
              },
            ),
            if (player.state.externalSubtitle != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const AppIcon(AppIconRole.close),
                title: const Text('Remove external subtitles'),
                onTap: () async {
                  await action(player.removeSubtitle);
                  if (context.mounted) update(() {});
                },
              ),
            const Divider(),
            const AppGap(8),
            const Text('Subtitle size'),
            Slider(
              value: subtitleScale,
              min: .6,
              max: 2,
              divisions: 7,
              label: '${(subtitleScale * 100).round()}%',
              onChanged: (value) {
                update(() => subtitleScale = value);
              },
              onChangeEnd: (_) => action(
                () =>
                    player.setSubtitleStyle(subtitleScale, subtitleBackground),
              ),
            ),
            InterfaceSwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Subtitle background'),
              subtitle: const Text(
                'Off uses transparent captions with an outline',
              ),
              value: subtitleBackground,
              onChanged: (value) async {
                update(() => subtitleBackground = value);
                await action(
                  () => player.setSubtitleStyle(
                    subtitleScale,
                    subtitleBackground,
                  ),
                );
              },
            ),
          ],
        ],
      );
    });
  }

  Future<void> more() => sheet(
    'Playback options',
    (context, update) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PluginSessionActions(),
        if (widget.compact) ...[
          ListTile(
            leading: const AppIcon(AppIconRole.speed),
            title: const Text('Playback speed'),
            onTap: () {
              Navigator.pop(context);
              speed();
            },
          ),
          ListTile(
            leading: const AppIcon(AppIconRole.music),
            title: const Text('Audio tracks'),
            onTap: () {
              Navigator.pop(context);
              tracks(true);
            },
          ),
          ListTile(
            leading: const AppIcon(AppIconRole.subtitles),
            title: const Text('Subtitles'),
            onTap: () {
              Navigator.pop(context);
              tracks(false);
            },
          ),
          ListTile(
            leading: const AppIcon(AppIconRole.lock),
            title: const Text('Touch lock'),
            onTap: () {
              Navigator.pop(context);
              lock();
            },
          ),
        ],
        if (widget.floatingAvailable && !player.state.privateCollection)
          InterfaceSwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Floating window'),
            subtitle: const Text(
              'Automatically float playing video when you leave the app',
            ),
            value: player.state.autoPip,
            onChanged: (value) async {
              await action(() => player.setAutoPip(value));
              if (context.mounted) update(() {});
            },
          ),
        InterfaceSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Background playback'),
          subtitle: Text(
            player.state.privateCollection
                ? 'Disabled for locked collections'
                : 'Keep audio playing when you leave the app',
          ),
          value: player.state.background,
          onChanged: player.state.privateCollection
              ? null
              : (value) async {
                  await action(() => player.setBackground(value));
                  if (context.mounted) update(() {});
                },
        ),
        InterfaceSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Mute'),
          value: player.state.volume == 0,
          onChanged: (value) async {
            await action(() => player.setVolume(value ? 0 : 1));
            if (context.mounted) update(() {});
          },
        ),
        InterfaceSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Repeat video'),
          value: player.state.repeat,
          onChanged: (value) async {
            await action(() => player.setRepeat(value));
            if (context.mounted) update(() {});
          },
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Picture fit'),
        ),
        Wrap(
          spacing: 10,
          children: [
            for (final entry in {
              'fit': 'Fit',
              'fill': 'Fill / crop',
              'stretch': 'Stretch',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: player.state.fit == entry.key,
                onSelected: (_) async {
                  await action(() => player.setFit(entry.key));
                  if (context.mounted) update(() {});
                },
              ),
          ],
        ),
        const AppGap(12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const AppIcon(AppIconRole.restore),
          title: const Text('Reset playback preferences'),
          subtitle: const Text(
            'Speed, picture fit, caption style and track languages',
          ),
          onTap: () async {
            await action(player.resetPreferences);
            if (context.mounted) update(() {});
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const AppIcon(AppIconRole.externalLink),
          title: const Text('Play in external player'),
          onTap: () {
            Navigator.pop(context);
            action(widget.external);
          },
        ),
      ],
    ),
  );
  Widget button(
    String label,
    AppIconRole icon,
    VoidCallback callback, {
    double size = 24,
  }) => IconButton(
    tooltip: label,
    constraints: widget.compact
        ? const BoxConstraints.tightFor(width: 40, height: 40)
        : null,
    padding: widget.compact ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
    onPressed: callback,
    icon: AppIcon(
      icon,
      color: Colors.white,
      size: widget.compact ? (size > 34 ? 34 : 22) : size,
    ),
  );

  Widget toolbar() {
    final state = player.state;
    final items = <Widget>[
      if (!widget.compact)
        TextButton.icon(
          onPressed: speed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(56, 40),
          ),
          icon: AppIcon(
            AppIconRole.speed,
            color: Colors.white,
            size: widget.compact ? 18 : 20,
          ),
          label: Text(
            '${state.rate}×',
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.compact ? 12 : 14,
            ),
          ),
        ),
      if (widget.next != null)
        button('Play next', AppIconRole.next, () => action(widget.next!)),
      if (!widget.compact)
        button('Audio tracks', AppIconRole.music, () => tracks(true)),
      if (!widget.compact)
        button('Subtitles', AppIconRole.subtitles, () => tracks(false)),
      if (!widget.compact)
        button(
          state.volume == 0 ? 'Unmute' : 'Mute',
          state.volume == 0 ? AppIconRole.mute : AppIconRole.volume,
          () => action(() => player.setVolume(state.volume == 0 ? 1 : 0)),
        ),
      if (!widget.landscapeOnly)
        button(
          widget.isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
          widget.isFullscreen
              ? AppIconRole.fullscreenExit
              : AppIconRole.fullscreen,
          () => action(widget.fullscreen),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: widget.compact
          ? SizedBox(
              height: 48,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: items,
                    ),
                  ),
                ),
              ),
            )
          : Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: items,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = player.state;
    final accent = Theme.of(context).brightness == Brightness.light
        ? Color.lerp(Theme.of(context).colorScheme.primary, Colors.white, .65)!
        : Theme.of(context).colorScheme.primary;
    final duration = state.duration.inMilliseconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    final position = (scrub ?? state.position.inMilliseconds.toDouble())
        .clamp(0, duration)
        .toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: locked ? null : () => setVisible(!visible),
          onDoubleTapDown: locked
              ? null
              : (details) {
                  if (details.localPosition.dx <
                      MediaQuery.sizeOf(context).width / 2) {
                    seekBy(-widget.backSeconds);
                  } else {
                    seekBy(widget.forwardSeconds);
                  }
                },
          onDoubleTap: locked ? null : () {},
          child: const SizedBox.expand(),
        ),
        if (state.buffering && !locked)
          const IgnorePointer(
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        if (feedback != null && !locked)
          IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context)
                          .extension<ThemeTokens>()
                          ?.semanticColor(
                            'playerOverlay',
                            Theme.of(context).brightness,
                          )
                          ?.withValues(alpha: .8) ??
                      Colors.black54,
                  borderRadius: interfaceRadius(context, 24),
                ),
                child: Text(
                  feedback!,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        if (locked)
          SafeArea(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: AppSpacing.of(context).all(20),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: unlockIfLocked,
                  icon: const AppIcon(AppIconRole.unlock),
                  label: const Text('Unlock controls'),
                ),
              ),
            ),
          ),
        if (!locked && visible) ...[
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xB3000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xCC000000),
                  ],
                  stops: [0, .3, .5, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    if (widget.back != null)
                      button('Back', AppIconRole.back, widget.back!),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (!widget.compact)
                      button('Touch lock', AppIconRole.lock, lock),
                    button('Playback options', AppIconRole.menu, more),
                  ],
                ),
                Expanded(
                  child: state.error != null
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  state.error!,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: () => action(player.retry),
                                      child: const Text('Retry'),
                                    ),
                                    TextButton(
                                      onPressed: () => action(widget.external),
                                      child: const Text('External player'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              button(
                                'Back ${widget.backSeconds} seconds',
                                widget.backSeconds == 10
                                    ? AppIconRole.seekBack
                                    : AppIconRole.replay,
                                () => seekBy(-widget.backSeconds),
                                size: 34,
                              ),
                              const AppGap.horizontal(28),
                              DecoratedBox(
                                decoration: ShapeDecoration(
                                  color: Colors.black38,
                                  shape: isPixel(context)
                                      ? const PixelBorder()
                                      : const CircleBorder(),
                                ),
                                child: button(
                                  state.completed
                                      ? 'Replay'
                                      : state.playing
                                      ? 'Pause'
                                      : 'Play',
                                  state.completed
                                      ? AppIconRole.replay
                                      : state.playing
                                      ? AppIconRole.pause
                                      : AppIconRole.play,
                                  () => action(player.playOrPause),
                                  size: 52,
                                ),
                              ),
                              const AppGap.horizontal(28),
                              button(
                                'Forward ${widget.forwardSeconds} seconds',
                                widget.forwardSeconds == 10
                                    ? AppIconRole.seekForward
                                    : AppIconRole.forward,
                                () => seekBy(widget.forwardSeconds),
                                size: 34,
                              ),
                            ],
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        videoTime(Duration(milliseconds: position.round())),
                        style:
                            Theme.of(context)
                                .extension<ThemeTokens>()
                                ?.roleStyle(
                                  'timestamp',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ) ??
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                          ),
                          child: Slider(
                            activeColor: accent,
                            inactiveColor: Colors.white30,
                            value: position,
                            min: 0,
                            max: duration,
                            onChangeStart: (_) => hideTimer?.cancel(),
                            onChanged: state.duration <= Duration.zero
                                ? null
                                : (value) => setState(() => scrub = value),
                            onChangeEnd: (value) async {
                              await action(
                                () => player.seek(
                                  Duration(milliseconds: value.round()),
                                ),
                              );
                              if (mounted) setState(() => scrub = null);
                              armTimer();
                            },
                          ),
                        ),
                      ),
                      Text(
                        videoTime(state.duration),
                        style:
                            Theme.of(context)
                                .extension<ThemeTokens>()
                                ?.roleStyle(
                                  'timestamp',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ) ??
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                toolbar(),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
