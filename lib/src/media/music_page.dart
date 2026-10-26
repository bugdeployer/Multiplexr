import 'session_mini_player.dart';
import '../features/playback/application/audio_commands.dart';
import '../experience/collection/collection_scope_router.dart';
import '../experience/collection/collection_experience.dart';
import 'video_projections.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../catalog/domain/playlist.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../features/catalog/application/collection_presenter.dart';
import '../experience/collection/collection_layout.dart';
import '../experience/navigation/browse_memory.dart';
import '../experience/navigation/navigation_origin.dart';
import '../experience/navigation/navigation_coordinator.dart';
import '../library/tags.dart';
import 'source_recovery.dart';
import 'music_track_picker.dart';
import 'music_space_components.dart';
import '../features/catalog/application/space_queries.dart';
import '../library/library_models.dart';
import '../library/library_controller.dart';
import '../library/collection_form.dart';

import 'package:app_shell/app_shell.dart';

import '../space_preferences.dart';
import 'contracts.dart';
import 'media_cover.dart';
import 'media_ui_patterns.dart';
import 'music_catalog_models.dart';
import '../features/metadata/application/music_metadata_target.dart';
import 'music_metadata_ui.dart';
import 'music_metadata_job.dart';
import 'music_playback.dart';
import 'music_player.dart';
import '../features/catalog/application/music_catalog_commands.dart';
import 'navigation_settings.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({
    super.key,
    required this.library,
    required this.playback,
    this.collectionId,
    this.space = false,
    this.scan = false,
    this.showJobs = false,
  });
  final LibraryController library;
  final MusicPlayback playback;
  final String? collectionId;
  final bool space, scan, showJobs;
  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  bool controlsExpanded = false;
  late final repository = widget.playback.repository;
  late final provider = widget.playback.metadataProvider;
  final updates = ValueNotifier<int>(0);
  bool permitted(MusicTrack track) {
    final owner = widget.library.collections
        .where((c) => c.id == track.id.collectionId)
        .firstOrNull;
    return owner != null &&
        scope.includes(
          owner.catalogCollection,
          authorized: repository.access(owner.id),
        );
  }

  final preferences = SpacePreferences();
  late SpaceDisplay display;
  late final scope = SpaceScope(
    MediaSubtype.music,
    collectionId: widget.collectionId,
  );
  final controller = CollectionController<MusicTrack, MediaId>(
    identity: (t) => t.id,
  );
  final spaceController = SpaceController<MusicAlbum, String>(
    identity: (a) => a.key,
  );
  final query = TextEditingController(), scroll = ScrollController();
  Map<String, dynamic> extra = {'titles': {}, 'albums': {}, 'playlists': []};
  List<MusicTrack> tracks = [];
  List<MusicPlaylist> playlists = [];
  List<MusicAlbum> albums = [];
  Map<MediaId, int> history = {};
  String section = 'Albums',
      genre = '',
      tag = '',
      availability = 'all',
      folder = '',
      sort = 'title';
  bool descending = false;
  int tab = 0, revision = 0;
  bool loading = true, working = false, scanPending = false, canResume = false;
  String? error;
  MusicMetadataJob? job;
  VideoCollection? get collection => widget.library.collections
      .where((c) => c.id == widget.collectionId)
      .firstOrNull;
  late final memory = BrowseMemory(
    preferences: widget.library.service.userPreferences,
    query: query,
    scroll: scroll,
    alive: () => mounted,
    contentReady: () => !loading,
    defaults: () => NavigationOrigin(
      routeId: widget.space ? 'music-space' : 'music-collection',
      collectionId: widget.collectionId,
      tab: 0,
    ),
    capture: () => NavigationOrigin(
      routeId: widget.space ? 'music-space' : 'music-collection',
      collectionId: widget.collectionId,
      query: query.text,
      tab: tab,
      layout: controller.layout.name,
      filter: jsonEncode([
        section,
        genre,
        availability,
        tag,
        folder,
        sort,
        descending,
      ]),
      scrollOffset: scroll.hasClients
          ? scroll.offset.clamp(0, double.infinity)
          : 0,
    ),
    apply: (origin) {
      if (!mounted) return;
      setState(() {
        tab = origin.tab;
        try {
          final saved = jsonDecode(origin.filter) as List;
          section = saved[0];
          genre = saved[1];
          availability = saved[2];
          tag = saved[3];
          folder = saved[4];
          sort = saved[5];
          descending = saved.length > 6 && saved[6] == true;
        } catch (_) {
          section = 'Albums';
          clearFilters();
        }
      });
    },
  );
  @override
  void initState() {
    super.initState();
    display = SpaceDisplay();
    scanPending = widget.scan;
    widget.library.addListener(changed);
    query.addListener(redraw);
    load(initial: true);
  }

  void redraw() {
    if (mounted) setState(() {});
  }

  void changed() {
    if (!mounted) return;
    // Remove revoked content synchronously; storage reloads may take time.
    setState(() {
      tracks = tracks.where(permitted).toList();
      albums = repository.albums(tracks, extra);
      if (widget.collectionId != null &&
          !repository.access(widget.collectionId!)) {
        playlists = [];
      }
    });
    load();
  }

  @override
  void dispose() {
    revision++;
    widget.library.removeListener(changed);
    query.removeListener(redraw);
    memory.dispose();
    query.dispose();
    scroll.dispose();
    updates.dispose();
    controller.dispose();
    spaceController.dispose();
    job?.removeListener(redraw);

    super.dispose();
  }

  Future<void> load({bool initial = false}) async {
    final current = ++revision;
    try {
      if (initial) {
        await preferences.load(widget.library.service.userPreferences);
        display = preferences.music;
        if (widget.collectionId != null && widget.space) {
          display = SpaceDisplay();
          display.restore(
            await widget.library.spaces.read(
                  MediaSubtype.music,
                  widget.collectionId!,
                ) ??
                {},
          );
        }
        tab = 0;
      }
      final overview = await repository.overview(scope);
      final values = overview.tracks,
          extras = overview.extras,
          times = overview.history;
      final lists = await repository.playlists(widget.collectionId);
      final resumable = await widget.playback.canResume(
        values.where((track) => track.available).map((track) => track.id),
      );
      if (!mounted || current != revision) return;
      setState(() {
        tracks = values;
        canResume = resumable;
        extra = extras;
        playlists = lists;
        history = times;
        albums = repository.albums(values, extras);
        if (!values.any((t) => t.metadata.genre == genre)) genre = '';
        if (!values.any((t) => t.folderId == folder)) folder = '';
        if (!values.any(
          (t) => (repository.flags(extras, t.id)['tags'] as List? ?? [])
              .contains(tag),
        )) {
          tag = '';
        }
        controller.replace(values);
        controller.layout = switch (collection?.view) {
          CatalogView.compact => CatalogLayout.compact,
          CatalogView.list => CatalogLayout.list,
          _ => CatalogLayout.grid,
        };
        loading = false;
        error = null;
      });
      updates.value++;
      if (initial) await memory.restore();
      if (widget.collectionId != null &&
          repository.access(widget.collectionId!) &&
          job == null) {
        job = widget.playback.jobFor(widget.collectionId!)..addListener(redraw);
        if (!job!.running) await job!.recover();
        if (widget.showJobs && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => run(showJobs));
        }
      }
      if (scanPending &&
          widget.collectionId != null &&
          repository.access(widget.collectionId!)) {
        scanPending = false;
        await run(() => widget.library.scan(widget.collectionId!));
      }
    } catch (e) {
      if (mounted && current == revision) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  int operations = 0;
  Future<bool> run(Future<void> Function() action) async {
    operations++;
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
      if (mounted) await load();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Bad state: ', ''))),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          operations--;
          working = operations > 0;
        });
      }
    }
  }

  List<MusicTrack> get visible => controller.browse(
    matches: (track) {
      final m = track.metadata, flags = repository.flags(extra, track.id);
      return '${m.title} ${m.artist} ${m.album} ${m.albumArtist} ${m.genre} ${(flags['tags'] as List? ?? []).join(' ')}'
              .toLowerCase()
              .contains(query.text.trim().toLowerCase()) &&
          (genre.isEmpty || m.genre == genre) &&
          (tag.isEmpty || (flags['tags'] as List? ?? []).contains(tag)) &&
          (folder.isEmpty || track.folderId == folder) &&
          (availability == 'all' ||
              availability == 'favorites' && flags['favorite'] == true ||
              availability == 'available' && track.available ||
              availability == 'missing' && !track.available);
    },
    compare: (a, b) {
      final result = switch (sort) {
        'artist' => a.metadata.artist.toLowerCase().compareTo(
          b.metadata.artist.toLowerCase(),
        ),
        'added' =>
          ((repository.flags(extra, b.id)['addedAt'] as num?)?.toInt() ?? 0)
              .compareTo(
                (repository.flags(extra, a.id)['addedAt'] as num?)?.toInt() ??
                    0,
              ),
        'played' => (history[b.id] ?? 0).compareTo(history[a.id] ?? 0),
        'year' => (b.metadata.year ?? 0).compareTo(a.metadata.year ?? 0),
        'duration' => b.metadata.durationMs.compareTo(a.metadata.durationMs),
        _ => a.metadata.title.toLowerCase().compareTo(
          b.metadata.title.toLowerCase(),
        ),
      };
      return descending ? -result : result;
    },
  );
  Future<void> settings({bool player = false}) async {
    if (collection == null || !repository.access(collection!.id)) return;
    await collectionDialog(
      context,
      widget.library,
      existing: collection,
      initialSection: player ? 'Playback' : null,
    );
  }

  Future<void> play(
    MusicTrack track,
    List<MusicTrack> queue, {
    bool shuffle = false,
    int? startIndex,
  }) => NavigationCoordinator.forOwner(widget.library.service.persistenceOwner)
      .run(
        'music:open-player',
        () =>
            _playTitle(track, queue, shuffle: shuffle, startIndex: startIndex),
      );
  Future<void> _playTitle(
    MusicTrack track,
    List<MusicTrack> queue, {
    bool shuffle = false,
    int? startIndex,
  }) async {
    final latest = (await repository.tracks(scope))
        .where((t) => t.id == track.id && t.available)
        .firstOrNull;
    if (latest == null || !mounted) {
      if (mounted) {
        showUnavailableSource(context, widget.library, track.id.collectionId);
      }
      return;
    }
    final owner = widget.library.collections.firstWhere(
      (c) => c.id == track.id.collectionId,
    );
    final navigation = await resolveMediaNavigation(
      widget.library.service,
      collection: owner,
      collectionId: owner.id,
      titleId: track.id.key,
      ancestorIds: [if (track.albumId != null) 'album:${track.albumId}'],
      legacyDetails: true,
    );
    if (!mounted) return;
    if (!permitted(latest)) {
      throw StateError('Collection access changed. Reopen the collection.');
    }
    if (navigation.engine.value.name == 'external') {
      await widget.playback.audio.execute(
        AudioCommand.external(latest.source.uri),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Opened this track externally. Queue controls stay with the external player.',
            ),
          ),
        );
      }
    } else {
      final fresh = await repository.tracks(scope),
          byId = {for (final t in fresh) t.id: t};
      final eligible = [
        for (final item in queue)
          if (byId[item.id]?.available == true) byId[item.id]!,
      ];
      await widget.playback.play(
        eligible,
        start: track.id,
        collectionId: widget.collectionId,
        shuffle: shuffle,
        startIndex: startIndex,
      );
      if (mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => MusicPlayer(playback: widget.playback),
          ),
        );
      }
    }
  }

  Future<void> openTrack(
    MusicTrack track,
    List<MusicTrack> queue, {
    int? startIndex,
  }) async {
    if (controller.selecting) {
      setState(() => controller.toggle(track));
      return;
    }
    final owner = widget.library.collections.firstWhere(
      (c) => c.id == track.id.collectionId,
    );
    final nav = await resolveMediaNavigation(
      widget.library.service,
      collection: owner,
      collectionId: owner.id,
      titleId: track.id.key,
      ancestorIds: [if (track.albumId != null) 'album:${track.albumId}'],
      legacyDetails: true,
    );
    if (!mounted || !repository.access(owner.id)) return;
    if (nav.opening.value.name == 'play') {
      await play(track, queue, startIndex: startIndex);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (page) => _MusicProtectedBuilder(
          library: widget.library,
          updates: updates,
          allowed: () => permitted(track),
          builder: (page, update) {
            final latest =
                tracks.where((t) => t.id == track.id).firstOrNull ?? track;
            return Scaffold(
              appBar: AppBar(
                title: Text(latest.metadata.title),
                actions: [trackMenu(latest, after: () => update(() {}))],
              ),
              bottomNavigationBar: SessionMiniPlayer(playback: widget.playback),
              body: ListView(
                padding: AppSpacing.of(context).all(20),
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: MediaCover(cover: latest.metadata.cover),
                  ),
                  const AppGap(20),
                  Text(
                    latest.metadata.title,
                    style: Theme.of(page).textTheme.headlineSmall,
                  ),
                  const AppGap(8),
                  Text(latest.metadata.artist),
                  if (latest.metadata.album.isNotEmpty)
                    Text(latest.metadata.album),
                  if (latest.metadata.year != null)
                    Text('${latest.metadata.year}'),
                  const AppGap(20),
                  FilledButton.icon(
                    onPressed: latest.available
                        ? () => run(
                            () => play(latest, queue, startIndex: startIndex),
                          )
                        : null,
                    icon: const AppIcon(AppIconRole.play),
                    label: const Text('Play'),
                  ),
                  const AppGap(16),
                  Text(
                    '${(latest.metadata.durationMs / 60000).ceil()} min · ${latest.metadata.genre}',
                  ),
                  if (!latest.available)
                    const Text(
                      'Source unavailable. Check Folder health or reselect its root folder.',
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> editMetadata(MusicTrack track) async {
    final values = await textForm('Edit metadata', {
      'title': track.metadata.title,
      'artist': track.metadata.artist,
      'album': track.metadata.album,
      'albumArtist': track.metadata.albumArtist,
      'genre': track.metadata.genre,
      'year': '${track.metadata.year ?? ''}',
      'disc': '${track.metadata.disc}',
      'track': '${track.metadata.track}',
    });
    if (values == null) return;
    final patch = <String, Object?>{...values};
    for (final field in ['year', 'disc', 'track']) {
      final raw = values[field]!.trim();
      final number = int.tryParse(raw);
      if (raw.isNotEmpty && (number == null || number < 0)) {
        throw StateError('$field must be a non-negative number.');
      }
      patch[field] = raw.isEmpty && field == 'year' ? null : number ?? 0;
    }
    if ((patch['title'] as String).trim().isEmpty) {
      throw StateError('A title is required.');
    }
    await repository.patchTrack(
      track.id,
      (current) => current.corrected(patch),
    );
    await widget.playback.refreshMetadata();
  }

  Future<Map<String, String>?> textForm(
    String title,
    Map<String, String> values,
  ) async {
    final fields = Map<String, String>.from(values);
    return await showDialog<Map<String, String>>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                    initialValue: entry.value,
                    onChanged: (value) => fields[entry.key] = value,
                    decoration: InputDecoration(labelText: entry.key),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, {
              for (final e in fields.entries) e.key: e.value.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> lookup({
    MusicTrack? track,
    MusicAlbum? album,
    MetadataCandidate? saved,
  }) async {
    final target = MusicMetadataTarget(
      repository,
      trackId: track?.id,
      album: album,
    );
    final candidate =
        saved ??
        await findMusicMetadata(
          context,
          provider,
          entity: target.entity,
          title: album?.title ?? track!.metadata.title,
          artist: album?.artist ?? track!.metadata.artist,
        );
    if (candidate != null &&
        mounted &&
        await reviewMusicMetadata(context, target, candidate)) {
      if (track != null) await job?.applied(track.id.key);
      await widget.playback.refreshMetadata();
    }
  }

  Future<void> artwork({MusicTrack? track, MusicAlbum? album}) async {
    final image = await chooseMusicArtwork(
      context,
      provider,
      imports: widget.library.imports,
      title:
          album?.title ??
          (track!.metadata.album.isEmpty
              ? track.metadata.title
              : track.metadata.album),
      artist: album?.artist ?? track!.metadata.artist,
      album: album,
    );
    if (image == null) return;
    if (album != null) {
      await repository.setAlbum(album, {
        'cover': image,
        'coverSource': 'manual',
      });
    } else {
      await repository.patchTrack(
        track!.id,
        (current) =>
            current.corrected({'cover': image, 'coverSource': 'manual'}),
      );
    }
    await widget.playback.refreshMetadata();
  }

  Widget trackMenu(
    MusicTrack track, {
    VoidCallback? after,
  }) => PopupMenuButton<String>(
    icon: const AppIcon(AppIconRole.menu),
    itemBuilder: (_) => [
      ...mediaMetadataActions(settings: true),
      const PopupMenuItem(value: 'next', child: Text('Play next')),
      const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
      const PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
      PopupMenuItem(
        value: 'favorite',
        child: Text(
          repository.flags(extra, track.id)['favorite'] == true
              ? 'Remove favorite'
              : 'Favorite',
        ),
      ),
      const PopupMenuItem(value: 'tags', child: Text('Manage tags')),
      const PopupMenuItem(value: 'repair', child: Text('Repair source')),
      const PopupMenuItem(
        value: 'group',
        child: Text('Correct album grouping'),
      ),
    ],
    onSelected: (action) async {
      await run(() async {
        switch (action) {
          case 'settings':
            await showMediaNavigationSettings(
              context,
              widget.library.service,
              MediaNavigationSettings.key(track.id.collectionId, track.id.key),
              track.metadata.title,
              showRate: false,
              groupLabel: 'Album',
              ancestorIds: [
                if (track.albumId != null) 'album:${track.albumId}',
              ],
            );
          case 'edit':
            await editMetadata(track);
          case 'metadata':
            await lookup(track: track);
          case 'artwork':
            await artwork(track: track);
          case 'next':
            await widget.playback.enqueue(track, next: true);
          case 'queue':
            await widget.playback.enqueue(track);
          case 'playlist':
            await addToPlaylist([track]);
          case 'favorite':
            await repository.setFlags(track.id, {
              'favorite': repository.flags(extra, track.id)['favorite'] != true,
            });
          case 'repair':
            await repairTrack(track);
          case 'tags':
            await editTags([track]);
          case 'group':
            await correctAlbum(track);
        }
      });
      after?.call();
    },
  );
  Widget trackRow(
    MusicTrack track,
    List<MusicTrack> queue, {
    bool compact = false,
  }) => !permitted(track)
      ? const SizedBox.shrink()
      : MediaItemSelection(
          selected: controller.selecting
              ? controller.selected.contains(track.id)
              : null,
          onToggle: () => setState(() => controller.toggle(track)),
          reserveLeading: true,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: controller.selecting
                  ? null
                  : widget.space && !display.artwork
                  ? null
                  : SizedBox.square(
                      dimension: compact ? 36 : 56,
                      child: MediaCover(cover: track.metadata.cover),
                    ),
              title: Text(
                track.metadata.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${track.metadata.artist}${compact ? '' : '\n${track.metadata.album}'}${track.available ? '' : ' · Unavailable'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: trackMenu(track),
              onTap: () => run(() => openTrack(track, queue)),
              onLongPress: () => setState(() {
                section = 'Tracks';
                controller.selecting = true;
                controller.toggle(track);
              }),
            ),
          ),
        );
  Future<void> albumPage(MusicAlbum album) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (page) => _MusicProtectedBuilder(
          library: widget.library,
          updates: updates,
          allowed: () => album.tracks.any(permitted),
          builder: (page, update) {
            final latest =
                albums.where((a) => a.key == album.key).firstOrNull ?? album;
            return Scaffold(
              appBar: AppBar(
                title: Text(latest.title),
                actions: [
                  PopupMenuButton<String>(
                    icon: const AppIcon(AppIconRole.menu),
                    itemBuilder: (_) => mediaMetadataActions(settings: true),
                    onSelected: (action) async {
                      await run(() async {
                        switch (action) {
                          case 'settings':
                            await showMediaNavigationSettings(
                              context,
                              widget.library.service,
                              MediaNavigationSettings.key(
                                album.id.collectionId,
                                'album:${album.id.entityId}',
                              ),
                              latest.title,
                              showRate: false,
                              groupLabel: 'Album',
                            );
                          case 'edit':
                            final values = await textForm(
                              'Edit album metadata',
                              {
                                'title': latest.title,
                                'artist': latest.artist,
                                'year': '${latest.year ?? ''}',
                              },
                            );
                            if (values != null) {
                              final year = int.tryParse(values['year']!);
                              if (values['title']!.isEmpty ||
                                  values['year']!.isNotEmpty &&
                                      (year == null || year < 0)) {
                                throw StateError(
                                  'Enter an album title and valid year.',
                                );
                              }
                              await repository.setAlbum(latest, {
                                'title': values['title'],
                                'artist': values['artist'],
                                'year': year,
                                'metadataSource': 'manual',
                              });
                            }
                          case 'metadata':
                            await lookup(album: latest);
                          case 'artwork':
                            await artwork(album: latest);
                        }
                      });
                      if (page.mounted) update(() {});
                    },
                  ),
                ],
              ),
              bottomNavigationBar: SessionMiniPlayer(playback: widget.playback),
              body: ListView(
                padding: AppSpacing.of(context).all(20),
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: MediaCover(cover: latest.cover),
                  ),
                  const AppGap(20),
                  Text(
                    latest.title,
                    style: Theme.of(page).textTheme.headlineSmall,
                  ),
                  const AppGap(8),
                  Text(latest.artist),
                  if (latest.year != null) Text('${latest.year}'),
                  const AppGap(20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: latest.tracks.any((t) => t.available)
                            ? () => run(
                                () => play(
                                  latest.tracks.firstWhere((t) => t.available),
                                  latest.tracks,
                                ),
                              )
                            : null,
                        child: const Text('Play album'),
                      ),
                      OutlinedButton(
                        onPressed: latest.tracks.any((t) => t.available)
                            ? () => run(
                                () => play(
                                  latest.tracks.firstWhere((t) => t.available),
                                  latest.tracks,
                                  shuffle: true,
                                ),
                              )
                            : null,
                        child: const Text('Shuffle'),
                      ),
                    ],
                  ),
                  const AppGap(24),
                  for (final track in latest.tracks) ...[
                    if (track.metadata.disc > 0 &&
                        latest.tracks
                                .where(
                                  (t) => t.metadata.disc == track.metadata.disc,
                                )
                                .first
                                .id ==
                            track.id)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Disc ${track.metadata.disc}'),
                      ),
                    trackRow(track, latest.tracks),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget albumTile(MusicAlbum album) => widget.space && !display.artwork
      ? Card(
          child: ListTile(
            title: Text(album.title),
            subtitle: Text(album.artist),
            onTap: () => albumPage(album),
          ),
        )
      : Semantics(
          label: album.title,
          button: true,
          child: InkWell(
            onTap: () => albumPage(album),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: MediaCover(cover: album.cover),
                ),
                const AppGap(8),
                Text(album.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
  Widget albumGrid(List<MusicAlbum> items) => CollectionLayout(
    layout: controller.layout,
    cardSize: collection?.cardSize ?? 180,
    builder: (context, width, grid, compact) => grid
        ? Wrap(
            spacing: 12,
            runSpacing: 20,
            children: [
              for (final album in items)
                SizedBox(width: width, child: albumTile(album)),
            ],
          )
        : Column(
            children: [
              for (final album in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: SizedBox.square(
                      dimension: compact ? 36 : 64,
                      child: MediaCover(cover: album.cover),
                    ),
                    title: Text(album.title),
                    subtitle: Text(album.artist),
                    trailing: const AppIcon(AppIconRole.disclosure),
                    onTap: () => albumPage(album),
                  ),
                ),
            ],
          ),
  );
  Future<void> correctAlbum(MusicTrack track) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Keep as an ungrouped track'),
              onTap: () => Navigator.pop(sheet, ''),
            ),
            ListTile(
              title: const Text('Create a new album group'),
              onTap: () => Navigator.pop(sheet, 'new'),
            ),
            for (final album in albums.where(
              (a) => a.id.collectionId == track.id.collectionId,
            ))
              ListTile(
                title: Text(album.title),
                subtitle: Text(album.artist),
                onTap: () => Navigator.pop(sheet, album.id.entityId),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    String? albumId = selected.isEmpty ? null : selected;
    String? title;
    if (selected == 'new') {
      final values = await textForm('New album', {
        'title': track.metadata.album,
      });
      if (values == null || values['title']!.isEmpty) return;
      albumId = repository.newIdentity();
      title = values['title'];
    }
    final existing = albums
        .where(
          (a) =>
              a.id.entityId == albumId &&
              a.id.collectionId == track.id.collectionId,
        )
        .firstOrNull;
    await repository.patchTrack(
      track.id,
      (current) => current.corrected({
        'albumId': albumId,
        'album': ?title,
        if (existing != null) 'album': existing.title,
      }),
    );
  }

  Future<void> repairTrack(MusicTrack track) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Repair folders'),
              subtitle: const Text('Reconnect a root folder and scan again.'),
              onTap: () => Navigator.pop(sheet, 'folders'),
            ),
            if (!track.available)
              ListTile(
                title: const Text('Reconnect to an indexed track'),
                subtitle: const Text(
                  'Keep this title, metadata, playlists and progress.',
                ),
                onTap: () => Navigator.pop(sheet, 'track'),
              ),
          ],
        ),
      ),
    );
    if (action == 'folders' && mounted) {
      await recoverCollectionSource(
        context,
        track.id.collectionId,
        authorized: () => repository.access(track.id.collectionId),
        controller: widget.library,
      );
      return;
    }
    if (action != 'track' || !mounted) return;
    final chosen = await pickTracks(
      context,
      tracks
          .where(
            (t) => t.available && t.id.collectionId == track.id.collectionId,
          )
          .toList(),
    );
    if (chosen == null || !mounted) return;
    if (chosen.length != 1) {
      throw StateError('Choose exactly one replacement track.');
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reconnect this track?'),
        content: Text(
          'Use ${chosen.single.metadata.title} as the source for ${track.metadata.title}. This keeps the original metadata and progress, and combines their playlist references. Current audio playback will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Reconnect'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await repository.reconnect(track, chosen.single);
      await widget.library.load();
    }
  }

  Future<void> manageTagVocabulary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) {
          final names = <String, String>{};
          for (final t in tracks) {
            for (final value in List<String>.from(
              repository.flags(extra, t.id)['tags'] ?? [],
            )) {
              names.putIfAbsent(value.toLowerCase(), () => value);
            }
          }
          final sorted = names.values.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * .75,
              child: ListView(
                padding: AppSpacing.of(context).all(24),
                children: [
                  Text(
                    'Manage tags',
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                  const AppGap(12),
                  const Text(
                    'Rename or remove tags in this collection. Use selection to add tags to tracks.',
                  ),
                  const AppGap(16),
                  if (sorted.isEmpty) const Text('No tags yet.'),
                  for (final tag in sorted)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tag),
                      subtitle: Text(
                        '${tracks.where((t) => List<String>.from(repository.flags(extra, t.id)['tags'] ?? []).any((s) => s.toLowerCase() == tag.toLowerCase())).length} tracks',
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const AppIcon(AppIconRole.menu),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename tag'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove tag'),
                          ),
                        ],
                        onSelected: (action) async {
                          final selected = tracks
                              .where(
                                (t) =>
                                    List<String>.from(
                                      repository.flags(extra, t.id)['tags'] ??
                                          [],
                                    ).any(
                                      (s) =>
                                          s.toLowerCase() == tag.toLowerCase(),
                                    ),
                              )
                              .map((t) => t.id)
                              .toList();
                          var replacement = '';
                          if (action == 'rename') {
                            final values = await textForm('Rename tag', {
                              'name': tag,
                            });
                            if (values == null) return;
                            final parsed = normalizeTags(values['name']!);
                            if (parsed.length != 1) {
                              throw StateError('Enter one tag name.');
                            }
                            replacement = parsed.single;
                          } else {
                            if (!sheet.mounted) return;
                            final confirm = await showDialog<bool>(
                              context: sheet,
                              builder: (dialog) => AlertDialog(
                                title: const Text('Remove this tag?'),
                                content: Text(
                                  'Remove $tag from ${selected.length} tracks. Other tags are kept.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialog, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialog, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true) return;
                          }
                          Map<MediaId, List<String>>? before;
                          await run(() async {
                            before = action == 'rename'
                                ? await repository.renameTag(
                                    selected,
                                    tag,
                                    replacement,
                                  )
                                : await repository.changeTags(
                                    selected,
                                    'remove',
                                    [tag],
                                  );
                          });
                          if (sheet.mounted) update(() {});
                          if (before != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Tags updated'),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => run(
                                    () => repository.restoreTags(before!),
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  const AppGap(20),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(sheet);
                      setState(() {
                        section = 'Tracks';
                        controller.selecting = true;
                      });
                    },
                    child: const Text('Select tracks to add tags'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> editTags(List<MusicTrack> selected) async {
    if (selected.isEmpty) return;
    var operation = selected.length == 1 ? 'replace' : 'add';
    var input = selected.length == 1
        ? (repository.flags(extra, selected.single.id)['tags'] as List? ?? [])
              .join(', ')
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(
            'Tags · ${selected.length} ${selected.length == 1 ? 'track' : 'tracks'}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: operation,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: const [
                    DropdownMenuItem(value: 'add', child: Text('Add tags')),
                    DropdownMenuItem(
                      value: 'remove',
                      child: Text('Remove tags'),
                    ),
                    DropdownMenuItem(
                      value: 'replace',
                      child: Text('Replace all tags'),
                    ),
                  ],
                  onChanged: (v) => update(() => operation = v!),
                ),
                const AppGap(20),
                TextFormField(
                  initialValue: input,
                  onChanged: (value) => input = value,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Separate tags with commas.',
                  ),
                ),
                const AppGap(12),
                Text(
                  operation == 'replace'
                      ? 'This replaces existing tags on every selected track.'
                      : 'Other tags are kept.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final tags = normalizeTags(input);
    final before = await repository.changeTags(
      selected.map((t) => t.id).toList(),
      operation,
      tags,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated tags on ${selected.length} tracks'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => run(() => repository.restoreTags(before)),
          ),
        ),
      );
    }
  }

  Future<void> createPlaylist() async {
    final fields = await textForm('Create playlist', {'name': ''});
    if (fields == null || fields['name']!.isEmpty || !mounted) return;
    final chosen = await pickTracks(
      context,
      tracks.where((t) => t.available).toList(),
    );
    if (chosen == null) return;
    final list = MusicPlaylist(
      id: repository.newIdentity(),
      name: fields['name']!,
      scope: widget.collectionId == null
          ? const PlaylistScope.global()
          : PlaylistScope.collection(widget.collectionId!),
      entries: [
        for (final t in chosen)
          PlaylistEntry(id: repository.newIdentity(), track: t.catalogTitle.id),
      ],
    );
    await repository.savePlaylist(list);
    await load();
    if (mounted) await playlistPage(list);
  }

  Future<void> addToPlaylist(List<MusicTrack> selected) async {
    final lists = await repository.playlists(widget.collectionId);
    if (!mounted) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Create playlist'),
              onTap: () => Navigator.pop(sheet, 'new'),
            ),
            for (final list in lists)
              ListTile(
                title: Text(list.name),
                onTap: () => Navigator.pop(sheet, list.id),
              ),
          ],
        ),
      ),
    );
    if (id == null) return;
    MusicPlaylist playlist;
    if (id == 'new') {
      final fields = await textForm('Create playlist', {'name': ''});
      if (fields == null || fields['name']!.isEmpty) return;
      playlist = MusicPlaylist(
        id: repository.newIdentity(),
        name: fields['name']!,
        scope: widget.collectionId == null
            ? const PlaylistScope.global()
            : PlaylistScope.collection(widget.collectionId!),
        entries: [],
      );
    } else {
      playlist = lists.firstWhere((p) => p.id == id);
    }
    await repository.savePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: playlist.name,
        scope: playlist.scope,
        entries: [
          ...playlist.entries,
          for (final track in selected)
            PlaylistEntry(
              id: repository.newIdentity(),
              track: track.catalogTitle.id,
            ),
        ],
      ),
    );
  }

  Future<void> playlistPage(MusicPlaylist initial) async {
    var playlist = initial;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (page) => _MusicProtectedBuilder(
          library: widget.library,
          updates: updates,
          allowed: () =>
              widget.collectionId == null ||
              repository.access(widget.collectionId!),
          builder: (page, update) {
            final playable = repository.playlistTracks(playlist, tracks);
            final byId = {
              for (final track in tracks.where((t) => t.available))
                track.catalogTitle.id: track,
            };
            final entries = playlist.entries
                .where((e) => playable.any((t) => t.catalogTitle.id == e.track))
                .toList();
            return Scaffold(
              appBar: AppBar(
                title: Text(playlist.name),
                actions: [
                  PopupMenuButton<String>(
                    icon: const AppIcon(AppIconRole.menu),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename playlist'),
                      ),
                      const PopupMenuItem(
                        value: 'add',
                        child: Text('Add tracks'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete playlist'),
                      ),
                    ],
                    onSelected: (action) async {
                      var draft = playlist;
                      final saved = await run(() async {
                        if (action == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: page,
                            builder: (dialog) => AlertDialog(
                              title: const Text('Delete playlist?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await repository.deletePlaylist(playlist);
                            if (page.mounted) Navigator.pop(page);
                          }
                          return;
                        }
                        if (action == 'rename') {
                          final values = await textForm('Rename playlist', {
                            'name': playlist.name,
                          });
                          if (values == null || values['name']!.isEmpty) return;
                          draft = MusicPlaylist(
                            id: playlist.id,
                            name: values['name']!,
                            scope: playlist.scope,
                            entries: playlist.entries,
                          );
                        } else {
                          final chosen = await pickTracks(
                            page,
                            tracks.where((t) => t.available).toList(),
                          );
                          if (chosen == null) return;
                          draft = MusicPlaylist(
                            id: playlist.id,
                            name: playlist.name,
                            scope: playlist.scope,
                            entries: [
                              ...playlist.entries,
                              for (final t in chosen)
                                PlaylistEntry(
                                  id: repository.newIdentity(),
                                  track: t.catalogTitle.id,
                                ),
                            ],
                          );
                        }
                        await repository.savePlaylist(draft);
                      });
                      if (saved && page.mounted) update(() => playlist = draft);
                    },
                  ),
                ],
              ),
              bottomNavigationBar: SessionMiniPlayer(playback: widget.playback),
              body: Column(
                children: [
                  Padding(
                    padding: AppSpacing.of(context).all(20),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: playable.isEmpty
                              ? null
                              : () => run(() => play(playable.first, playable)),
                          child: const Text('Play playlist'),
                        ),
                        OutlinedButton(
                          onPressed: playable.isEmpty
                              ? null
                              : () => run(
                                  () => play(
                                    playable.first,
                                    playable,
                                    shuffle: true,
                                  ),
                                ),
                          child: const Text('Shuffle'),
                        ),
                      ],
                    ),
                  ),
                  if (entries.isEmpty)
                    Padding(
                      padding: AppSpacing.of(context).all(20),
                      child: Column(
                        children: [
                          const Text('Add tracks to start this playlist.'),
                          const AppGap(12),
                          FilledButton.icon(
                            icon: const AppIcon(AppIconRole.add),
                            label: const Text('Add tracks'),
                            onPressed: () async {
                              final chosen = await pickTracks(
                                page,
                                tracks.where((t) => t.available).toList(),
                              );
                              if (chosen == null) return;
                              final next = MusicPlaylist(
                                id: playlist.id,
                                name: playlist.name,
                                scope: playlist.scope,
                                entries: [
                                  ...playlist.entries,
                                  for (final t in chosen)
                                    PlaylistEntry(
                                      id: repository.newIdentity(),
                                      track: t.catalogTitle.id,
                                    ),
                                ],
                              );
                              final saved = await run(
                                () => repository.savePlaylist(next),
                              );
                              if (saved && page.mounted) {
                                update(() => playlist = next);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: entries.length,
                      onReorderItem: (oldIndex, newIndex) async {
                        final reordered = [...entries];
                        final moved = reordered.removeAt(oldIndex);
                        reordered.insert(newIndex, moved);
                        final visibleIds = reordered.map((e) => e.id).toSet();
                        var index = 0;
                        final next = MusicPlaylist(
                          id: playlist.id,
                          name: playlist.name,
                          scope: playlist.scope,
                          entries: [
                            for (final e in playlist.entries)
                              visibleIds.contains(e.id)
                                  ? reordered[index++]
                                  : e,
                          ],
                        );
                        final saved = await run(
                          () => repository.savePlaylist(next),
                        );
                        if (saved && page.mounted) {
                          update(() => playlist = next);
                        }
                      },
                      itemBuilder: (_, i) {
                        final track = byId[entries[i].track]!;
                        return ListTile(
                          key: ValueKey(entries[i].id),
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Tooltip(
                              message: 'Drag to reorder',
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: AppIcon(AppIconRole.drag),
                              ),
                            ),
                          ),
                          title: Text(track.metadata.title),
                          subtitle: Text(track.metadata.artist),
                          onTap: () => run(
                            () => openTrack(track, playable, startIndex: i),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove from playlist',
                            icon: const AppIcon(AppIconRole.close),
                            onPressed: () async {
                              final next = MusicPlaylist(
                                id: playlist.id,
                                name: playlist.name,
                                scope: playlist.scope,
                                entries: playlist.entries.where(
                                  (e) => e.id != entries[i].id,
                                ),
                              );
                              final saved = await run(
                                () => repository.savePlaylist(next),
                              );
                              if (saved && page.mounted) {
                                update(() => playlist = next);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<List<MusicTrack>?> pickTracks(
    BuildContext page,
    List<MusicTrack> options,
  ) => Navigator.push<List<MusicTrack>>(
    page,
    MaterialPageRoute(builder: (_) => MusicTrackPicker(options: options)),
  );

  Future<void> showJobs() async {
    if (job == null) return;
    await job!.recover();
    if (!mounted) return;
    var filter = 'review';
    var advance = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (page) => _MusicProtectedBuilder(
          library: widget.library,
          updates: updates,
          allowed: () =>
              widget.collectionId != null &&
              repository.access(widget.collectionId!),
          builder: (page, update) => ListenableBuilder(
            listenable: job!,
            builder: (page, _) {
              final matching = tracks
                  .where(
                    (t) =>
                        job!.entries[t.id.key] != null &&
                        (filter == 'all' ||
                            job!.entries[t.id.key]['status'] == filter),
                  )
                  .toList();
              Future<void> reviewTrack(MusicTrack initial) async {
                MusicTrack? track = initial;
                final seen = <MediaId>{};
                while (track != null &&
                    page.mounted &&
                    repository.access(track.id.collectionId)) {
                  seen.add(track.id);
                  final saved =
                      job!.entries[track.id.key]?['candidates'] as List? ?? [];
                  MetadataCandidate? candidate;
                  if (saved.isNotEmpty) {
                    if (!page.mounted) return;
                    final chosen = await showDialog<Object>(
                      context: page,
                      builder: (dialog) => SimpleDialog(
                        title: const Text('Review metadata matches'),
                        children: [
                          for (final raw in saved)
                            SimpleDialogOption(
                              child: Text(
                                '${raw['values']['title']} · ${raw['values']['artist']}\n${raw['values']['album'] ?? ''} · ${raw['values']['edition'] ?? ''}',
                              ),
                              onPressed: () => Navigator.pop(
                                dialog,
                                MetadataCandidate.fromJson(
                                  Map<String, dynamic>.from(raw),
                                  provider: provider.id,
                                  entity: MetadataEntityType.musicTrack,
                                  attribution: 'Imported metadata',
                                ),
                              ),
                            ),
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(dialog, 'search'),
                            child: const Text('Search again'),
                          ),
                        ],
                      ),
                    );
                    if (chosen == null || !page.mounted) return;
                    if (chosen is MetadataCandidate) candidate = chosen;
                  }
                  if (!page.mounted) return;
                  candidate ??= await findMusicMetadata(
                    page,
                    provider,
                    entity: MetadataEntityType.musicTrack,
                    title: track.metadata.title,
                    artist: track.metadata.artist,
                  );
                  if (candidate == null || !page.mounted) return;
                  final applied = await reviewMusicMetadata(
                    page,
                    MusicMetadataTarget(repository, trackId: track.id),
                    candidate,
                  );
                  if (!applied) return;
                  await job!.applied(track.id.key);
                  await load();
                  if (!advance) return;
                  track = tracks
                      .where(
                        (t) =>
                            !seen.contains(t.id) &&
                            job!.entries[t.id.key]?['status'] == 'review',
                      )
                      .firstOrNull;
                }
              }

              return Scaffold(
                appBar: AppBar(title: const Text('Metadata jobs')),
                body: ListView(
                  padding: AppSpacing.of(context).all(20),
                  children: [
                    Text(
                      '${job!.done} of ${job!.total} · ${job!.remaining.length} remaining',
                    ),
                    if (job!.pausedReason != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(job!.pausedReason!),
                      ),
                    if (job!.running)
                      TextButton(
                        onPressed: job!.cancel,
                        child: const Text('Cancel job'),
                      ),
                    if (!job!.running && job!.remaining.isNotEmpty)
                      FilledButton(
                        onPressed: () =>
                            run(() => job!.start(tracks, resume: true)),
                        child: const Text('Resume metadata job'),
                      ),
                    const AppGap(20),
                    DropdownButtonFormField<String>(
                      icon: const AppIcon(AppIconRole.expand),
                      initialValue: filter,
                      decoration: const InputDecoration(labelText: 'Show'),
                      items: const [
                        DropdownMenuItem(
                          value: 'review',
                          child: Text('Pending review'),
                        ),
                        DropdownMenuItem(
                          value: 'failed',
                          child: Text('Failed'),
                        ),
                        DropdownMenuItem(
                          value: 'noMatch',
                          child: Text('No match'),
                        ),
                        DropdownMenuItem(
                          value: 'applied',
                          child: Text('Applied'),
                        ),
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All results'),
                        ),
                      ],
                      onChanged: (v) => update(() => filter = v!),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Review next after applying'),
                      value: advance,
                      onChanged: (v) => update(() => advance = v),
                    ),
                    const AppGap(20),
                    if (matching.isEmpty) const Text('No titles in this view.'),
                    for (final track in matching)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(track.metadata.title),
                          subtitle: Text(
                            '${job!.entries[track.id.key]['status']}${job!.entries[track.id.key]['error'] == null ? '' : ' · ${job!.entries[track.id.key]['error']}'}',
                          ),
                          trailing: const AppIcon(AppIconRole.disclosure),
                          onTap: () => run(() => reviewTrack(track)),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> filters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SingleChildScrollView(
            padding: AppSpacing.of(context).all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: availability,
                  decoration: const InputDecoration(labelText: 'Filter'),
                  items: [
                    for (final v in [
                      'all',
                      'favorites',
                      'available',
                      'missing',
                    ])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => update(() => availability = v!),
                ),
                const AppGap(16),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: genre,
                  decoration: const InputDecoration(labelText: 'Genre'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All genres'),
                    ),
                    for (final v
                        in tracks
                            .map((t) => t.metadata.genre)
                            .where((s) => s.isNotEmpty)
                            .toSet())
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => update(() => genre = v!),
                ),
                const AppGap(16),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: tag,
                  decoration: const InputDecoration(labelText: 'Tag'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All tags')),
                    for (final v
                        in tracks
                            .expand(
                              (t) => List<String>.from(
                                repository.flags(extra, t.id)['tags'] ?? [],
                              ),
                            )
                            .toSet())
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => update(() => tag = v!),
                ),
                if (collection?.allowFolders == true) ...[
                  const AppGap(16),
                  DropdownButtonFormField<String>(
                    icon: const AppIcon(AppIconRole.expand),
                    initialValue: folder,
                    decoration: const InputDecoration(labelText: 'Folder'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All folders'),
                      ),
                      for (final v in tracks.map((t) => t.folderId).toSet())
                        DropdownMenuItem(
                          value: v,
                          child: Text(
                            v.split('/').last,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => update(() => folder = v!),
                  ),
                ],
                const AppGap(16),
                TextButton(
                  onPressed: () => update(() => clearFilters()),
                  child: const Text('Clear filters'),
                ),
                const AppGap(20),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> spaceSettings() async {
    final draft = SpaceDisplay()..restore(display.toJson());
    final eligible = albums
        .where((a) => a.tracks.any((t) => t.available))
        .toList();
    draft.pins.removeWhere((id) => !eligible.any((a) => a.key == id));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SingleChildScrollView(
            padding: AppSpacing.of(context).all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Music space settings',
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
                const AppGap(20),

                const AppGap(16),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: draft.source,
                  decoration: const InputDecoration(labelText: 'Showcase'),
                  items: const [
                    DropdownMenuItem(
                      value: 'recent',
                      child: Text('Recent albums'),
                    ),
                    DropdownMenuItem(
                      value: 'pinned',
                      child: Text('Choose up to three albums'),
                    ),
                    DropdownMenuItem(
                      value: 'favorites',
                      child: Text('Favorite albums'),
                    ),
                    DropdownMenuItem(
                      value: 'progress',
                      child: Text('Recently played albums'),
                    ),
                  ],
                  onChanged: (v) => update(() => draft.source = v!),
                ),
                if (draft.source == 'pinned') ...[
                  const AppGap(16),
                  for (var i = 0; i < draft.pins.length; i++)
                    ListTile(
                      title: Text(
                        eligible
                            .firstWhere((a) => a.key == draft.pins[i])
                            .title,
                      ),
                      leading: Text('${i + 1}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Move artwork up',
                            onPressed: i == 0
                                ? null
                                : () => update(() {
                                    final item = draft.pins.removeAt(i);
                                    draft.pins.insert(i - 1, item);
                                  }),
                            icon: const AppIcon(AppIconRole.sortAscending),
                          ),
                          IconButton(
                            tooltip: 'Remove pinned title',
                            onPressed: () =>
                                update(() => draft.pins.removeAt(i)),
                            icon: const AppIcon(AppIconRole.close),
                          ),
                        ],
                      ),
                    ),
                  if (draft.pins.length < 3)
                    for (final album in eligible.where(
                      (a) => !draft.pins.contains(a.key),
                    ))
                      ListTile(
                        title: Text(album.title),
                        trailing: const AppIcon(AppIconRole.add),
                        onTap: () => update(() => draft.pins.add(album.key)),
                      ),
                ],
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

                const AppGap(20),
                FilledButton(
                  onPressed: () async {
                    await run(() async {
                      if (widget.collectionId == null) {
                        final old = preferences.music.toJson();
                        preferences.music.restore(draft.toJson());
                        try {
                          await preferences.save(
                            widget.library.service.userPreferences,
                          );
                        } catch (_) {
                          preferences.music.restore(old);
                          rethrow;
                        }
                      } else {
                        if (!repository.access(widget.collectionId!)) {
                          throw StateError('Collection access required.');
                        }
                        await widget.library.spaces.save(
                          MediaSubtype.music,
                          widget.collectionId!,
                          draft.toJson(),
                        );
                      }
                      display.restore(draft.toJson());
                    });
                    if (sheet.mounted && error == null) Navigator.pop(sheet);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> menu(String action) => run(() async {
    switch (action) {
      case 'createPlaylist':
        await createPlaylist();
      case 'settings':
        await settings();
      case 'player':
        await settings(player: true);
      case 'space-settings':
        await spaceSettings();
      case 'scan':
        await widget.library.scan(widget.collectionId!);
      case 'select':
        setState(() {
          section = 'Tracks';
          controller.selecting = true;
        });
      case 'tags':
        if (controller.selected.isEmpty) {
          await manageTagVocabulary();
        } else {
          await editTags(
            tracks.where((t) => controller.selected.contains(t.id)).toList(),
          );
        }
      case 'bulk':
        await job?.start(
          controller.selected.isEmpty
              ? tracks
              : tracks
                    .where((t) => controller.selected.contains(t.id))
                    .toList(),
        );
      case 'retry':
        await job?.start(tracks, retry: true);
      case 'jobs':
        await showJobs();
      case 'health':
        await recoverCollectionSource(
          context,
          widget.collectionId!,
          authorized: () => repository.access(widget.collectionId!),
          controller: widget.library,
        );
      case 'playlist':
        await addToPlaylist(
          tracks.where((t) => controller.selected.contains(t.id)).toList(),
        );
      case 'reset':
        await memory.reset();
    }
  });
  List<Widget> browsing() {
    final matches = visible;
    if (section == 'Albums') {
      final ids = matches.map((t) => t.id).toSet();
      return [
        albumGrid(
          albums.where((a) => a.tracks.any((t) => ids.contains(t.id))).toList(),
        ),
      ];
    }
    if (section == 'Artists') {
      final artists = matches.map((t) => t.metadata.artist).toSet().toList()
        ..sort();
      return [
        for (final artist in artists)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(artist.isEmpty ? 'Unknown artist' : artist),
              trailing: const AppIcon(AppIconRole.disclosure),
              onTap: () => artistPage(artist),
            ),
          ),
      ];
    }
    if (section == 'Playlists') {
      return [
        FilledButton.icon(
          onPressed: () => run(createPlaylist),
          icon: const AppIcon(AppIconRole.add),
          label: const Text('Create playlist'),
        ),
        const AppGap(16),
        for (final playlist in playlists.where(
          (p) => p.name.toLowerCase().contains(query.text.toLowerCase()),
        ))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(playlist.name),
              subtitle: Text(
                '${repository.playlistTracks(playlist, tracks).length} eligible tracks',
              ),
              trailing: const AppIcon(AppIconRole.disclosure),
              onTap: () => playlistPage(playlist),
            ),
          ),
      ];
    }
    if (controller.layout != CatalogLayout.grid) {
      return [
        for (final track in matches)
          trackRow(
            track,
            matches,
            compact: controller.layout == CatalogLayout.compact,
          ),
      ];
    }
    return [
      CollectionLayout(
        layout: controller.layout,
        cardSize: collection?.cardSize ?? 180,
        builder: (context, width, grid, compact) => Wrap(
          spacing: 12,
          runSpacing: 20,
          children: [
            for (final track in matches)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MediaItemSelection(
                      selected: controller.selecting
                          ? controller.selected.contains(track.id)
                          : null,
                      onToggle: () => setState(() => controller.toggle(track)),
                      child: Stack(
                        children: [
                          InkWell(
                            onTap: () => run(() => openTrack(track, matches)),
                            onLongPress: () => setState(() {
                              section = 'Tracks';
                              controller.selecting = true;
                              controller.toggle(track);
                            }),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: MediaCover(cover: track.metadata.cover),
                            ),
                          ),
                          Positioned(top: 0, right: 0, child: trackMenu(track)),
                        ],
                      ),
                    ),
                    const AppGap(8),
                    Text(
                      track.metadata.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.metadata.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Future<void> artistPage(String artist) =>
      NavigationCoordinator.forOwner(widget.library.service.persistenceOwner)
          .run('music:artist:$artist', () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (page) => _MusicProtectedBuilder(
                  library: widget.library,
                  updates: updates,
                  allowed: () => tracks.any(
                    (t) => t.metadata.artist == artist && permitted(t),
                  ),
                  builder: (page, update) => Scaffold(
                    appBar: AppBar(
                      title: Text(artist.isEmpty ? 'Unknown artist' : artist),
                    ),
                    bottomNavigationBar: SessionMiniPlayer(
                      playback: widget.playback,
                    ),
                    body: ListView(
                      padding: AppSpacing.of(context).all(20),
                      children: [
                        for (final track in tracks.where(
                          (t) => t.metadata.artist == artist,
                        ))
                          trackRow(
                            track,
                            tracks
                                .where((t) => t.metadata.artist == artist)
                                .toList(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          });
  List<Widget> workStatus() => [
    if (working ||
        job?.running == true ||
        widget.library.scanning.contains(widget.collectionId)) ...[
      const LinearProgressIndicator(),
      if (widget.collectionId != null &&
          widget.library.scanning.contains(widget.collectionId))
        TextButton(
          onPressed: () => widget.library.cancelScan(widget.collectionId!),
          child: Text(
            'Scanning · ${widget.library.scanProgress[widget.collectionId]?['found'] ?? 0} tracks · Cancel scan',
          ),
        ),
      const AppGap(12),
      if (job?.running == true)
        TextButton(
          onPressed: job!.cancel,
          child: Text('Metadata ${job!.done}/${job!.total} · Cancel'),
        ),
      const AppGap(16),
    ],
  ];

  Widget selectionControls() => Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      Text('${controller.selected.length} selected'),
      TextButton(
        onPressed: () => setState(
          () => controller.selected.addAll(visible.map((t) => t.id)),
        ),
        child: const Text('Select all visible'),
      ),
      TextButton(
        onPressed: () => setState(controller.selected.clear),
        child: const Text('Clear selection'),
      ),
      TextButton(
        onPressed: controller.selected.isEmpty ? null : () => menu('tags'),
        child: const Text('Add tags'),
      ),
      TextButton(
        onPressed: controller.selected.isEmpty ? null : () => menu('playlist'),
        child: const Text('Add to playlist'),
      ),
      TextButton(
        onPressed: () => setState(controller.endSelection),
        child: const Text('Done'),
      ),
    ],
  );
  void clearFilters() {
    genre = '';
    tag = '';
    folder = '';
    availability = 'all';
  }

  bool get filtered =>
      genre.isNotEmpty ||
      tag.isNotEmpty ||
      folder.isNotEmpty ||
      availability != 'all';
  Widget emptyState() => MusicEmptyState(
    title: tracks.isEmpty ? 'No music yet' : 'No matches',
    message: tracks.isEmpty
        ? (widget.collectionId == null
              ? 'Include an unlocked Music collection in this space.'
              : 'Add root folders and scan to find your music.')
        : 'Try another search or clear your filters.',
    action: tracks.isEmpty
        ? (widget.collectionId == null
              ? 'Back to collections'
              : 'Manage folders')
        : 'Clear search and filters',
    onPressed: () => tracks.isEmpty
        ? (widget.collectionId == null
              ? Navigator.pop(context)
              : run(
                  () => recoverCollectionSource(
                    context,
                    widget.collectionId!,
                    authorized: () => repository.access(widget.collectionId!),
                    controller: widget.library,
                  ),
                ))
        : setState(() {
            query.clear();
            clearFilters();
          }),
  );
  Future<void> viewSettings() async {
    final choice = await showCollectionView(
      context,
      layout: controller.layout.name,
      sort: sort,
      sorts: const {
        'title': 'Title',
        'artist': 'Artist',
        'added': 'Recently added',
        'played': 'Last played',
        'year': 'Year',
        'duration': 'Duration',
      },
      cardSize: collection?.cardSize ?? 180,
      descending: descending,
    );
    if (choice == null) return;
    if (widget.collectionId != null) {
      await widget.library.saveBrowsing(widget.collectionId!, {
        'view': choice.layout,
        'cardSize': choice.cardSize,
      });
      await widget.library.load();
    }
    if (mounted) {
      setState(() {
        controller.layout = CatalogLayout.values.byName(choice.layout);
        sort = choice.sort;
        descending = choice.descending;
      });
    }
  }

  Widget searchControl() => Visibility(
    visible: controlsExpanded,
    maintainState: true,
    child: CollectionBrowseToolbar(
      query: query,
      onChanged: (_) => setState(() {}),
      onFilters: filters,
      onView: viewSettings,
      count: visible.length,
      filters: {
        if (genre.isNotEmpty) genre: () => setState(() => genre = ''),
        if (tag.isNotEmpty) tag: () => setState(() => tag = ''),
        if (availability != 'all')
          availability: () => setState(() => availability = 'all'),
        if (folder.isNotEmpty) 'Folder': () => setState(() => folder = ''),
      },
      onClearFilters: () => setState(clearFilters),
    ),
  );
  Widget playlistTile(MusicPlaylist list) {
    final songs = repository.playlistTracks(list, tracks);
    return InkWell(
      onTap: () => playlistPage(list),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (display.artwork)
            AspectRatio(
              aspectRatio: 1,
              child: MediaCover(cover: songs.firstOrNull?.metadata.cover ?? ''),
            ),
          const AppGap(8),
          Text(
            list.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const AppGap(4),
          Text(
            '${songs.length} tracks',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _musicHome(List<MusicAlbum> showcase) {
    final recent = orderedMusicAlbums(
      albums,
      extra,
      history,
      'recent',
    ).take(8).toList();
    final played = orderedMusicAlbums(
      albums
          .where((a) => a.tracks.any((t) => (history[t.id] ?? 0) > 0))
          .toList(),
      extra,
      history,
      'progress',
    ).take(8).toList();
    final quick = <Widget>[
      MusicShortcut(
        title: 'Liked songs',
        icon: AppIconRole.favorite,
        artwork: display.artwork,
        onTap: () => setState(() {
          tab = 2;
          section = 'Tracks';
          availability = 'favorites';
          query.clear();
        }),
      ),
      for (final album in showcase.take(3))
        MusicShortcut(
          title: album.title,
          cover: album.cover,
          artwork: display.artwork,
          onTap: () => albumPage(album),
        ),
      for (final list in playlists.take(2))
        MusicShortcut(
          title: list.name,
          cover:
              repository
                  .playlistTracks(list, tracks)
                  .firstOrNull
                  ?.metadata
                  .cover ??
              '',
          artwork: display.artwork,
          onTap: () => playlistPage(list),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controlsExpanded)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ActionChip(
                label: const Text('Albums'),
                onPressed: () => setState(() {
                  tab = 2;
                  section = 'Albums';
                  clearFilters();
                  query.clear();
                }),
              ),
              ActionChip(
                label: const Text('Playlists'),
                onPressed: () => setState(() {
                  tab = 2;
                  section = 'Playlists';
                  clearFilters();
                  query.clear();
                }),
              ),
              ActionChip(
                label: const Text('Artists'),
                onPressed: () => setState(() {
                  tab = 2;
                  section = 'Artists';
                  clearFilters();
                  query.clear();
                }),
              ),
            ],
          ),
        const AppGap(20),
        Text(
          widget.collectionId == null
              ? 'Your music'
              : collection?.name ?? 'Your music',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const AppGap(16),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth < 300 ? 1 : 2;
            final width = (c.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tile in quick) SizedBox(width: width, child: tile),
              ],
            );
          },
        ),
        const AppGap(16),
        OutlinedButton.icon(
          icon: const AppIcon(AppIconRole.play),
          label: const Text('Continue listening'),
          onPressed: !canResume
              ? null
              : () => run(() async {
                  if (!await widget.playback.restore(scope: scope)) {
                    throw StateError(
                      'No saved Music queue. Pick an album, playlist or track.',
                    );
                  }
                  if (mounted) {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MusicPlayer(playback: widget.playback),
                      ),
                    );
                  }
                }),
        ),
        if (tracks.isEmpty) emptyState(),
        if (played.isNotEmpty)
          MusicRail(
            title: 'Recently played',
            items: [for (final a in played) albumTile(a)],
          ),
        MusicRail(
          title: 'Your playlists',
          action: TextButton(
            onPressed: () => run(createPlaylist),
            child: const Text('Create playlist'),
          ),
          items: [for (final p in playlists.take(8)) playlistTile(p)],
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              icon: const AppIcon(AppIconRole.add),
              label: const Text('Create your first playlist'),
              onPressed: () => run(createPlaylist),
            ),
          ),
        if (recent.isNotEmpty)
          MusicRail(
            title: 'Recently added',
            items: [for (final a in recent) albumTile(a)],
          ),
        const AppGap(24),
      ],
    );
  }

  Widget musicSpaceBody(List<MusicAlbum> showcase) {
    final matches = visible;
    final ids = matches.map((t) => t.id).toSet();
    final groups = albums
        .where((a) => a.tracks.any((t) => ids.contains(t.id)))
        .toList();
    final lists = playlists
        .where((p) => p.name.toLowerCase().contains(query.text.toLowerCase()))
        .toList();
    final artists = matches.map((t) => t.metadata.artist).toSet().toList()
      ..sort();
    final grid = section == 'Albums' || section == 'Tracks';
    final length = section == 'Albums'
        ? groups.length
        : section == 'Tracks'
        ? matches.length
        : section == 'Artists'
        ? artists.length
        : lists.length;
    Widget item(int i) => switch (section) {
      'Albums' => albumTile(groups[i]),
      'Tracks' => trackRow(matches[i], matches),
      'Playlists' => ListTile(
        leading: display.artwork
            ? SizedBox.square(
                dimension: 56,
                child: MediaCover(
                  cover:
                      repository
                          .playlistTracks(lists[i], tracks)
                          .firstOrNull
                          ?.metadata
                          .cover ??
                      '',
                ),
              )
            : null,
        title: Text(lists[i].name),
        subtitle: Text(
          '${repository.playlistTracks(lists[i], tracks).length} tracks',
        ),
        trailing: const AppIcon(AppIconRole.disclosure),
        onTap: () => playlistPage(lists[i]),
      ),
      _ => ListTile(
        title: Text(artists[i].isEmpty ? 'Unknown artist' : artists[i]),
        subtitle: const Text('Artist'),
        onTap: () => artistPage(artists[i]),
      ),
    };
    return RefreshIndicator(
      onRefresh: load,
      child: CustomScrollView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('Retry')),
                  ],
                  ...workStatus(),
                  if (controller.selecting) ...[
                    selectionControls(),
                    const AppGap(16),
                  ],
                  if (tab == 0)
                    _musicHome(showcase)
                  else ...[
                    if (tab == 2)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Your library',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          TextButton.icon(
                            icon: const AppIcon(AppIconRole.add),
                            label: const Text('Create playlist'),
                            onPressed: () => run(createPlaylist),
                          ),
                        ],
                      ),
                    if (controlsExpanded) ...[
                      searchControl(),
                      const AppGap(16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final name in [
                              'Playlists',
                              'Albums',
                              'Tracks',
                              'Artists',
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(name),
                                  selected: section == name,
                                  onSelected: (_) =>
                                      setState(() => section = name),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const AppGap(20),
                    ],
                    if (length == 0)
                      (section == 'Playlists' && query.text.isEmpty
                          ? MusicEmptyState(
                              title: 'Your playlists',
                              message:
                                  'Make a mix from the tracks in this ${scope.local ? 'collection' : 'space'}.',
                              action: 'Create playlist',
                              onPressed: () => run(createPlaylist),
                            )
                          : emptyState()),
                  ],
                ],
              ),
            ),
          ),
          if (tab != 0 && length > 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: grid && display.artwork && section == 'Albums'
                  ? SliverLayoutBuilder(
                      builder: (context, c) {
                        final columns = (c.crossAxisExtent / 180).round().clamp(
                          1,
                          5,
                        );
                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 20,
                                mainAxisExtent:
                                    c.crossAxisExtent / columns +
                                    MediaQuery.textScalerOf(context).scale(54),
                              ),
                          itemCount: length,
                          itemBuilder: (_, i) => item(i),
                        );
                      },
                    )
                  : SliverList.builder(
                      itemCount: length,
                      itemBuilder: (_, i) => item(i),
                    ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    memory.changed();
    final eligibleAlbums = albums
        .where((a) => a.tracks.any((t) => t.available))
        .toList();
    final ordered = orderedMusicAlbums(
      eligibleAlbums,
      extra,
      history,
      display.source,
    );
    final showcase = spaceController.showcase(
      display.source == 'favorites'
          ? ordered.where(
              (a) => a.tracks.any(
                (t) => repository.flags(extra, t.id)['favorite'] == true,
              ),
            )
          : ordered,
      display.pins,
      pinned: display.source == 'pinned',
    );
    final body = Scaffold(
      appBar: AppBar(
        bottom: controller.selecting
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
                  MediaSubtype.music,
                ),
                scope: collection?.name ?? 'All collections',
                overview: widget.space && tab == 0,
                onOverview: () {
                  if (widget.space) {
                    setState(() => tab = 0);
                  } else {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MusicPage(
                          library: widget.library,
                          playback: widget.playback,
                          collectionId: widget.collectionId,
                          space: true,
                        ),
                      ),
                    );
                  }
                },
                onBrowse: () {
                  if (widget.space &&
                      widget.collectionId != null &&
                      Navigator.canPop(context)) {
                    Navigator.maybePop(context);
                  } else if (widget.space) {
                    setState(() => tab = 2);
                  }
                },
              ),

        title: Text(widget.space ? 'Music' : collection?.name ?? 'Music'),
        actions: [
          if (!controller.selecting && collection != null)
            IconButton(
              tooltip: 'Collection settings',
              icon: const AppIcon(AppIconRole.settings),
              onPressed: loading ? null : () => run(settings),
            ),
          CollectionActionsMenu(
            icon: const AppIcon(AppIconRole.menu),
            onSelected: menu,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'createPlaylist',
                child: Text('Create playlist'),
              ),
              if (widget.space)
                const PopupMenuItem(
                  value: 'space-settings',
                  child: Text('Space settings'),
                ),
              if (collection != null) ...[
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Collection settings'),
                ),
                const PopupMenuItem(
                  value: 'player',
                  child: Text('Player settings'),
                ),
                const PopupMenuItem(value: 'tags', child: Text('Manage tags')),
                const PopupMenuItem(
                  value: 'select',
                  child: Text('Select tracks'),
                ),
                const PopupMenuItem(value: 'scan', child: Text('Scan folders')),
                const PopupMenuItem(
                  value: 'bulk',
                  child: Text('Fetch missing metadata'),
                ),
                const PopupMenuItem(
                  value: 'retry',
                  child: Text('Retry failed metadata'),
                ),
                const PopupMenuItem(
                  value: 'jobs',
                  child: Text('Review metadata matches'),
                ),
                const PopupMenuItem(
                  value: 'jobs',
                  child: Text('Metadata job details'),
                ),
                const PopupMenuItem(
                  value: 'health',
                  child: Text('Folder health'),
                ),
              ],
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset browsing'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [SessionMiniPlayer(playback: widget.playback)],
      ),
      body: loading && tracks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : widget.space
          ? musicSpaceBody(showcase)
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                controller: scroll,
                padding: AppSpacing.of(context).all(20),
                children: [
                  if (error != null) ...[
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('Retry')),
                    const AppGap(16),
                  ],
                  ...workStatus(),
                  if (widget
                          .library
                          .warnings[widget.collectionId]
                          ?.isNotEmpty ==
                      true) ...[
                    Text(
                      widget.library.warnings[widget.collectionId]!.join('\n'),
                    ),
                    const AppGap(16),
                  ],
                  if (controller.selecting) ...[
                    selectionControls(),
                    const AppGap(16),
                  ],
                  if (controlsExpanded) ...[
                    searchControl(),
                    const AppGap(16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final value in [
                            'Albums',
                            'Tracks',
                            'Artists',
                            'Playlists',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(value),
                                selected: section == value,
                                onSelected: (_) =>
                                    setState(() => section = value),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const AppGap(20),
                  ],
                  if (tracks.isEmpty || visible.isEmpty) emptyState(),
                  ...browsing(),
                ],
              ),
            ),
    );
    return widget.space
        ? SpaceExitGuard(
            preferences: preferences,
            videos: false,
            display: display,
            name: 'Music',
            exitMessage: widget.collectionId != null
                ? 'Return to this collection?'
                : null,
            child: body,
          )
        : body;
  }
}

class _MusicProtectedBuilder extends StatelessWidget {
  const _MusicProtectedBuilder({
    required this.library,
    required this.updates,
    required this.allowed,
    required this.builder,
  });
  final LibraryController library;
  final ValueNotifier<int> updates;
  final bool Function() allowed;
  final StatefulWidgetBuilder builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([library, updates]),
    builder: (context, _) => allowed()
        ? StatefulBuilder(builder: builder)
        : Scaffold(
            appBar: AppBar(title: const Text('Music')),
            body: const Center(
              child: Text('This content is no longer available in this scope.'),
            ),
          ),
  );
}
