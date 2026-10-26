import 'package:flutter/material.dart';

import '../features/reading/application/reader_choices.dart';

import 'package:app_shell/app_shell.dart';

String readerChoiceName(String value) => switch (value) {
  'internal' => 'Built-in reader',
  'ask' => 'Ask every time',
  _ => value.startsWith('app:') ? value.substring(4) : value,
};

/// Returns a preference only after an explicit selection; dismissal changes nothing.
Future<String?> chooseReader(
  BuildContext context,
  ReaderChoices service,
  String format, {
  bool preference = false,
}) async {
  List<InstalledReader> apps = const [];
  String? error;
  try {
    apps = await service.installedReaders(format);
  } catch (_) {
    error = 'Installed readers could not be loaded.';
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .55,
      minChildSize: .3,
      maxChildSize: .9,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: AppSpacing.of(context).all(20),
        children: [
          Text(
            'Open ${format.toUpperCase()} with',
            style: Theme.of(sheet).textTheme.titleLarge,
          ),
          const AppGap(16),
          ListTile(
            leading: const AppIcon(AppIconRole.reading),
            title: const Text('Built-in reader'),
            onTap: () => Navigator.pop(sheet, 'internal'),
          ),
          if (preference)
            ListTile(
              leading: const AppIcon(AppIconRole.externalLink),
              title: const Text('Ask every time'),
              onTap: () => Navigator.pop(sheet, 'ask'),
            ),
          for (final app in apps)
            ListTile(
              title: Text(app.label),
              subtitle: Text(app.package),
              onTap: () => Navigator.pop(sheet, 'app:${app.package}'),
            ),
          if (apps.isEmpty)
            Padding(
              padding: AppSpacing.of(context).all(16),
              child: Text(
                error ?? 'No compatible external reader is installed.',
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Progress and annotations in external readers do not sync back to Multiplexr.',
            ),
          ),
        ],
      ),
    ),
  );
}
