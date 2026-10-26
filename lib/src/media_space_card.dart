import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

/// Shared showcase geometry for all media spaces; video retains its existing layout.
class MediaSpaceCard extends StatelessWidget {
  const MediaSpaceCard({
    super.key,
    required this.title,
    required this.icon,
    required this.artwork,
    required this.counts,
    required this.emptyHint,
    required this.onOpen,
    this.showArtwork = true,
    this.showCounts = true,
    this.squareArtwork = false,
  });
  final String title, emptyHint;
  final AppIconRole icon;
  final List<Widget> artwork;
  final List<String> counts;
  final VoidCallback? onOpen;
  final bool showArtwork, showCounts, squareArtwork;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final picture = Stack(
      fit: StackFit.expand,
      children: [
        if (artwork.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < artwork.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == artwork.length - 1 ? 0 : 4,
                    ),
                    child: artwork[i],
                  ),
                ),
            ],
          )
        else
          ColoredBox(
            color: colors.primaryContainer,
            child: Center(
              child: AppIcon(icon, size: 72, color: colors.onPrimaryContainer),
            ),
          ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, colors.surfaceContainerLow],
                stops: const [.55, 1],
              ),
            ),
          ),
        ),
      ],
    );
    return Container(
      foregroundDecoration: ShapeDecoration(
        shape: interfaceShape(
          context,
          radius: 28,
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      decoration: ShapeDecoration(
        color: colors.surfaceContainerLow,
        shape: interfaceShape(
          context,
          radius: 28,
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: InterfaceClip(
        radius: 28,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showArtwork)
              squareArtwork
                  ? AspectRatio(
                      aspectRatio: artwork.isEmpty
                          ? 3
                          : artwork.length.toDouble(),
                      child: picture,
                    )
                  : SizedBox(height: 210, child: picture),
            Padding(
              padding: EdgeInsets.fromLTRB(24, showArtwork ? 0 : 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const AppGap(8),
                  if (showCounts && onOpen != null)
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        for (final count in counts)
                          Text(
                            count,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                      ],
                    )
                  else if (onOpen == null)
                    Text(
                      emptyHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const AppGap(24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text('Open $title')),
                          const AppIcon(AppIconRole.forward, size: 20),
                        ],
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
}
