import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

/// Equal action cells with a real divider; stacks when text or width needs it.
class AudioControlPair extends StatelessWidget {
  const AudioControlPair({
    super.key,
    required this.first,
    required this.second,
  });
  final Widget first, second;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      Widget cell(Widget child) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: DefaultTextStyle.merge(
          textAlign: TextAlign.center,
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
      if (bounds.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [cell(first), const Divider(height: 1), cell(second)],
        );
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: cell(first)),
            const VerticalDivider(width: 1),
            Expanded(child: cell(second)),
          ],
        ),
      );
    },
  );
}

class AudioChapterTile extends StatelessWidget {
  const AudioChapterTile({
    super.key,
    required this.number,
    required this.title,
    required this.duration,
    required this.selected,
    required this.playing,
    this.onTap,
  });
  final int number;
  final String title, duration;
  final bool selected, playing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = Theme.of(context).cardTheme.shape;
    final border = BorderSide(
      color: selected ? colors.primary : colors.outlineVariant,
      width: selected ? 2 : 1,
    );
    final shape = base is OutlinedBorder
        ? base.copyWith(side: border)
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: border,
          );
    return Card(
      margin: EdgeInsets.zero,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      color: selected ? colors.primaryContainer : null,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minVerticalPadding: 12,
        selected: selected,
        selectedColor: colors.onPrimaryContainer,
        leading: SizedBox(width: 32, child: Center(child: Text('$number'))),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(duration),
        ),
        trailing: selected
            ? AppIcon(
                playing ? AppIconRole.play : AppIconRole.pause,
                semanticLabel: playing ? 'Playing' : 'Current chapter',
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
