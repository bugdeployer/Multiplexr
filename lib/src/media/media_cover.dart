import 'dart:convert';

import 'artwork_images.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

/// Stable image providers avoid decoding/flashing on playback position updates.
class MediaCover extends StatefulWidget {
  const MediaCover({
    super.key,
    required this.cover,
    this.fallbackIcon = AppIconRole.music,
    this.placeholder,
  });
  final String cover;
  final AppIconRole fallbackIcon;
  final WidgetBuilder? placeholder;
  @override
  State<MediaCover> createState() => _MediaCoverState();
}

class _MediaCoverState extends State<MediaCover> {
  ImageProvider? provider;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    provider = decode(widget.cover);
  }

  ImageProvider? decode(String cover) {
    try {
      if (cover.startsWith('data:image/')) {
        return MemoryImage(
          base64Decode(cover.substring(cover.indexOf(',') + 1)),
        );
      }
      if (cover.startsWith('https://')) return NetworkImage(cover);
      if (cover.isNotEmpty && !cover.contains('://')) {
        return ArtworkImages.localImage(context, cover);
      }
    } catch (_) {
      /* Damaged covers use a fallback. */
    }
    return null;
  }

  @override
  void didUpdateWidget(MediaCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) provider = decode(widget.cover);
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() =>
        widget.placeholder?.call(context) ??
        ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(child: AppIcon(widget.fallbackIcon, size: 40)),
        );
    return InterfaceClip(
      child: provider == null
          ? fallback()
          : Image(
              image: provider!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, error, stack) => fallback(),
            ),
    );
  }
}
