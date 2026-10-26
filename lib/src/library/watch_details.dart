import '../experience/plugins/plugin_contribution_page.dart';
import '../features/catalog/application/extension_catalog.dart';

import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'video_art.dart';
import 'queue_view.dart';
import 'video_scope.dart';

class WatchDetails extends StatefulWidget {
  const WatchDetails({
    super.key,
    required this.asset,
    required this.related,
    required this.onSelect,
    this.onWatchAction,
    this.library,
    this.openSource,
    this.queueItems,
  });
  final LibraryController? library;
  final Future<void> Function()? openSource;
  final List<VideoAsset> Function()? queueItems;
  final Future<void> Function(String)? onWatchAction;
  final VideoAsset asset;
  final List<VideoAsset> related;
  final void Function(VideoAsset) onSelect;
  @override
  State<WatchDetails> createState() => _WatchDetailsState();
}

class _WatchDetailsState extends State<WatchDetails> {
  bool expanded = false;
  VideoAsset get asset => widget.asset;
  List<VideoAsset> get related => widget.related;
  void Function(VideoAsset) get onSelect => widget.onSelect;
  Future<void> Function(String)? get onWatchAction => widget.onWatchAction;
  @override
  Widget build(BuildContext context) => ListView(
    padding: AppSpacing.of(context).all(20),
    children: [
      PluginDetailExtensions(
        collection: asset.collectionId,
        kind: asset.mediaSubtype == VideoSubtype.tv
            ? ExtensionMedia.television
            : asset.mediaSubtype == VideoSubtype.videos
            ? ExtensionMedia.video
            : ExtensionMedia.movie,
        titleId: asset.id,
      ),
      Text(
        asset.title,
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const AppGap(8),
      Text(
        [
          asset.metadata['year'],
          asset.metadata['series'],
          asset.metadata['genres'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (onWatchAction != null)
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () =>
                  onWatchAction!(asset.watched ? 'unwatched' : 'watched'),
              icon: AppIcon(
                asset.watched ? AppIconRole.success : AppIconRole.success,
              ),
              label: Text(asset.watched ? 'Watched' : 'Mark watched'),
            ),
            TextButton(
              onPressed: () => onWatchAction!('restart'),
              child: const Text('Play from beginning'),
            ),
            if (asset.inProgress)
              TextButton(
                onPressed: () => onWatchAction!('hide'),
                child: const Text('Remove from Continue watching'),
              ),
          ],
        ),
      if (widget.library != null)
        Row(
          children: [
            TextButton.icon(
              onPressed: () => showVideoQueue(
                context,
                widget.library!,
                onSelect,
                items: widget.queueItems,
              ),
              icon: const AppIcon(AppIconRole.playlistAdd),
              label: Text(
                'Queue · ${(widget.queueItems?.call() ?? widget.library!.queuedVideos).length}',
              ),
            ),
            const Spacer(),
            VideoActions(asset: asset, library: widget.library!),
          ],
        ),
      if (widget.openSource != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.openSource,
            icon: const AppIcon(AppIconRole.folderOpen),
            label: const Text('Open source collection'),
          ),
        ),
      const AppGap(16),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: AppSpacing.of(context).all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((asset.metadata['description'] ?? '').isNotEmpty)
                Text(
                  asset.metadata['description']!,
                  style: const TextStyle(height: 1.5),
                  maxLines: expanded ? null : 3,
                  overflow: expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                ),
              if ((asset.metadata['description'] ?? '').isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? 'Show less' : 'Show more'),
                ),
              const AppGap(8),
              Text(
                asset.filename,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              for (final field in {
                'director': 'Director',
                'cast': 'Cast',
                'tags': 'Tags',
              }.entries)
                if ((asset.metadata[field.key] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${field.value}: ${asset.metadata[field.key]}'),
                  ),
            ],
          ),
        ),
      ),
      if (related.any(
        (a) => a.id != asset.id || a.collectionId != asset.collectionId,
      )) ...[
        const AppGap(28),
        Text('More videos', style: Theme.of(context).textTheme.titleMedium),
        const AppGap(16),
        for (final video in related.where(
          (a) => a.id != asset.id || a.collectionId != asset.collectionId,
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VideoFeedCard(
                  asset: video,
                  onTap: () => onSelect(video),
                  source: widget.library == null
                      ? null
                      : videoFolderLabel(
                          video,
                          widget.library!,
                          global: widget.openSource != null,
                        ),
                  trailing: widget.library == null
                      ? null
                      : VideoActions(asset: video, library: widget.library!),
                ),
              ],
            ),
          ),
      ],
    ],
  );
}
