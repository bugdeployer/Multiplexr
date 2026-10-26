import 'reader_choice.dart';

import 'domain/reading_catalog.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../features/metadata/application/metadata_contracts.dart';

import 'package:app_shell/app_shell.dart';

import '../settings/domain/media_settings.dart';
import 'domain/reader_settings.dart';
import 'reading_library.dart';

String readingStatusLabel(String value) => switch (value) {
  'inProgress' => 'In progress',
  'unread' => 'Unread',
  'completed' => 'Completed',
  'missing' => 'Source missing',
  _ => value,
};
String readingRoleLabel(ReadingTitle title) => switch (title.role) {
  ReadingRole.publication =>
    title.catalog.subtype == MediaSubtype.ebook ? 'Ebook' : 'Comic',
  ReadingRole.volume => 'Volume',
  ReadingRole.issue => 'Issue',
  ReadingRole.chapter => 'Chapter',
};
String readingScopeLabel(SettingsScope scope) => switch (scope) {
  SettingsScope.app => 'Application defaults',
  SettingsScope.collection => 'Collection',
  SettingsScope.group => 'Series',
  SettingsScope.title => 'This title',
};
String readerChoiceLabel(String value) =>
    const {
      'paged': 'Paged',
      'scroll': 'Scroll',
      'webtoon': 'Webtoon',
      'ltr': 'Left to right',
      'rtl': 'Right to left',
      'page': 'Fit page',
      'width': 'Fit width',
      'single': 'Single page',
      'landscape': 'Landscape spreads',
      'standard': 'Standard',
      'inverted': 'Inverted',
      'off': 'Off',
      'start': 'Start',
      'justify': 'Justified',
      'center': 'Centered',
      'system': 'System',
      'day': 'Day',
      'sepia': 'Sepia',
      'dark': 'Dark',
      'custom': 'Custom',
      'serif': 'Serif',
      'sans': 'Sans serif',
      'monospace': 'Monospace',
    }[value] ??
    value;

String readingCoverReference(ReadingBundle bundle, CatalogIdentity id) {
  final chosen = bundle.management.entity(id).cover;
  if (chosen.isNotEmpty) return chosen;
  if (id.kind == CatalogEntityKind.title) {
    return bundle.index.entry(id)?.cover ?? '';
  }
  final children =
      bundle.catalog.memberships.where((m) => m.parent == id).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
  for (final child in children) {
    final cover = readingCoverReference(bundle, child.child);
    if (cover.isNotEmpty) return cover;
  }
  return '';
}

class ReadingCover extends StatefulWidget {
  const ReadingCover({
    super.key,
    required this.library,
    required this.reference,
    this.crop = false,
  });
  final ReadingLibrary library;
  final String reference;
  final bool crop;
  @override
  State<ReadingCover> createState() => _ReadingCoverState();
}

class _ReadingCoverState extends State<ReadingCover> {
  Future<Uint8List>? bytes;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    bytes = widget.reference.isEmpty
        ? null
        : widget.library.artworkBytes(widget.reference);
  }

  @override
  void didUpdateWidget(ReadingCover old) {
    super.didUpdateWidget(old);
    if (old.reference != widget.reference) load();
  }

  @override
  Widget build(BuildContext context) => InterfaceClip(
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                fit: widget.crop ? BoxFit.cover : BoxFit.contain,
                cacheWidth: 512,
                errorBuilder: (_, _, _) =>
                    const Center(child: AppIcon(AppIconRole.reading)),
              )
            : const Center(child: AppIcon(AppIconRole.reading)),
      ),
    ),
  );
}

Future<void> readingFields(
  BuildContext context, {
  required String title,
  required Map<String, String> initial,
  required Future<void> Function(Map<String, String>) save,
  Set<String> multiline = const {},
  Map<String, String> labels = const {},
  String saveLabel = 'Save',
  String? message,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ReadingFields(
    title: title,
    initial: initial,
    save: save,
    multiline: multiline,
    labels: labels,
    saveLabel: saveLabel,
    message: message,
  ),
);

class _ReadingFields extends StatefulWidget {
  const _ReadingFields({
    required this.title,
    required this.initial,
    required this.save,
    required this.multiline,
    required this.labels,
    required this.saveLabel,
    this.message,
  });
  final String title, saveLabel;
  final String? message;
  final Map<String, String> initial, labels;
  final Set<String> multiline;
  final Future<void> Function(Map<String, String>) save;
  @override
  State<_ReadingFields> createState() => _ReadingFieldsState();
}

class _ReadingFieldsState extends State<_ReadingFields> {
  late final inputs = {
    for (final e in widget.initial.entries)
      e.key: TextEditingController(text: e.value),
  };
  bool busy = false;
  String? error;
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        for (final e in inputs.entries) e.key: e.value.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is MetadataFailure
              ? e.message
              : 'Could not save. Your draft is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.message != null) Text(widget.message!),
          for (final e in inputs.entries)
            TextField(
              key: ValueKey('reading-field-${e.key}'),
              controller: e.value,
              enabled: !busy,
              maxLength: 4096,
              minLines: 1,
              maxLines: widget.multiline.contains(e.key) ? 4 : 1,
              decoration: InputDecoration(
                labelText: widget.labels[e.key] ?? e.key,
              ),
            ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(widget.saveLabel),
      ),
    ],
  );
  @override
  void dispose() {
    for (final input in inputs.values) {
      input.dispose();
    }
    super.dispose();
  }
}

