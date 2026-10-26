import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';

import 'library_models.dart';
import 'library_controller.dart';
import 'video_scope.dart';

List<String> normalizeTags(String text) {
  final seen = <String>{};
  final result = text
      .split(RegExp('[,;]'))
      .map((s) => s.trim().replaceFirst(RegExp(r'^#+'), '').trim())
      .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
      .toList();
  if (result.length > 100 || result.any((s) => s.length > 80)) {
    throw const FormatException('Use at most 100 tags of 80 characters each.');
  }
  return result;
}

Future<void> editVideoTags(
  BuildContext context,
  LibraryController library,
  List<VideoAsset> assets,
) async {
  var input = assets.length == 1 ? videoTags(assets.single).join(', ') : '';
  final initial = input;
  var operation = assets.length == 1 ? 'replace' : 'add';
  String? error;
  var busy = false;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tags · ${assets.length} ${assets.length == 1 ? 'video' : 'videos'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const AppGap(16),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: operation,
                  decoration: const InputDecoration(labelText: 'Action'),
                  items: const [
                    DropdownMenuItem(value: 'add', child: Text('Add tags')),
                    DropdownMenuItem(
                      value: 'remove',
                      child: Text('Remove tags'),
                    ),
                    DropdownMenuItem(
                      value: 'replace',
                      child: Text('Replace all tags'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => update(() => operation = value!),
                ),
                const AppGap(16),
                TextFormField(
                  initialValue: initial,
                  onChanged: (value) => input = value,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Separate tags with commas',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!),
                  ),
                const AppGap(20),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final tags = normalizeTags(input);
                            if (assets.any(
                              (a) =>
                                  !library.canAccessCollection(a.collectionId),
                            )) {
                              throw StateError(
                                'Unlock the source collection first.',
                              );
                            }
                            await library.editTags(
                              assets,
                              operation: operation,
                              tags: tags,
                            );
                            await library.load();
                            if (context.mounted) Navigator.pop(context);
                          } catch (failure) {
                            if (context.mounted) {
                              update(() {
                                busy = false;
                                error = failure is FormatException
                                    ? failure.message
                                    : 'Could not save tags. Try again.';
                              });
                            }
                          }
                        },
                  child: Text(busy ? 'Saving…' : 'Save tags'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  } finally {
    // The form owns and disposes its text controller with the sheet route.
  }
}

class CollectionTags extends StatefulWidget {
  const CollectionTags({
    super.key,
    required this.library,
    required this.collectionId,
  });
  final LibraryController library;
  final String collectionId;
  @override
  State<CollectionTags> createState() => _CollectionTagsState();
}

class _CollectionTagsState extends State<CollectionTags> {
  String? error;
  bool busy = false;
  Future<void> change(String tag, bool delete) async {
    var input = tag;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(delete ? 'Delete tag?' : 'Rename or merge tag'),
        content: delete
            ? Text('Remove “$tag” from every video in this collection?')
            : TextFormField(
                initialValue: tag,
                onChanged: (value) => input = value,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tag name',
                  helperText: 'An existing name merges the tags',
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, delete ? '' : input),
            child: Text(delete ? 'Delete' : 'Save'),
          ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!widget.library.canAccessCollection(widget.collectionId)) {
        throw StateError('Locked');
      }
      if (!delete && normalizeTags(target).length != 1) {
        throw const FormatException('Enter one tag name.');
      }
      await widget.library.editTags(
        [],
        operation: delete ? 'delete' : 'rename',
        tags: [tag],
        target: target,
        collectionId: widget.collectionId,
      );
      await widget.library.load();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is FormatException
              ? failure.message
              : 'Could not update tags.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.library,
    builder: (context, _) {
      final groups = <String, ({String name, int count})>{};
      for (final asset in widget.library.items(widget.collectionId)) {
        for (final tag in videoTags(asset)) {
          final key = tag.toLowerCase();
          final old = groups[key];
          groups[key] = (name: old?.name ?? tag, count: (old?.count ?? 0) + 1);
        }
      }
      final tags = groups.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return Scaffold(
        appBar: AppBar(title: const Text('Collection tags')),
        body: ListView(
          padding: AppSpacing.of(context).all(20),
          children: [
            const Text(
              'Rename a tag to an existing name to merge them. Add tags from a video menu or a multi-video selection.',
            ),
            if (error != null) Text(error!),
            if (tags.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('No tags yet.'),
              ),
            for (final tag in tags)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tag.name),
                subtitle: Text('${tag.count} videos'),
                onTap: busy ? null : () => change(tag.name, false),
                trailing: IconButton(
                  tooltip: 'Delete ${tag.name}',
                  onPressed: busy ? null : () => change(tag.name, true),
                  icon: const AppIcon(AppIconRole.delete),
                ),
              ),
          ],
        ),
      );
    },
  );
}
