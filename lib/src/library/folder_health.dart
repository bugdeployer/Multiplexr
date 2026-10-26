import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'library_models.dart';

Future<void> showFolderHealth(
  BuildContext context,
  VideoCollection collection,
  Future<void> Function() manage, {
  Future<void> Function()? verify,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) => SingleChildScrollView(
      padding: AppSpacing.of(context).all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Folder health', style: Theme.of(sheet).textTheme.titleLarge),
          const AppGap(12),
          Text(
            collection.lastScanAt == 0
                ? 'Not scanned yet'
                : 'Last scan: ${DateTime.fromMillisecondsSinceEpoch(collection.lastScanAt).toLocal().toString().split('.').first}',
          ),
          const AppGap(12),
          if (collection.roots.isEmpty)
            const Text('No root folders. Add a folder in collection settings.'),
          for (final root in collection.roots)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppIcon(
                collection.rootHealth[root.uri] == 'Available'
                    ? AppIconRole.folder
                    : AppIconRole.folderUnavailable,
              ),
              title: Text(root.name),
              subtitle: Text(
                collection.rootHealth[root.uri] ??
                    'Not checked — scan folders to check access',
              ),
            ),
          const AppGap(12),
          Text(
            collection.isAudio
                ? 'Reselect inaccessible folders in collection settings, then scan again. Existing metadata and playback history are kept.'
                : 'Unavailable files keep their metadata and watch history. Reselect inaccessible folders in collection settings, then scan again. Moved files reconnect only when their filename and size identify a unique previously missing item.',
          ),
          const AppGap(16),
          TextButton(
            onPressed: () => Navigator.pop(sheet, 'manage'),
            child: const Text('Manage folders'),
          ),
          if (verify != null)
            FilledButton(
              onPressed: () => Navigator.pop(sheet, 'verify'),
              child: const Text('Scan and verify sources'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'manage') await manage();
  if (action == 'verify' && verify != null) await verify();
}
