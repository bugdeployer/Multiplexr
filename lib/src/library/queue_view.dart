import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'tags.dart';

Future<void> showVideoQueue(
  BuildContext context,
  LibraryController library,
  void Function(VideoAsset) play, {
  List<VideoAsset> Function()? items,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => AnimatedBuilder(
    animation: library,
    builder: (context, _) {
      final queued = items?.call() ?? library.queuedVideos;
      Future<void> reorder(int oldIndex, int newIndex) async {
        final updated = [...queued];
        updated.insert(newIndex, updated.removeAt(oldIndex));
        try {
          await library.reorderQueued(updated);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not reorder the queue.')),
            );
          }
        }
      }

      return SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  children: [
                    Text(
                      'Up next · ${queued.length}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const AppGap(6),
                    const Text('Drag to reorder · first video plays next'),
                  ],
                ),
              ),
              Expanded(
                child: queued.isEmpty
                    ? const Center(
                        child: Text(
                          'Your queue is empty. Add videos with their menu.',
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: queued.length,
                        onReorderItem: reorder,
                        itemBuilder: (context, index) {
                          final asset = queued[index];
                          final name =
                              library.collections
                                  .where((c) => c.id == asset.collectionId)
                                  .firstOrNull
                                  ?.name ??
                              '';
                          return ListTile(
                            key: ValueKey(library.queueKey(asset)),
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const AppIcon(AppIconRole.drag),
                                    const AppGap.horizontal(8),
                                    Text('${index + 1}'),
                                  ],
                                ),
                              ),
                            ),
                            title: Text(
                              asset.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$name · ${asset.filename}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              play(asset);
                            },
                            trailing: PopupMenuButton<String>(
                              icon: const AppIcon(AppIconRole.menu),
                              tooltip: 'Queue options for ${asset.title}',
                              onSelected: (action) async {
                                try {
                                  if (action == 'next') {
                                    await library.enqueue(asset, next: true);
                                  } else {
                                    await library.removeQueued(asset);
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Could not update the queue.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'next',
                                  child: Text('Move to next'),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove from queue'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);

class VideoActions extends StatelessWidget {
  const VideoActions({
    super.key,
    required this.asset,
    required this.library,
    this.openSource,
  });
  final Future<void> Function()? openSource;
  final VideoAsset asset;
  final LibraryController library;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    icon: const AppIcon(AppIconRole.menu),
    tooltip: 'Video actions for ${asset.title}',
    onSelected: (action) async {
      try {
        if (action == 'tags') {
          await editVideoTags(context, library, [asset]);
        } else if (action == 'source') {
          await openSource?.call();
        } else if (action == 'next' || action == 'queue') {
          await library.enqueue(asset, next: action == 'next');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  action == 'next' ? 'Added to play next' : 'Added to queue',
                ),
              ),
            );
          }
        } else {
          await library.flags(
            [asset],
            action,
            action == 'favorite' ? !asset.favorite : !asset.watchLater,
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save this action.')),
          );
        }
      }
    },
    itemBuilder: (_) => [
      if (openSource != null)
        const PopupMenuItem(
          value: 'source',
          child: Text('Open source collection'),
        ),
      const PopupMenuItem(value: 'tags', child: Text('Edit tags')),
      const PopupMenuItem(value: 'next', child: Text('Play next')),
      const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
      PopupMenuItem(
        value: 'favorite',
        child: Text(
          asset.favorite ? 'Remove from Favorites' : 'Add to Favorites',
        ),
      ),
      PopupMenuItem(
        value: 'watchLater',
        child: Text(
          asset.watchLater ? 'Remove from Watch later' : 'Add to Watch later',
        ),
      ),
    ],
  );
}
