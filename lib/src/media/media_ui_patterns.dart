import 'package:app_shell/app_shell.dart' show AppGap, AppSpacing;

import '../experience/actions/catalog_actions.dart';
import '../experience/actions/media_actions.dart';
import '../catalog/domain/classification.dart';

import 'package:flutter/material.dart';

/// Shared cover-grid geometry. The parent owns scrolling so keyboard/accessibility
/// focus can reveal a complete tile without landing in an inert nested grid.
class MediaArtworkGrid extends StatelessWidget {
  const MediaArtworkGrid({
    super.key,
    required this.children,
    this.tileWidth = 180,
    this.spacing = 12,
    this.aspectRatio = 1,
  }) : assert(tileWidth > 0),
       assert(spacing >= 0);
  final List<Widget> children;
  final double tileWidth, spacing;
  final double? aspectRatio;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final columns = (size.maxWidth / tileWidth).round().clamp(
        size.maxWidth < 280 ? 1 : 2,
        6,
      );
      final width = (size.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: aspectRatio == null
                  ? child
                  : AspectRatio(aspectRatio: aspectRatio!, child: child),
            ),
        ],
      );
    },
  );
}

/// Common metadata actions keep the reference video labels and their order.
List<PopupMenuEntry<String>> mediaMetadataActions({
  bool settings = false,
  String edit = 'edit',
  String artwork = 'artwork',
  String find = 'metadata',
  bool includeFind = true,
  bool canEdit = true,
  bool canArtwork = true,
  bool canFind = true,
  bool authorized = true,
  Set<MediaCapability> capabilities = const {
    MediaCapability.artwork,
    MediaCapability.metadataLookup,
  },
}) {
  final context = MediaActionContext(
    authorized: authorized,
    capabilities: capabilities,
    hasSettings: settings,
    hasProvider: includeFind,
  );
  final keys = {
    MediaActionId.settings: 'settings',
    MediaActionId.editMetadata: edit,
    MediaActionId.chooseArtwork: artwork,
    MediaActionId.findMetadata: find,
  };
  final enabled = {
    MediaActionId.settings: true,
    MediaActionId.editMetadata: canEdit,
    MediaActionId.chooseArtwork: canArtwork,
    MediaActionId.findMetadata: canFind,
  };
  return [
    for (final action in MediaActionRegistry.definitions)
      if ((action.id != MediaActionId.settings || settings) &&
          (action.id != MediaActionId.findMetadata || includeFind))
        PopupMenuItem(
          value: keys[action.id],
          enabled:
              enabled[action.id]! &&
              MediaActionRegistry.permitted(action.id, context),
          child: Text(action.label),
        ),
  ];
}

List<PopupMenuEntry<String>> catalogActionMenu(
  List<PopupMenuEntry<String>> items, {
  required CatalogActionScope scope,
  required MediaActionContext context,
}) => [
  for (final item in items)
    if (item is PopupMenuItem<String>)
      PopupMenuItem<String>(
        key: item.key,
        value: item.value,
        height: item.height,
        padding: item.padding,
        onTap: item.onTap,
        enabled:
            item.enabled &&
            item.value != null &&
            CatalogActionRegistry.permitted(scope, item.value!, context),
        child: item.child,
      )
    else
      item,
];

/// Reference details shell: artwork, then the existing 20-pixel content gutter.
class MediaDetailsBody extends StatelessWidget {
  const MediaDetailsBody({
    super.key,
    required this.artwork,
    required this.children,
    this.artworkAspectRatio = 1,
    this.controller,
  });
  final Widget artwork;
  final List<Widget> children;
  final double artworkAspectRatio;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => ListView(
    controller: controller,
    children: [
      AspectRatio(aspectRatio: artworkAspectRatio, child: artwork),
      Padding(
        padding: AppSpacing.of(context).all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ],
  );
}

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    this.action,
  });
  final String title;
  final List<Widget> items;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const AppGap(24),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          ?action,
        ],
      ),
      const AppGap(14),
      if (items.isEmpty)
        const Text('Nothing here yet.')
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: SizedBox(width: 156, child: item),
                ),
            ],
          ),
        ),
    ],
  );
}
