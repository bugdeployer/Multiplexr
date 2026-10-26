import '../experience/collection/collection_experience.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'media_cover.dart';

class AudiobookCover extends MediaCover {
  const AudiobookCover({super.key, required super.cover})
    : super(fallbackIcon: AppIconRole.reading);
}

/// Collections and series use the same square, artwork-only tile.
class AudiobookArtworkTile extends StatelessWidget {
  const AudiobookArtworkTile({
    super.key,
    required this.title,
    required this.cover,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.menu,
  });
  final String title, cover;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool? selected;
  final Widget? menu;
  @override
  Widget build(BuildContext context) => Semantics(
    label: title,
    button: true,
    selected: selected,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: MediaItemSelection(
        selected: selected,
        onToggle: onTap,
        child: InterfaceClip(
          radius: 18,
          child: AspectRatio(
            aspectRatio: 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AudiobookCover(cover: cover),
                    if (menu != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Material(
                          color: Colors.transparent,
                          child: menu!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
