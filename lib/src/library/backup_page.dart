import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/backup/application/backup_workflow.dart';
import '../features/backup/application/backup_document.dart';
export '../features/backup/application/backup_document.dart'
    show backupSummary, readingBackupCollections;
import 'library_controller.dart';

class LibraryBackupSettings extends StatefulWidget {
  const LibraryBackupSettings({
    super.key,
    required this.library,
    required this.platform,
  });
  final LibraryController library;
  final ShellPlatform platform;
  @override
  State<LibraryBackupSettings> createState() => _LibraryBackupSettingsState();
}

class _LibraryBackupSettingsState extends State<LibraryBackupSettings> {
  late final workflow = widget.library.backupWorkflow(
    authentication: widget.platform.authenticate,
    active: () => mounted,
  );
  bool busy = false, restored = false;
  int lastExportAt = 0;
  @override
  void initState() {
    super.initState();
    workflow.port
        .lastExport()
        .then((value) {
          if (mounted) {
            setState(() => lastExportAt = value);
          }
        })
        .catchError((Object _) {});
  }

  Future<void> verifyRestored() => task(() async {
    final result = await workflow.verify();
    if (mounted) setState(() => status = result.message);
  });
  String? status;
  Map<String, dynamic>? preview;
  final Set<String> reselected = {};
  Future<void> task(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await action();
      if (mounted && workflow.authenticationCancelled) {
        setState(() => status = 'Authentication cancelled.');
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => status = failure is BackupBusy
              ? failure.message
              : failure is PlatformException
              ? failure.message
              : 'Could not complete this operation. Your current library is preserved if restore did not finish.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() => task(() async {
    final result = await workflow.export();
    if (result == BackupExportResult.saved) {
      lastExportAt = widget.library.clock.now().millisecondsSinceEpoch;
    }
    if (mounted) {
      setState(
        () => status = switch (result) {
          BackupExportResult.saved => 'Library backup saved.',
          BackupExportResult.cancelled => 'Export cancelled.',
          BackupExportResult.authenticationCancelled =>
            'Authentication cancelled.',
        },
      );
    }
  });
  Future<void> pick() => task(() async {
    final data = await workflow.pick();
    if (data == null || !mounted) return;
    setState(() {
      preview = data;
      reselected.clear();
    });
  });
  Future<void> relink(Map<String, dynamic> collection, int index) => task(
    () async {
      if (await workflow.relink(preview!, collection, index, reading: false) &&
          mounted) {
        setState(() => reselected.add('${collection['id']}:$index'));
      }
    },
  );
  Future<void> relinkReading(Map<String, dynamic> collection, int index) =>
      task(() async {
        if (await workflow.relink(preview!, collection, index, reading: true) &&
            mounted) {
          setState(() => reselected.add('reading:${collection['id']}:$index'));
        }
      });
  Future<void> restore() => task(() async {
    final data = preview;
    if (data == null) return;
    final success = await workflow.restore(
      data,
      () async =>
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Replace this library?'),
              content: const Text(
                'This replaces the current index, collections, favorites, queues and history with this backup. Source media files are kept. Export the current library first if you need it.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Replace library'),
                ),
              ],
            ),
          ) ==
          true,
    );
    if (!success) return;
    if (mounted) {
      setState(() {
        preview = null;
        restored = true;
        status = 'Library restored. Scan each collection to verify its files. Existing folder permissions were kept; reselect only roots marked unavailable.';
      });
    }
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Back up collections, metadata, tags, favorites and playback history. Media files, artwork cache, API credentials and device security preferences are excluded.',
      ),
      const AppGap(12),
      const Text(
        'Backups are readable JSON files and can include private collection information. Save them somewhere you trust.',
      ),
      if (lastExportAt > 0)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'Last backup: ${DateTime.fromMillisecondsSinceEpoch(lastExportAt).toLocal().toString().split('.').first}',
          ),
        ),
      if (restored)
        TextButton(
          onPressed: busy ? null : verifyRestored,
          child: const Text('Verify restored sources'),
        ),
      const AppGap(24),
      FilledButton.icon(
        onPressed: busy ? null : export,
        icon: const AppIcon(AppIconRole.importData),
        label: const Text('Export library backup'),
      ),
      const AppGap(12),
      OutlinedButton.icon(
        onPressed: busy ? null : pick,
        icon: const AppIcon(AppIconRole.exportData),
        label: const Text('Choose backup to restore'),
      ),
      if (busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      if (status != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(status!, semanticsLabel: status),
        ),
      if (preview != null) ...[
        const AppGap(24),
        Text('Restore preview', style: Theme.of(context).textTheme.titleLarge),
        Text(backupSummary(preview!)),
        const AppGap(16),
        const Text(
          'Existing folder permissions on this device are kept. Select only missing or changed folders below, then scan after restoring to verify files.',
        ),
        for (final value in preview!['collections'] as List) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              value['name'],
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (var index = 0; index < (value['roots'] as List).length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(value['roots'][index]['name']),
              subtitle: Text(
                reselected.contains('${value['id']}:$index')
                    ? 'Folder selected'
                    : (value['rootHealth']
                                  as Map?)?[value['roots'][index]['uri']]
                              ?.toString()
                              .startsWith('Permission retained') ==
                          true
                    ? 'Permission retained — scan after restore'
                    : 'Needs folder selection',
              ),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => relink(
                        Map<String, dynamic>.from(value)
                          ..['roots'] = value['roots'],
                        index,
                      ),
                child: const Text('Select'),
              ),
            ),
        ],
        for (final collection in readingBackupCollections(preview!)) ...[
          Text(
            collection['name'] as String,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (
            var index = 0;
            index < (collection['roots'] as List).length;
            index++
          )
            ListTile(
              title: Text(collection['roots'][index]['name'] as String),
              subtitle: Text(
                reselected.contains('reading:${collection['id']}:$index')
                    ? 'Folder selected · scan after restore'
                    : 'Reading source · verify in Folder health after restore',
              ),
              trailing: TextButton(
                onPressed: busy ? null : () => relinkReading(collection, index),
                child: const Text('Select'),
              ),
            ),
        ],
        const AppGap(24),
        FilledButton(
          onPressed: busy ? null : restore,
          child: const Text('Restore this backup'),
        ),
        TextButton(
          onPressed: busy ? null : () => setState(() => preview = null),
          child: const Text('Cancel restore'),
        ),
      ],
    ],
  );
}
