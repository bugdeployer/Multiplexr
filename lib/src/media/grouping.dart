import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

export '../catalog/domain/media_group.dart';

/// Reused for book order, chapter order and TV episode order.
class GroupOrderPage<T> extends StatefulWidget {
  const GroupOrderPage({
    super.key,
    required this.title,
    required this.items,
    required this.identity,
    required this.label,
    required this.save,
  });
  final String title;
  final List<T> items;
  final String Function(T) identity, label;
  final Future<void> Function(List<T>) save;
  @override
  State<GroupOrderPage<T>> createState() => _GroupOrderPageState<T>();
}

class _GroupOrderPageState<T> extends State<GroupOrderPage<T>> {
  late final items = [...widget.items];
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        if (error != null)
          Padding(padding: AppSpacing.of(context).all(16), child: Text(error!)),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: items.length,
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              if (!busy) {
                setState(
                  () => items.insert(newIndex, items.removeAt(oldIndex)),
                );
              }
            },
            itemBuilder: (context, index) => ListTile(
              key: ValueKey(widget.identity(items[index])),
              leading: Text('${index + 1}'),
              title: Text(widget.label(items[index])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: busy || index == 0
                        ? null
                        : () => setState(
                            () =>
                                items.insert(index - 1, items.removeAt(index)),
                          ),
                    icon: const AppIcon(AppIconRole.sortAscending),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    enabled: !busy,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: AppIcon(AppIconRole.drag),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: AppSpacing.of(context).all(20),
            child: FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.save(items);
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (mounted) {
                          setState(() {
                            busy = false;
                            error = 'Could not save order. Please try again.';
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Save order'),
            ),
          ),
        ),
      ],
    ),
  );
}
