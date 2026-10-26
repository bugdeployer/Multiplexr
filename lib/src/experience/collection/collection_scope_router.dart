import 'package:flutter/material.dart';

import '../../catalog/domain/classification.dart';

import 'package:app_shell/app_shell.dart';

class CollectionScopeOption {
  const CollectionScopeOption(this.id, this.name);
  final String id, name;
}

/// The app owns route creation and access; subtype screens only request a scope.
class CollectionScopeRouter {
  CollectionScopeRouter({required this.options, required this.open});
  final List<CollectionScopeOption> Function(MediaSubtype) options;
  final Future<void> Function(MediaSubtype, String?) open;
  static final _owners = Expando<CollectionScopeRouter>();
  static void register(Object owner, CollectionScopeRouter? router) =>
      _owners[owner] = router;
  static Future<void> choose(
    BuildContext context,
    Object owner,
    MediaSubtype subtype,
  ) async {
    final router = _owners[owner];
    if (router == null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => ListView(
        shrinkWrap: true,
        padding: AppSpacing.of(context).all(20),
        children: [
          Text('Collection scope', style: Theme.of(sheet).textTheme.titleLarge),
          ListTile(
            leading: const AppIcon(AppIconRole.reading),
            title: const Text('All collections'),
            subtitle: const Text('Global Space · eligible collections'),
            onTap: () => Navigator.pop(sheet, ''),
          ),
          for (final option in router.options(subtype))
            ListTile(
              leading: const AppIcon(AppIconRole.folder),
              title: Text(option.name),
              subtitle: const Text('Local collection and Space'),
              onTap: () => Navigator.pop(sheet, option.id),
            ),
        ],
      ),
    );
    if (selected != null &&
        context.mounted &&
        identical(_owners[owner], router)) {
      await router.open(subtype, selected.isEmpty ? null : selected);
    }
  }
}
