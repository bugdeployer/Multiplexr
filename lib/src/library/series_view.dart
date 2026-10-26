import '../features/catalog/application/series_groups.dart';

import 'metadata_search_page.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../metadata/metadata_review_page.dart';
import '../experience/actions/catalog_actions.dart';
import '../experience/actions/media_actions.dart';
import '../catalog/domain/classification.dart';
import '../media/media_ui_patterns.dart';
import 'series_management.dart';
import '../media/grouping.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'series.dart';
import 'video_art.dart';

Future<VideoAsset?> chooseVersion(
  BuildContext context,
  EpisodeRecord episode,
) async {
  final available = episode.versions.where((a) => a.available).toList();
  if (available.isEmpty) return null;
  if (available.length == 1) return available.single;
  return showModalBottomSheet<VideoAsset>(
    context: context,
    useSafeArea: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      padding: AppSpacing.of(context).all(24),
      children: [
        Text('Choose a version', style: Theme.of(context).textTheme.titleLarge),
        for (final a in available)
          ListTile(
            leading: const AppIcon(AppIconRole.videoFile),
            title: Text(a.filename),
            subtitle: Text(
              '${a.relativePath.isEmpty ? a.filename : a.relativePath}${a.width > 0 ? '\n${a.width} × ${a.height}' : ''}',
            ),
            onTap: () => Navigator.pop(context, a),
          ),
      ],
    ),
  );
}

class SeriesDetails extends StatefulWidget {
  const SeriesDetails({
    super.key,
    required this.library,
    required this.series,
    required this.play,
    this.editEpisode,
    this.matchEpisode,
  });
  final LibraryController library;
  final SeriesRecord series;
  final Future<void> Function(VideoAsset, bool) play;
  final Future<void> Function(VideoAsset)? editEpisode, matchEpisode;
  @override
  State<SeriesDetails> createState() => _SeriesDetailsState();
}

class _SeriesDetailsState extends State<SeriesDetails> {
  int? season;
  bool busy = false;
  late final lookupJob = widget.library.metadataJobs.series(widget.series);
  bool get cancelMatching => lookupJob.cancelled;
  int get matchedCount => lookupJob.done;
  int get matchCount => lookupJob.total;
  String? error;
  SeriesRecord get current {
    final all = buildSeries(
      widget.library.items(widget.series.assets.first.collectionId),
    );
    return all
            .where(
              (s) => s.assets.any((a) => a.id == widget.series.assets.first.id),
            )
            .firstOrNull ??
        all.where((s) => s.id == widget.series.id).firstOrNull ??
        widget.series;
  }

  @override
  void initState() {
    super.initState();
    lookupJob.addListener(refresh);
    widget.library.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    lookupJob.removeListener(refresh);
    widget.library.removeListener(refresh);
    super.dispose();
  }

