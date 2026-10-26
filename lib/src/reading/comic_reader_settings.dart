import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';

import '../settings/domain/media_settings.dart';
import 'comic_reader_controller.dart';

Future<void> showComicReaderSettings(
  BuildContext context,
  ComicReaderController controller,
) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => _ComicSettings(controller)));

class _ComicSettings extends StatefulWidget {
  const _ComicSettings(this.controller);
  final ComicReaderController controller;
  @override
  State<_ComicSettings> createState() => _ComicSettingsState();
}

class _ComicSettingsState extends State<_ComicSettings> {
  bool _busy = false;
  String? _error;
  ComicReaderController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _save(Map<String, Object> changes, {bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await c.setPreferences(changes, reset: reset);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save comic settings. Retry your change.',
        );
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_error!)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String origin(String key) => c.provenance[key]?.scope == SettingsScope.title
      ? 'This title'
      : 'Inherited';
  Widget choice(String key, String label, Map<String, String> values) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          icon: const AppIcon(AppIconRole.expand),
          key: ValueKey('$key:${c.preferences[key]}'),
          initialValue: c.preferences[key] as String,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            helperText: origin(key),
          ),
          items: values.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _busy
              ? null
              : (v) {
                  if (v != null) _save({key: v});
                },
        ),
      );
  Future<void> custom() async {
    final color = await showDialog<int>(
      context: context,
      builder: (_) => const _ComicColorDialog(),
    );
    if (color == null) return;
    final bg = Color(color);
    final fg = bg.computeLuminance() > .179 ? 0xff000000 : 0xffffffff;
    await _save({
      'palette': 'custom',
      'readerBackground': color,
      'readerForeground': fg,
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(c.pdf ? 'PDF appearance' : 'Comic reader settings'),
    ),
    body: SafeArea(
      child: ListView(
        padding: AppSpacing.of(context).all(16),
        children: [
          const Text(
            'Overrides apply to this title. Reset uses the current collection and series settings.',
          ),
          if (_error != null) Text(_error!),
          choice('comicMode', 'Reading mode', {
            'paged': 'Paged',
            'webtoon': c.pdf ? 'Continuous scrolling' : 'Webtoon vertical',
          }),
          if (!c.pdf)
            choice('direction', 'Page direction', {
              'ltr': 'Left to right',
              'rtl': 'Right to left',
            }),
          choice('fit', 'Page fit', {'page': 'Fit page', 'width': 'Fit width'}),
          if (!c.pdf)
            choice('spreads', 'Spreads', {
              'single': 'Single page',
              'landscape': 'Two pages in landscape (cover stays single)',
            }),
          if (!c.pdf)
            choice('tapZones', 'Tap zones', {
              'standard': 'Standard: right advances in LTR',
              'inverted': 'Reverse side taps',
              'off': 'Tap to toggle controls only',
            }),
          if (!c.pdf)
            SwitchListTile(
              title: const Text('Crop uniform borders'),
              subtitle: Text(
                '${origin('cropBorders')} · Paged mode; conservative edge detection',
              ),
              value: c.preferences['cropBorders'] == true,
              onChanged: _busy ? null : (v) => _save({'cropBorders': v}),
            ),
          if (!c.pdf)
            SwitchListTile(
              title: const Text('Volume-key navigation'),
              subtitle: Text(
                '${origin('volumeKeys')} · Down advances, Up goes back while this reader is active',
              ),
              value: c.preferences['volumeKeys'] == true,
              onChanged: _busy ? null : (v) => _save({'volumeKeys': v}),
            ),
          choice('palette', 'Reading palette', {
            'system': 'System',
            'day': 'Day',
            'sepia': 'Sepia',
            'dark': 'Dark',
            'custom': 'Custom',
          }),
          OutlinedButton(
            onPressed: _busy ? null : custom,
            child: const Text('Choose custom background'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _save({}, reset: true),
            child: const Text('Reset to inherited'),
          ),
          const Text(
            'Pinch to zoom, drag to pan. In webtoon mode, drag vertically or use navigation controls. Crop and spreads apply in paged mode.',
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }
}

class _ComicColorDialog extends StatefulWidget {
  const _ComicColorDialog();
  @override
  State<_ComicColorDialog> createState() => _ComicColorDialogState();
}

class _ComicColorDialogState extends State<_ComicColorDialog> {
  final input = TextEditingController();
  bool invalid = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reading background'),
    content: SingleChildScrollView(
      child: TextField(
        controller: input,
        autofocus: true,
        maxLength: 6,
        decoration: InputDecoration(
          labelText: 'RRGGBB',
          errorText: invalid ? 'Enter six hexadecimal digits' : null,
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(input.text)) {
            setState(() => invalid = true);
            return;
          }
          Navigator.pop(context, 0xff000000 | int.parse(input.text, radix: 16));
        },
        child: const Text('Apply'),
      ),
    ],
  );
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }
}
