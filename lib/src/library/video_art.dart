import 'dart:convert';

import '../media/artwork_images.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'library_models.dart';

class VideoArtwork extends StatelessWidget {
  const VideoArtwork({
    super.key,
    required this.asset,
    this.posterFirst = false,
  });
  final VideoAsset asset;
  final bool posterFirst;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: AppIcon(
          AppIconRole.play,
          size: 42,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
    Widget image(String? local, String? remote, Widget Function() fallback) {
      if (remote?.startsWith('data:image/') == true) {
        try {
          return Image.memory(
            base64Decode(remote!.substring(remote.indexOf(',') + 1)),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback(),
          );
        } catch (_) {
          return fallback();
        }
      }
      Widget online() => remote == null
          ? fallback()
          : Image.network(
              remote,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            );
      final provider = local == null
          ? null
          : ArtworkImages.localImage(context, local);
      return provider == null
          ? online()
          : Image(
              image: provider,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => online(),
            );
    }

    Widget poster() => image(asset.localPoster, asset.poster, fallback);
    Widget thumbnail() => image(asset.thumbnail, null, poster);
    return posterFirst
        ? image(asset.localPoster, asset.poster, thumbnail)
        : image(asset.localBackdrop, asset.backdrop, thumbnail);
  }
}

String feedDuration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final minutes = seconds ~/ 60;
  return seconds >= 3600
      ? '${seconds ~/ 3600}:${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
      : '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

class VideoFeedCard extends StatelessWidget {
  const VideoFeedCard({
    super.key,
    required this.asset,
    required this.onTap,
    this.source,
    this.trailing,
  });
  final VideoAsset asset;
  final VoidCallback onTap;
  final String? source;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final added = asset.addedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(asset.addedAt).toLocal()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: interfaceRadius(context, 18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: InterfaceClip(
              radius: 18,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoArtwork(asset: asset),
                  if (!asset.available)
                    ColoredBox(
                      color: Colors.black54,
                      child: const Center(
                        child: Text(
                          'Unavailable',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  if (asset.durationMs > 0)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .85),
                          borderRadius: interfaceRadius(context, 5),
                        ),
                        child: Text(
                          feedDuration(asset.durationMs),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (asset.watched)
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: AppIcon(
                            AppIconRole.confirm,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (asset.durationMs > 0 && asset.positionMs > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: (asset.positionMs / asset.durationMs).clamp(
                          0,
                          1,
                        ),
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 10),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const AppIcon(AppIconRole.folder, size: 19),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const AppGap(4),
                      Text(
                        [
                          source ?? asset.filename,
                          if (added != null)
                            'Added ${added.day}/${added.month}/${added.year}',
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}