/// Same resolver and primitive definitions consumed by the actual readers.
class ReadingScopedSettingsPage extends StatefulWidget {
  const ReadingScopedSettingsPage({
    super.key,
    required this.library,
    required this.collectionId,
    required this.subtype,
    this.identity,
    this.application = false,
  });
  final ReadingLibrary library;
  final String collectionId;
  final MediaSubtype subtype;
  final CatalogIdentity? identity;
  final bool application;
  @override
  State<ReadingScopedSettingsPage> createState() =>
      _ReadingScopedSettingsPageState();
}

class _ReadingScopedSettingsPageState extends State<ReadingScopedSettingsPage> {
  Map<String, ResolvedSetting<Object>> effective = {};
  bool busy = true;
  bool pdfTitle = false;
  String? error;
  SettingsScope get scope => widget.application
      ? SettingsScope.app
      : widget.identity == null
      ? SettingsScope.collection
      : widget.identity!.kind == CatalogEntityKind.group
      ? SettingsScope.group
      : SettingsScope.title;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (!widget.application) widget.library.access(widget.collectionId);
      final b = await widget.library.read();
      if (!widget.application) widget.library.access(widget.collectionId);
      final parent = scope == SettingsScope.title
          ? b.catalog.memberships
                .where((m) => m.child == widget.identity)
                .firstOrNull
                ?.parent
          : widget.identity;
      final layers =
          b.catalog.settings
              .where(
                (s) =>
                    s.subtype == widget.subtype &&
                    (s.scope == SettingsScope.app ||
                        !widget.application &&
                            s.collectionId == widget.collectionId &&
                            (s.scope == SettingsScope.collection ||
                                s.scope == SettingsScope.group &&
                                    s.entityId == parent?.entityId ||
                                s.scope == SettingsScope.title &&
                                    s.entityId == widget.identity?.entityId)),
              )
              .toList()
            ..sort((a, b) => a.scope.index.compareTo(b.scope.index));
      if (mounted) {
        setState(() {
          pdfTitle =
              b.catalog.titles
                  .where((t) => t.catalog.id == widget.identity)
                  .firstOrNull
                  ?.format ==
              ReadingFormat.pdf;
          effective = {
            for (final d in ReaderSettings.definitions(widget.subtype))
              d.id: const SettingsResolver().resolve(
                d,
                layers.map((l) => l.layer),
              ),
          };
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not load reader settings. Retry.';
        });
      }
    }
  }

  Future<void> save(Map<String, Object> patch, {bool reset = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await persist(patch, reset: reset);
      await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save reader settings. Previous values are retained.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> inherit(String key) async {
    setState(() => busy = true);
    try {
      await widget.library.readerPreferences.setScope(
        subtype: widget.subtype,
        scope: scope,
        collectionId: widget.application ? null : widget.collectionId,
        entityId: widget.identity?.entityId,
        inherit: key,
      );
      await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not reset this setting. Retry.';
        });
      }
    }
  }

  static const choices = {
    'pdfMode': ['paged', 'scroll'],
    'pdfFit': ['page', 'width'],
    'textMode': ['paged', 'scroll'],
    'comicMode': ['paged', 'webtoon'],
    'direction': ['ltr', 'rtl'],
    'fit': ['page', 'width'],
    'spreads': ['single', 'landscape'],
    'tapZones': ['standard', 'inverted', 'off'],
    'alignment': ['start', 'justify', 'center'],
    'palette': ['system', 'day', 'sepia', 'dark', 'custom'],
    'fontAsset': ['system', 'serif', 'sans', 'monospace'],
  };
  Future<void> persist(Map<String, Object> patch, {bool reset = false}) =>
      widget.library.readerPreferences.setScope(
        subtype: widget.subtype,
        scope: scope,
        collectionId: widget.application ? null : widget.collectionId,
        entityId: widget.identity?.entityId,
        changes: patch,
        reset: reset,
      );

  static const labels = {
    'pdfMode': 'PDF reading mode',
    'pdfFit': 'PDF page fit',
    'fontSize': 'Font size',
    'fontWeight': 'Font weight',
    'lineHeight': 'Line height',
    'margin': 'Margins',
    'paragraphSpacing': 'Paragraph spacing',
    'alignment': 'Alignment',
    'fontAsset': 'Font family',
    'textMode': 'Reading mode',
    'comicMode': 'Reading mode',
    'direction': 'Page direction',
    'fit': 'Page fit',
    'spreads': 'Spreads',
    'tapZones': 'Tap zones',
    'cropBorders': 'Crop uniform borders',
    'volumeKeys': 'Volume-key navigation',
    'palette': 'Reading palette',
    'readerForeground': 'Text color',
    'readerBackground': 'Reading background',
  };
  Future<void> edit(String key, Object value) async {
    if (key == 'fontAsset') {
      final tokens = Theme.of(context).extension<ThemeTokens>();
      final options = {
        'system',
        'serif',
        'sans',
        'monospace',
        if (tokens != null && tokens.fontFamily != null) tokens.font,
      };
      final choice = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Font family'),
          children: [
            for (final font in options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, font),
                child: Text(font),
              ),
          ],
        ),
      );
      if (choice != null) await save({'fontAsset': choice});
      return;
    }
    await readingFields(
      context,
      title: labels[key] ?? key,
      initial: {
        'value': key.startsWith('reader')
            ? (value as int).toRadixString(16)
            : '$value',
      },
      labels: {
        'value': key == 'fontAsset'
            ? 'Validated font asset ID'
            : key.startsWith('reader')
            ? 'Opaque ARGB hexadecimal (FFRRGGBB)'
            : labels[key] ?? key,
      },
      save: (fields) async {
        final raw = fields['value']!;
        final Object next = key == 'fontAsset'
            ? raw
            : key.startsWith('reader')
            ? int.parse(raw, radix: 16)
            : value is int
            ? int.parse(raw)
            : double.parse(raw);
        await persist({key: next});
        await load();
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.application ? 'Application reader defaults' : 'Reader settings',
      ),
    ),
    body: !widget.application && !widget.library.authorized(widget.collectionId)
        ? const Center(child: Text('Collection access is required.'))
        : ListView(
            padding: AppSpacing.of(context).all(20),
            children: [
              Text(
                scope == SettingsScope.app
                    ? 'Application defaults · Reset uses built-in values.'
                    : '${readingScopeLabel(scope)} overrides · Reset uses inherited values.',
              ),
              if (widget.subtype == MediaSubtype.ebook)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'External readers keep their own progress and annotations. These do not sync back to Multiplexr.',
                  ),
                ),
              const AppGap(8),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                TextButton(onPressed: load, child: Text(error!)),
              AppSection(
                title: 'Reading preferences',
                children: [
                  Padding(
                    padding: AppSpacing.of(context).symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final e in effective.entries.where(
                          (e) =>
                              !pdfTitle ||
                              e.key == 'reader_pdf' ||
                              {
                                'pdfMode',
                                'pdfFit',
                                'palette',
                                'readerBackground',
                                'readerForeground',
                              }.contains(e.key),
                        )) ...[
                          if (e.key.startsWith('reader_'))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              minVerticalPadding: 12,
                              title: Text(
                                '${e.key.substring(7).toUpperCase()} default reader',
                              ),
                              subtitle: Text(
                                '${readerChoiceName(e.value.value as String)} · ${readingScopeLabel(e.value.scope)}',
                              ),
                              trailing:
                                  !widget.application && e.value.scope == scope
                                  ? IconButton(
                                      tooltip: 'Use inherited setting',
                                      icon: const AppIcon(AppIconRole.replay),
                                      onPressed: busy
                                          ? null
                                          : () => inherit(e.key),
                                    )
                                  : const AppIcon(AppIconRole.disclosure),
                              onTap: busy
                                  ? null
                                  : () async {
                                      final value = await chooseReader(
                                        context,
                                        widget.library.service,
                                        e.key.substring(7),
                                        preference: true,
                                      );
                                      if (value != null && mounted) {
                                        await save({e.key: value});
                                      }
                                    },
                            )
                          else if (e.value.value is bool)
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(labels[e.key] ?? e.key),
                              subtitle: Text(readingScopeLabel(e.value.scope)),
                              value: e.value.value as bool,
                              onChanged: busy
                                  ? null
                                  : (value) => save({e.key: value}),
                            )
                          else if (choices.containsKey(e.key))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: DropdownButtonFormField<String>(
                                icon: const AppIcon(AppIconRole.expand),
                                key: ValueKey('${e.key}:${e.value.value}'),
                                initialValue: e.value.value as String,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: labels[e.key],
                                  helperText: readingScopeLabel(e.value.scope),
                                  helperMaxLines: 3,
                                ),
                                items:
                                    {
                                          ...choices[e.key]!,
                                          if (e.key == 'fontAsset' &&
                                              Theme.of(context)
                                                      .extension<ThemeTokens>()
                                                      ?.fontFamily !=
                                                  null)
                                            Theme.of(context)
                                                .extension<ThemeTokens>()!
                                                .font,
                                          e.value.value as String,
                                        }
                                        .map(
                                          (v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(
                                              readerChoiceLabel(v),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                onChanged: busy
                                    ? null
                                    : (value) {
                                        if (value != null) save({e.key: value});
                                      },
                              ),
                            )
                          else
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              minVerticalPadding: 12,
                              title: Text(labels[e.key] ?? e.key),
                              subtitle: Text(
                                '${e.value.value} · ${readingScopeLabel(e.value.scope)}',
                              ),
                              onTap: busy
                                  ? null
                                  : () => edit(e.key, e.value.value),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const AppGap(16),
              TextButton(
                onPressed: busy ? null : () => save({}, reset: true),
                child: const Text('Reset to inherited'),
              ),
            ],
          ),
  );
}
