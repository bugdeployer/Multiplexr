import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';

import '../settings/domain/media_settings.dart';
import 'text_reader_controller.dart';
import 'text_reader_layout.dart';

Future<void> showTextReaderSettings(
  BuildContext context,
  TextReaderController controller,
  Map<String, String> fonts,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: .72,
    child: _ReaderSettingsPage(controller, fonts),
  ),
);

class _ReaderSettingsPage extends StatefulWidget {
  const _ReaderSettingsPage(this.controller, this.fonts);
  final TextReaderController controller;
  final Map<String, String> fonts;
  @override
  State<_ReaderSettingsPage> createState() => _ReaderSettingsPageState();
}

class _ReaderSettingsPageState extends State<_ReaderSettingsPage> {
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _save(Map<String, Object> values, {bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.setPreferences(values, reset: reset);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save reader settings. Your previous settings are retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _source(String key) =>
      widget.controller.provenance[key]?.scope == SettingsScope.title
      ? 'This title'
      : 'Inherited';
  Widget _choice(
    String id,
    String title,
    List<String> values, [
    Map<String, String> labels = const {},
  ]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      icon: const AppIcon(AppIconRole.expand),
      key: ValueKey('$id:${widget.controller.preferences[id]}'),
      initialValue: widget.controller.preferences[id] as String,
      isExpanded: true,
      decoration: InputDecoration(labelText: title, helperText: _source(id)),
      items: [
        for (final value in values)
          DropdownMenuItem(
            value: value,
            child: Text(
              labels[value] ?? value,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _busy
          ? null
          : (v) {
              if (v != null) _save({id: v});
            },
    ),
  );
  Future<void> _customPalette() async {
    final result = await showDialog<Map<String, Object>>(
      context: context,
      builder: (_) => _CustomReaderPalette(widget.controller.preferences),
    );
    if (result != null) await _save(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.preferences;
    final fonts = {
      'system',
      'serif',
      'sans',
      'monospace',
      ...widget.fonts.keys,
      p['fontAsset'] as String,
    }.toList();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Appearance'),
        actions: [
          IconButton(
            tooltip: 'Done',
            onPressed: () => Navigator.pop(context),
            icon: const AppIcon(AppIconRole.close),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.of(context).all(16),
          children: [
            Container(
              padding: AppSpacing.of(context).all(20),
              decoration: BoxDecoration(
                color: ReaderPalette.resolve(
                  p,
                  Theme.of(context).colorScheme,
                ).background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'A quiet moment, a good book.\nMake this page your own.',
                style: TextStyle(
                  inherit: false,
                  color: ReaderPalette.resolve(
                    p,
                    Theme.of(context).colorScheme,
                  ).foreground,
                  fontFamily: p['fontAsset'] == 'system'
                      ? 'sans-serif'
                      : widget.fonts[p['fontAsset']] ??
                            p['fontAsset'] as String,
                  fontSize: (p['fontSize'] as num).toDouble(),
                  height: (p['lineHeight'] as num).toDouble(),
                ),
              ),
            ),
            const AppGap(16),
            const Text('Title overrides'),
            const AppGap(8),
            const Text(
              'Reset removes these overrides and uses the current collection and series values.',
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
            _choice(
              'textMode',
              'Reading mode',
              ['paged', 'scroll'],
              {'paged': 'Pages', 'scroll': 'Vertical scrolling'},
            ),
            _choice('fontAsset', 'Font', fonts, {
              'system': 'System',
              'serif': 'Serif',
              'sans': 'Sans serif',
              'monospace': 'Monospace',
              ...widget.fonts,
            }),
            if (!{
              'system',
              'serif',
              'sans',
              'monospace',
              ...widget.fonts.keys,
            }.contains(p['fontAsset']))
              const Text(
                'The selected font is unavailable. System font is being used.',
              ),
            for (final spec in [
              ('fontSize', 'Font size', 8.0, 72.0),
              ('lineHeight', 'Line height', 1.0, 3.0),
              ('margin', 'Margins', 0.0, 96.0),
              ('paragraphSpacing', 'Paragraph spacing', 0.0, 64.0),
            ])
              _ReaderSlider(
                label: '${spec.$2} · ${_source(spec.$1)}',
                value: (p[spec.$1] as num).toDouble(),
                min: spec.$3,
                max: spec.$4,
                enabled: !_busy,
                save: (v) => _save({spec.$1: v}),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DropdownButtonFormField<int>(
                icon: const AppIcon(AppIconRole.expand),
                key: ValueKey(p['fontWeight']),
                initialValue: p['fontWeight'] as int,
                decoration: InputDecoration(
                  labelText: 'Font weight',
                  helperText: _source('fontWeight'),
                ),
                items: [
                  for (var weight = 100; weight <= 900; weight += 100)
                    DropdownMenuItem(value: weight, child: Text('$weight')),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) _save({'fontWeight': v});
                      },
              ),
            ),
            _choice(
              'alignment',
              'Alignment',
              ['start', 'justify', 'center'],
              {'start': 'Start', 'justify': 'Justified', 'center': 'Centered'},
            ),
            _choice(
              'palette',
              'Reading palette',
              ['system', 'day', 'sepia', 'dark', 'custom'],
              {
                'system': 'App theme',
                'day': 'Day',
                'sepia': 'Sepia',
                'dark': 'Dark',
                'custom': 'Custom',
              },
            ),
            TextButton(
              onPressed: _busy ? null : _customPalette,
              child: const Text('Edit custom palette'),
            ),
            const AppGap(16),
            OutlinedButton(
              onPressed: _busy ? null : () => _save({}, reset: true),
              child: const Text('Reset to inherited'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }
}

class _ReaderSlider extends StatefulWidget {
  const _ReaderSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.save,
  });
  final String label;
  final double value, min, max;
  final bool enabled;
  final Future<void> Function(double) save;
  @override
  State<_ReaderSlider> createState() => _ReaderSliderState();
}

class _ReaderSliderState extends State<_ReaderSlider> {
  double? _draft;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label),
      Slider(
        value: (_draft ?? widget.value).clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        label: (_draft ?? widget.value).toStringAsFixed(1),
        onChanged: widget.enabled ? (v) => setState(() => _draft = v) : null,
        onChangeEnd: widget.enabled
            ? (v) async {
                await widget.save(v);
                if (mounted) setState(() => _draft = null);
              }
            : null,
      ),
    ],
  );
}

class _CustomReaderPalette extends StatefulWidget {
  const _CustomReaderPalette(this.preferences);
  final Map<String, Object> preferences;
  @override
  State<_CustomReaderPalette> createState() => _CustomReaderPaletteState();
}

class _CustomReaderPaletteState extends State<_CustomReaderPalette> {
  late final _foreground = TextEditingController(
    text: (widget.preferences['readerForeground'] as int)
        .toRadixString(16)
        .substring(2),
  );
  late final _background = TextEditingController(
    text: (widget.preferences['readerBackground'] as int)
        .toRadixString(16)
        .substring(2),
  );
  String? _error;
  void _save() {
    final f = _foreground.text.trim(), b = _background.text.trim();
    if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(f) ||
        !RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(b)) {
      setState(() => _error = 'Enter six hexadecimal digits for each color.');
      return;
    }
    final foreground = int.parse('ff$f', radix: 16),
        background = int.parse('ff$b', radix: 16);
    if (ReaderPalette.contrast(Color(foreground), Color(background)) < 4.5) {
      setState(
        () => _error = 'Choose colors with at least 4.5:1 text contrast.',
      );
      return;
    }
    Navigator.pop(context, <String, Object>{
      'readerForeground': foreground,
      'readerBackground': background,
      'palette': 'custom',
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom reading palette'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _foreground,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Text color (RRGGBB)'),
          ),
          TextField(
            controller: _background,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Background (RRGGBB)'),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Apply')),
    ],
  );
  @override
  void dispose() {
    _foreground.dispose();
    _background.dispose();
    super.dispose();
  }
}
