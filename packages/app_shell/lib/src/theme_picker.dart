import 'theme/theme_gallery.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';
import 'theme_definition.dart';
import 'pixel_theme.dart';

class ThemePicker extends StatefulWidget {
  const ThemePicker({super.key, required this.settings});
  final ShellSettingsController settings;
  @override
  State<ThemePicker> createState() => _ThemePickerState();
}

class _ThemePickerState extends State<ThemePicker> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'Could not save theme. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reviewImport(String text) async {
    final definition = AppThemeDefinition.parse(text);
    if ({'retro', 'modern', 'minimal'}.contains(definition.id)) {
      throw const FormatException('Use a custom theme name when importing.');
    }
    await definition.tokens.prepare();
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(definition.name),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${definition.tokens.assets.values.where((a) => a.mime.startsWith('font/')).length} fonts and ${definition.tokens.assets.values.where((a) => a.mime == 'image/png').length} icons included',
                ),
                for (final dark in [false, true])
                  ExpansionTile(
                    title: Text(dark ? 'Dark preview' : 'Light preview'),
                    children: [
                      ThemeGallery(
                        data: widget.settings.previewTheme(
                          definition,
                          night: dark,
                        ),
                      ),
                    ],
                  ),
                for (final asset in definition.tokens.assets.values)
                  ExpansionTile(
                    title: Text(
                      '${asset.mime.startsWith('font/') ? 'Font' : 'Icon'} · ${asset.author}',
                    ),
                    subtitle: Text(asset.license),
                    children: [
                      if (asset.licenseText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(asset.licenseText),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(
              widget.settings.themes.containsKey(definition.id)
                  ? 'Update theme'
                  : 'Install theme',
            ),
          ),
        ],
      ),
    );
    if (accepted == true) await widget.settings.importTheme(text);
  }

  Future<void> editor({String? initial}) async {
    final controller = TextEditingController(
      text: initial ?? widget.settings.exportThemeV2(),
    );
    String? error;
    AppThemeDefinition? preview;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Import theme'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Edit the template or paste a theme JSON file. Preview it before applying.',
                  ),
                  const AppGap(12),
                  TextField(
                    controller: controller,
                    minLines: 6,
                    maxLines: 10,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    onChanged: (_) => update(() {
                      preview = null;
                      error = null;
                    }),
                    decoration: InputDecoration(
                      labelText: 'Theme JSON',
                      errorText: error,
                      errorMaxLines: 4,
                    ),
                  ),
                  if (preview != null) ...[
                    const AppGap(12),
                    Text(preview!.name),
                    for (final dark in [true, false]) ...[
                      Text(dark ? 'Dark' : 'Light'),
                      ThemeGallery(
                        data: widget.settings.previewTheme(
                          preview!,
                          night: dark,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final text = controller.text;
                try {
                  final next = AppThemeDefinition.parse(text);
                  if (['retro', 'modern', 'minimal'].contains(next.id)) {
                    throw const FormatException('Use a custom theme ID.');
                  }
                  await next.tokens.prepare();
                  if (!context.mounted || controller.text != text) return;
                  update(() {
                    preview = next;
                    error = null;
                  });
                } catch (e) {
                  if (!context.mounted) return;
                  update(() {
                    preview = null;
                    error = e is FormatException
                        ? e.message
                        : 'Theme assets could not be loaded.';
                  });
                }
              },
              child: const Text('Preview'),
            ),
            FilledButton(
              onPressed: preview == null
                  ? null
                  : () => Navigator.pop(context, controller.text),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    // Dialog route disposal may follow its pop animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (result != null) await widget.settings.importTheme(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Theme'),
        const AppGap(12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                icon: const AppIcon(AppIconRole.expand),
                key: ValueKey(s.selectedTheme?.id),
                initialValue: s.selectedTheme?.id,
                isExpanded: true,
                items: [
                  for (final theme in s.themes.values)
                    DropdownMenuItem(
                      value: theme.id,
                      child: Text(theme.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (id) {
                        if (id != null) run(() => s.selectTheme(id));
                      },
              ),
            ),
            IconButton(
              tooltip: 'Reset theme colors',
              onPressed: busy ? null : () => run(s.resetThemePalette),
              icon: const AppIcon(AppIconRole.refresh),
            ),
          ],
        ),
        if (s.themeWarning != null) Text(s.themeWarning!),
        const AppGap(8),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: busy ? null : () => run(() => editor()),
              icon: const AppIcon(AppIconRole.edit),
              label: const Text('Create / paste'),
            ),
            TextButton.icon(
              onPressed: busy || !s.supported
                  ? null
                  : () => run(() async {
                      final text = await s.platform.readThemeFile();
                      if (text != null && mounted) await reviewImport(text);
                    }),
              icon: const AppIcon(AppIconRole.openFile),
              label: const Text('Import file'),
            ),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => run(() async {
                      await Clipboard.setData(
                        ClipboardData(text: s.exportTheme()),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Theme JSON copied')),
                        );
                      }
                    }),
              icon: const AppIcon(AppIconRole.copy),
              label: const Text('Copy JSON'),
            ),
            TextButton.icon(
              onPressed: busy || !s.supported
                  ? null
                  : () => run(() async {
                      await s.platform.writeThemeFile(s.exportTheme());
                    }),
              icon: const AppIcon(AppIconRole.save),
              label: const Text('Export file'),
            ),

            if (s.selectedTheme?.tokens.assets.isNotEmpty == true)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Theme credits'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final asset
                              in s.selectedTheme!.tokens.assets.values)
                            ListTile(
                              title: Text(asset.path),
                              subtitle: Text(
                                '${asset.author} · ${asset.license}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Theme credits'),
              ),
            if (s.selectedTheme != null &&
                !['retro', 'modern', 'minimal'].contains(s.selectedTheme!.id))
              TextButton(
                onPressed: busy
                    ? null
                    : () => run(() => s.removeTheme(s.selectedTheme!.id)),
                child: const Text('Remove theme'),
              ),
          ],
        ),
      ],
    );
  }
}
