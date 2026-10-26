import 'media_ui_patterns.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'media_cover.dart';

class MusicShortcut extends StatelessWidget {
  const MusicShortcut({
    super.key,
    required this.title,
    required this.onTap,
    this.cover = '',
    this.icon = AppIconRole.music,
    this.artwork = true,
  });
  final String title, cover;
  final VoidCallback onTap;
  final AppIconRole icon;
  final bool artwork;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (artwork) ...[
              SizedBox.square(
                dimension: 48,
                child: cover.isEmpty
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: AppIcon(icon),
                      )
                    : MediaCover(cover: cover),
              ),
              const AppGap.horizontal(10),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MusicRail extends StatelessWidget {
  const MusicRail({
    super.key,
    required this.title,
    required this.items,
    this.action,
  });
  final String title;
  final List<Widget> items;
  final Widget? action;
  @override
  Widget build(BuildContext context) =>
      MediaRail(title: title, items: items, action: action);
}

class MusicEmptyState extends StatelessWidget {
  const MusicEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });
  final String title, message, action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const AppGap(10),
        Text(message),
        const AppGap(16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(onPressed: onPressed, child: Text(action)),
        ),
      ],
    ),
  );
}