  Future<void> perform(Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not finish this action. Your existing files and history are preserved.',
        );
      }
    }
  }

  Future<void> start(EpisodeRecord episode, {bool external = false}) async {
    final asset = await chooseVersion(context, episode);
    if (asset != null && mounted) {
      await perform(() => widget.play(asset, external));
    }
  }

  Future<void> matchSeries() async {
    if (!current.assets.any(identifiedEpisode)) {
      setState(
        () => error = 'Set a series name, season and episode number with Correct episode first.',
      );
      return;
    }
    final snapshot = current;
    final saved = await lookupJob.recover();
    if (!mounted) return;
    var resume = false;
    if ((saved?['remaining'] as List? ?? []).isNotEmpty) {
      final resumeChoice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Resume series metadata?'),
          content: const Text(
            'Continue the saved match using its selected fields and remaining episodes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('New search'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (!mounted || resumeChoice == null) return;
      resume = resumeChoice;
    }
    final MetadataCandidate? candidate = resume
        ? MetadataCandidate.fromJson(
            Map<String, dynamic>.from(saved!['candidate'] as Map),
          )
        : await Navigator.push<MetadataCandidate>(
            context,
            MaterialPageRoute(
              builder: (_) => VideoMetadataSearchPage(
                library: widget.library,
                asset: snapshot.assets.first,
                query: snapshot.needsIdentification ? '' : snapshot.name,
                selectOnly: true,
              ),
            ),
          );
    if (candidate == null || !mounted) return;
    final Set<String>? fields = resume
        ? Set<String>.from(saved!['fields'])
        : await Navigator.push<Set<String>>(
            context,
            MaterialPageRoute(
              builder: (_) => MetadataReviewPage(
                target: lookupJob.target(
                  snapshot.assets.firstWhere(identifiedEpisode),
                ),
                candidate: candidate,
                title: 'Review series match',
                selectOnly: true,
              ),
            ),
          );
    if (fields == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await lookupJob.run(candidate, fields, resume: resume);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Series matching stopped. Saved matches are preserved; identify episode numbers and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = current;
    final seasons = series.seasons;
    final resumeSeason = series.resume == null
        ? null
        : seasonNumber(series.resume!);
    season = seasons.any((s) => s.number == season)
        ? season
        : seasons.any((s) => s.number == resumeSeason)
        ? resumeSeason
        : (seasons.where((s) => s.number != 0).firstOrNull ??
                  seasons.firstOrNull)
              ?.number;
    final episodes = series.needsIdentification
        ? series.episodes
        : series.episodes
              .where((e) => e.season == season || e.number == null)
              .toList();
    final numbers = episodes
        .where((e) => e.number != null)
        .map((e) => e.number!)
        .toSet();
    final localMax = numbers.isEmpty
        ? 0
        : numbers.reduce((a, b) => a > b ? a : b);
    final knownCounts = series.assets
        .where((a) => seasonNumber(a) == season)
        .map((a) => int.tryParse(a.metadata['seasonEpisodeCount'] ?? '') ?? 0)
        .toList();
    final expected = knownCounts.fold<int>(localMax, (a, b) => a > b ? a : b);
    final missing = expected > 500
        ? <int>[]
        : [
            for (var n = 1; n <= expected; n++)
              if (!numbers.contains(n)) n,
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(series.name),
        actions: [
          PopupMenuButton<String>(
            icon: const AppIcon(AppIconRole.menu),
            tooltip: 'Series actions',
            onSelected: (action) async {
              if (!CatalogActionRegistry.permitted(
                CatalogActionScope.group,
                action,
                MediaActionContext(
                  authorized: widget.library.canAccessCollection(
                    series.assets.first.collectionId,
                  ),
                  capabilities: appSubtypes
                      .definition(MediaSubtype.moviesTv)
                      .capabilities,
                ),
              )) {
                return;
              }
              if (action == 'group') {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SeriesGroupingPage(
                      library: widget.library,
                      collectionId: series.assets.first.collectionId,
                    ),
                  ),
                );
              } else {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupOrderPage<EpisodeRecord>(
                      title: 'Episode order',
                      items: series.episodes,
                      identity: (e) => e.id,
                      label: (e) => e.asset.title,
                      save: (ordered) async {
                        await widget.library
                            .seriesGroups(series.assets.first.collectionId)
                            .reorderSeries(
                              seriesGroupIdentity(series),
                              ordered.map(episodeTitleIdentity).toList(),
                            );
                      },
                    ),
                  ),
                );
              }
              if (mounted) setState(() {});
            },
            itemBuilder: (_) => catalogActionMenu(
              const [
                PopupMenuItem(
                  value: 'group',
                  child: Text('Manage series grouping'),
                ),
                PopupMenuItem(value: 'order', child: Text('Reorder episodes')),
              ],
              scope: CatalogActionScope.group,
              context: MediaActionContext(
                authorized: widget.library.canAccessCollection(
                  series.assets.first.collectionId,
                ),
                capabilities: appSubtypes
                    .definition(MediaSubtype.moviesTv)
                    .capabilities,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Match series online',
            onPressed: busy ? null : () => perform(matchSeries),
            icon: const AppIcon(AppIconRole.metadata),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (!series.needsIdentification)
            InterfaceClip(
              radius: 24,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoArtwork(asset: series.artwork),
              ),
            ),
          const AppGap(20),
          Text(series.name, style: Theme.of(context).textTheme.headlineMedium),
          Text(series.summary),
          if ((series.artwork.metadata['genres'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(series.artwork.metadata['genres']!),
            ),
          if (series.overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(series.overview, style: const TextStyle(height: 1.5)),
            ),
          if (series.resume != null && !series.needsIdentification)
            FilledButton.icon(
              onPressed: () => start(
                series.episodes.firstWhere(
                  (e) => e.versions.any((a) => a.id == series.resume!.id),
                ),
              ),
              icon: const AppIcon(AppIconRole.play),
              label: Text(
                series.resume!.inProgress
                    ? 'Resume S${seasonNumber(series.resume!)} · E${episodeNumber(series.resume!)}'
                    : 'Play S${seasonNumber(series.resume!)} · E${episodeNumber(series.resume!)}',
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => perform(
                  () => widget.library.flags(
                    series.assets,
                    'favorite',
                    !series.assets.any((a) => a.favorite),
                  ),
                ),
                icon: AppIcon(
                  series.assets.any((a) => a.favorite)
                      ? AppIconRole.favoriteSelected
                      : AppIconRole.favorite,
                ),
                label: const Text('Favorite'),
              ),
              TextButton.icon(
                onPressed: () => perform(
                  () => widget.library.flags(
                    series.assets,
                    'watchLater',
                    !series.assets.any((a) => a.watchLater),
                  ),
                ),
                icon: AppIcon(
                  series.assets.any((a) => a.watchLater)
                      ? AppIconRole.bookmarkSelected
                      : AppIconRole.bookmark,
                ),
                label: const Text('Watch later'),
              ),
            ],
          ),
          if (series.assets.any(
            (a) => a.lastPlayedAt > 0 && !a.hiddenFromContinue,
          ))
            TextButton(
              onPressed: () => perform(
                () => widget.library.flags(series.assets, 'hideContinue', true),
              ),
              child: const Text('Remove from Continue watching'),
            ),
          if (busy) ...[
            LinearProgressIndicator(
              value: matchCount > 0 ? matchedCount / matchCount : null,
            ),
            Text(
              'Matching series · $matchedCount / $matchCount · batch ${matchedCount ~/ 20 + 1}',
            ),
            TextButton(
              onPressed: () {
                lookupJob.cancel();
              },
              child: Text(
                cancelMatching
                    ? 'Finishing current request…'
                    : 'Cancel matching',
              ),
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (series.needsIdentification)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Set a series name, season, and episode number to organize these files.',
              ),
            ),
          if (seasons.isNotEmpty && !series.needsIdentification)
            DropdownButtonFormField<int>(
              icon: const AppIcon(AppIconRole.expand),
              key: ValueKey('${series.id}:$season'),
              initialValue: season,
              decoration: const InputDecoration(labelText: 'Season'),
              items: [
                for (final s in seasons)
                  DropdownMenuItem(value: s.number, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => season = v),
            ),
          if (missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Not on this device: ${missing.length > 12 ? '${missing.length} episodes' : missing.map((n) => 'E$n').join(', ')}',
              ),
            ),
          const AppGap(16),
          for (final episode in episodes)
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: SizedBox(
                  width: 86,
                  height: 56,
                  child: InterfaceClip(
                    radius: 8,
                    child: VideoArtwork(asset: episode.asset),
                  ),
                ),
                title: Text(
                  '${episode.number == null ? '?' : '${episode.number}.'} ${episode.asset.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (episode.watched) 'Watched',
                    if (episode.asset.inProgress) 'In progress',
                    if (!episode.available) 'Unavailable',
                    if (episode.versions.length > 1)
                      '${episode.versions.length} versions',
                    if (episode.asset.durationMs > 0)
                      '${(episode.asset.durationMs / 60000).ceil()} min',
                  ].join(' · '),
                ),
                childrenPadding: const EdgeInsets.all(16),
                children: [
                  if ((episode.asset.metadata['description'] ?? '').isNotEmpty)
                    Text(episode.asset.metadata['description']!),
                  if (episode.asset.durationMs > 0)
                    LinearProgressIndicator(
                      value:
                          (episode.asset.positionMs / episode.asset.durationMs)
                              .clamp(0, 1),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: episode.available
                            ? () => start(episode)
                            : null,
                        icon: const AppIcon(AppIconRole.play),
                        label: Text(
                          episode.asset.inProgress ? 'Resume' : 'Play',
                        ),
                      ),
                      TextButton(
                        onPressed: episode.available
                            ? () => start(episode, external: true)
                            : null,
                        child: const Text('External player'),
                      ),
                      TextButton(
                        onPressed: () => perform(
                          () => widget.library.flags(
                            episode.versions,
                            'watched',
                            !episode.watched,
                          ),
                        ),
                        child: Text(
                          episode.watched ? 'Mark unwatched' : 'Mark watched',
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SeriesGroupingPage(
                              library: widget.library,
                              collectionId: episode.asset.collectionId,
                              initial: episode.asset.id,
                            ),
                          ),
                        ),
                        child: const Text('Move / ungroup episode'),
                      ),
                      if (widget.editEpisode != null)
                        TextButton(
                          onPressed: () => widget.editEpisode!(episode.asset),
                          child: const Text('Correct episode'),
                        ),
                      if (widget.matchEpisode != null)
                        TextButton(
                          onPressed: () => widget.matchEpisode!(episode.asset),
                          child: const Text('Find metadata'),
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
