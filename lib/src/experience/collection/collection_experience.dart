import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

/// Progressive disclosure for the existing, capability-checked action lists.
class CollectionActionsMenu extends StatelessWidget {
  const CollectionActionsMenu({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.enabled = true,
    this.icon,
    this.tooltip = 'Collection actions',
  });
  final PopupMenuItemBuilder<String> itemBuilder;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final Widget? icon;
  final String tooltip;

  String group(String value) {
    if (['select', 'selectItems'].contains(value)) return 'select';
    if ([
      'settings',
      'collectionSettings',
      'player',
      'playerSettings',
      'readerSettings',
      'space-settings',
    ].contains(value)) {
      return 'settings';
    }
    if ([
      'jobs',
      'metadataJob',
      'reviewMetadata',
      'retryMetadata',
      'retry',
      'reviewJobs',
      'job',
      'activity',
    ].contains(value)) {
      return 'activity';
    }
    return 'manage';
  }

  @override
  Widget build(BuildContext context) {
    final entries = itemBuilder(context)
        .whereType<PopupMenuItem<String>>()
        .toList();
    final selection = entries.any(
      (e) => ['selectAll', 'clearSelection', 'tagSelected'].contains(e.value),
    );
    return PopupMenuButton<String>(
      enabled: enabled,
      icon: icon ?? const AppIcon(AppIconRole.menu),
      tooltip: tooltip,
      itemBuilder: (_) => selection
          ? entries
          : [
              if (entries.any((e) => group(e.value ?? '') == 'select'))
                const PopupMenuItem(
                  value: 'select',
                  child: Text('Select items'),
                ),
              if (entries.any((e) => group(e.value ?? '') == 'manage'))
                const PopupMenuItem(
                  value: 'manage',
                  child: Text('Manage collection'),
                ),
              if (entries.any((e) => group(e.value ?? '') == 'activity'))
                const PopupMenuItem(value: 'activity', child: Text('Activity')),
              if (entries.any((e) => group(e.value ?? '') == 'settings'))
                const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
      onSelected: (value) async {
        if (selection) {
          onSelected(value);
          return;
        }
        final choices = entries
            .where((e) => group(e.value ?? '') == value)
            .toList();
        if (choices.length == 1) {
          if (choices.single.enabled) onSelected(choices.single.value!);
          return;
        }
        final action = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          builder: (sheet) => ListView(
            shrinkWrap: true,
            padding: AppSpacing.of(context).all(20),
            children: [
              Text(
                value == 'manage'
                    ? 'Manage collection'
                    : value == 'activity'
                    ? 'Activity'
                    : 'Settings',
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              const AppGap(12),
              for (final entry in choices)
                ListTile(
                  enabled: entry.enabled,
                  title: entry.child,
                  onTap: entry.enabled
                      ? () => Navigator.pop(sheet, entry.value)
                      : null,
                ),
            ],
          ),
        );
        if (action != null && context.mounted) onSelected(action);
      },
    );
  }
}

/// One navigation vocabulary for local collections and aggregate Spaces.
class CollectionExperienceHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const CollectionExperienceHeader({
    super.key,
    required this.scope,
    required this.expanded,
    required this.onExpanded,
    required this.overview,
    required this.onOverview,
    required this.onBrowse,
    this.onScope,
  });
  final bool expanded;
  final VoidCallback onExpanded;
  final String scope;
  final bool overview;
  final VoidCallback onOverview, onBrowse;
  final VoidCallback? onScope;
  @override
  Size get preferredSize => Size.fromHeight(expanded ? 112 : 60);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!expanded)
          SizedBox(
            height: 48,
            child: Semantics(
              expanded: expanded,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  textStyle: Theme.of(context).textTheme.labelLarge,
                ),
                onPressed: onExpanded,
                icon: RotatedBox(
                  quarterTurns: expanded ? 2 : 0,
                  child: const AppIcon(AppIconRole.expand, size: 18),
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    expanded
                        ? 'Hide space controls'
                        : '${overview ? 'Overview' : 'Browse'} & filters',
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
        if (expanded) ...[
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onScope,
                      icon: AppIcon(
                        onScope == null
                            ? AppIconRole.folder
                            : AppIconRole.expand,
                        size: 18,
                      ),
                      label: Text(
                        'Scope: $scope',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide space controls',
                onPressed: onExpanded,
                icon: const RotatedBox(
                  quarterTurns: 2,
                  child: AppIcon(AppIconRole.expand),
                ),
              ),
            ],
          ),
          SegmentedButton<bool>(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(48, 48)),
            ),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: true,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Overview', maxLines: 1),
                ),
              ),
              ButtonSegment(
                value: false,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Browse', maxLines: 1),
                ),
              ),
            ],
            selected: {overview},
            onSelectionChanged: (value) =>
                value.single ? onOverview() : onBrowse(),
          ),
        ],
      ],
    ),
  );
}

/// Separate content discovery from presentation preferences on every subtype.
class CollectionBrowseToolbar extends StatelessWidget {
  const CollectionBrowseToolbar({
    super.key,
    required this.query,
    required this.onChanged,
    required this.onFilters,
    required this.onView,
    this.count,
    this.filters = const {},
    this.onClearFilters,
  });
  final TextEditingController query;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilters, onView;
  final int? count;
  final Map<String, VoidCallback> filters;
  final VoidCallback? onClearFilters;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: query,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search collection',
          prefixIcon: const AppIcon(AppIconRole.search),
          suffixIcon: query.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const AppIcon(AppIconRole.close),
                  onPressed: () {
                    query.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
      const AppGap(8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          if (count != null)
            Text(
              '$count ${count == 1 ? 'result' : 'results'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: onFilters,
                icon: const AppIcon(AppIconRole.filter),
                label: Text(
                  filters.isEmpty ? 'Filters' : 'Filters (${filters.length})',
                ),
              ),
              TextButton.icon(
                onPressed: onView,
                icon: const AppIcon(AppIconRole.library),
                label: const Text('View'),
              ),
            ],
          ),
        ],
      ),
      if (filters.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final filter in filters.entries)
              InputChip(label: Text(filter.key), onDeleted: filter.value),
            if (onClearFilters != null)
              TextButton(
                onPressed: onClearFilters,
                child: const Text('Clear filters'),
              ),
          ],
        ),
    ],
  );
}

class CollectionViewChoice {
  const CollectionViewChoice(
    this.layout,
    this.sort,
    this.cardSize,
    this.descending,
  );
  final String layout, sort;
  final double cardSize;
  final bool descending;
}

Future<CollectionViewChoice?> showCollectionView(
  BuildContext context, {
  required String layout,
  required String sort,
  required Map<String, String> sorts,
  double cardSize = 180,
  bool descending = false,
  bool allowDirection = true,
}) => showModalBottomSheet<CollectionViewChoice>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (sheet) => StatefulBuilder(
    builder: (_, update) => SingleChildScrollView(
      padding: AppSpacing.of(context).all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('View', style: Theme.of(sheet).textTheme.titleLarge),
          const AppGap(20),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'grid',
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Grid', maxLines: 1),
                ),
              ),
              ButtonSegment(
                value: 'list',
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('List', maxLines: 1),
                ),
              ),
              ButtonSegment(
                value: 'compact',
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Compact list', maxLines: 1),
                ),
              ),
            ],
            selected: {layout},
            onSelectionChanged: (values) =>
                update(() => layout = values.single),
          ),
          const AppGap(20),
          DropdownButtonFormField<String>(
            initialValue: sorts.containsKey(sort) ? sort : sorts.keys.first,
            decoration: const InputDecoration(labelText: 'Sort by'),
            items: [
              for (final e in sorts.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => update(() => sort = v!),
          ),
          if (allowDirection)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reverse sort order'),
              value: descending,
              onChanged: (v) => update(() => descending = v),
            ),
          if (layout == 'grid') ...[
            const AppGap(12),
            const Text('Artwork size'),
            Slider(
              value: cardSize.clamp(120, 280),
              min: 120,
              max: 280,
              divisions: 8,
              label: '${cardSize.round()}',
              onChanged: (v) => update(() => cardSize = v),
            ),
          ],
          const AppGap(16),
          FilledButton(
            onPressed: () => Navigator.pop(
              sheet,
              CollectionViewChoice(layout, sort, cardSize, descending),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  ),
);

/// The same selection anchor for every media tile and row.
class MediaItemSelection extends StatelessWidget {
  const MediaItemSelection({
    super.key,
    required this.child,
    required this.selected,
    required this.onToggle,
    this.reserveLeading = false,
  });
  final Widget child;
  final bool? selected;
  final VoidCallback onToggle;
  final bool reserveLeading;
  @override
  Widget build(BuildContext context) {
    if (selected == null) return child;
    Widget contents(Widget content) => Stack(
      children: [
        Padding(
          padding: reserveLeading
              ? const EdgeInsets.only(left: 56)
              : EdgeInsets.zero,
          child: content,
        ),
        Positioned(
          top: 4,
          left: 4,
          child: Material(
            type: MaterialType.transparency,
            borderRadius: interfaceRadius(context, 4),
            child: Checkbox(value: selected, onChanged: (_) => onToggle()),
          ),
        ),
      ],
    );
    if (child is Card) {
      final card = child as Card;
      return Card(
        key: card.key,
        color: card.color,
        shadowColor: card.shadowColor,
        surfaceTintColor: card.surfaceTintColor,
        elevation: card.elevation,
        shape: card.shape,
        borderOnForeground: card.borderOnForeground,
        margin: card.margin,
        semanticContainer: card.semanticContainer,
        clipBehavior: Clip.antiAlias,
        child: contents(card.child ?? const SizedBox.shrink()),
      );
    }
    return InterfaceClip(child: contents(child));
  }
}
