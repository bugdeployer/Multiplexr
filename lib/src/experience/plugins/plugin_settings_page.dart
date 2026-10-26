import 'package:app_shell/app_shell.dart'
    show AppSpacing, AppGap, AppSection, InterfaceSwitchListTile;

import '../../features/catalog/application/extension_catalog.dart';

import 'package:flutter/material.dart';

import 'plugin_manager.dart';

/// Host controls all fields, labels, navigation and reset confirmation.
class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({
    super.key,
    required this.manager,
    required this.plugin,
    this.collection,
  });
  final PluginManager manager;
  final PluginRecord plugin;
  final String? collection;
  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  final values = <String, Object?>{}, sources = <String, Object?>{};
  int revision = 0;
  bool busy = true;
  String? error;
  String? collection;
  late Future<List<PluginScope>> scopeOptions;
  List<Map<String, dynamic>> get sections => widget.plugin.contributions
      .where((d) => d['family'] == 'settings.section')
      .toList();
  List<Map<String, dynamic>> get fields => [
    for (final section in sections)
      for (final f in section['fields'] as List)
        Map<String, dynamic>.from(f as Map),
  ];
  List<Map<String, Object?>> get lineage => [
    {'scope': 'app'},
    if (collection != null) {'scope': 'collection', 'collection': collection},
  ];
  Map<String, Object?> get address => lineage.last;
  bool get active =>
      !widget.manager.gateway.blocked() &&
      (collection == null ||
          ExtensionMedia.values.any(
            (kind) => widget.manager.gateway.authorized(collection!, kind),
          )) &&
      widget.manager.installed.any(
        (p) =>
            p.id == widget.plugin.id &&
            p.enabled &&
            p.instance == widget.plugin.instance &&
            p.revision == widget.plugin.revision,
      );
  @override
  void initState() {
    super.initState();
    collection = widget.collection;
    scopeOptions = widget.manager.scopes();
    widget.manager.addListener(changed);
    load();
  }

  void changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(changed);
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() => busy = true);
    }
    try {
      final loaded = <String, Object?>{}, provenance = <String, Object?>{};
      for (final field in fields.where((f) => f['type'] != 'credential')) {
        final result = await widget.manager.hostSettings(
          widget.plugin,
          'settings.effective',
          {'id': field['id'], 'lineage': lineage},
        );
        loaded[field['id'] as String] = result['value'];
        provenance[field['id'] as String] = result['sourceIndex'];
        revision = result['revision'] as int;
      }
      if (mounted && active) {
        setState(() {
          values.clear();
          values.addAll(loaded);
          sources.clear();
          sources.addAll(provenance);
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Settings unavailable. Check access or refresh after a package change.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  bool condition(Object? raw) {
    if (raw == null) {
      return true;
    }
    final c = raw as Map;
    return values[c['field']] == c['equals'];
  }

  Future<void> save(
    Map<String, dynamic> field,
    Object? value, {
    bool reset = false,
  }) async {
    setState(() => busy = true);
    try {
      await widget.manager.hostSettings(
        widget.plugin,
        reset ? 'settings.reset' : 'settings.propose',
        {
          'id': field['id'],
          'address': address,
          'expectedRevision': revision,
          if (!reset) 'value': value,
        },
      );
      await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Value rejected or settings changed. Refresh before retrying.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> edit(Map<String, dynamic> field) async {
    final id = field['id'] as String, type = field['type'] as String;
    final controller = TextEditingController(text: '${values[id] ?? ''}');
    Object? selected = values[id];
    final result = await showDialog<Object?>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(field['label'] as String),
          content: type == 'enum'
              ? DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selected as String?,
                  items: [
                    for (final choice in field['choices'] as List)
                      DropdownMenuItem(
                        value: choice as String,
                        child: Text(choice),
                      ),
                  ],
                  onChanged: (v) => update(() => selected = v),
                )
              : type == 'multiSelect'
              ? SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final choice in field['choices'] as List)
                        CheckboxListTile(
                          title: Text(choice as String),
                          value: (selected as List).contains(choice),
                          onChanged: (checked) => update(() {
                            final next = List<Object?>.from(selected as List);
                            if (checked == true) {
                              next.add(choice);
                            } else {
                              next.remove(choice);
                            }
                            selected = next;
                          }),
                        ),
                    ],
                  ),
                )
              : TextField(
                  controller: controller,
                  maxLength: type == 'text' ? field['maxLength'] as int : 30,
                  keyboardType: type == 'number'
                      ? const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        )
                      : TextInputType.text,
                  decoration: InputDecoration(
                    labelText: field['accessibleLabel'] as String,
                    helperText: type == 'number'
                        ? '${field['min']} – ${field['max']}'
                        : null,
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialog,
                type == 'text'
                    ? controller.text
                    : type == 'number'
                    ? num.tryParse(controller.text)
                    : selected,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null && mounted) {
      await save(field, result);
    }
  }

  Widget setting(Map<String, dynamic> field) {
    final id = field['id'] as String, type = field['type'] as String;
    final supported = (field['scopes'] as List).contains(address['scope']);
    final enabled =
        !busy &&
        error == null &&
        active &&
        supported &&
        condition(field['enabledWhen']);
    if (!condition(field['visibleWhen'])) {
      return const SizedBox.shrink();
    }
    if (type == 'credential') {
      return ListTile(
        title: Text(field['label'] as String),
        subtitle: const Text(
          'Configure credentials in the plugin manager. Tokens are never settings values.',
        ),
      );
    }
    final provenance = sources[id] == null
        ? 'Default'
        : sources[id] == 0
        ? 'Application override'
        : 'Collection override';
    return Semantics(
      label: field['accessibleLabel'] as String,
      child: Column(
        children: [
          if (type == 'boolean')
            InterfaceSwitchListTile(
              title: Text(field['label'] as String),
              subtitle: Text('${field['description'] ?? ''}\n$provenance'),
              value: values[id] == true,
              onChanged: enabled ? (v) => save(field, v) : null,
            )
          else
            ListTile(
              title: Text(field['label'] as String),
              subtitle: Text('${values[id] ?? ''} · $provenance'),
              enabled: enabled,
              onTap: enabled ? () => edit(field) : null,
            ),
          if (sources[id] == lineage.length - 1 && supported)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: enabled
                    ? () => save(field, null, reset: true)
                    : null,
                child: const Text('Use inherited value'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.plugin.name} settings')),
    body: !active
        ? const Center(
            child: Text('Plugin access ended. Return to the plugin manager.'),
          )
        : ListView(
            padding: AppSpacing.of(context).all(20),
            children: [
              FutureBuilder<List<PluginScope>>(
                future: scopeOptions,
                builder: (context, snapshot) {
                  final scopes = {
                    for (final scope in snapshot.data ?? <PluginScope>[])
                      if (widget.plugin.collections.contains(scope.collection))
                        scope.collection: scope,
                  };
                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: collection ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Settings scope',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Application defaults'),
                      ),
                      if (collection != null && !scopes.containsKey(collection))
                        DropdownMenuItem(
                          value: collection,
                          child: const Text('Selected collection'),
                        ),
                      for (final scope in scopes.values)
                        DropdownMenuItem(
                          value: scope.collection,
                          child: Text(scope.label),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(
                              () => collection = value == '' ? null : value,
                            );
                            load();
                          },
                  );
                },
              ),
              const AppGap(24),
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              for (final section in sections) ...[
                AppSection(
                  title: section['title'] as String,
                  children: [
                    for (final field in section['fields'] as List)
                      setting(Map<String, dynamic>.from(field as Map)),
                  ],
                ),
                const AppGap(20),
              ],
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        scopeOptions = widget.manager.scopes();
                        load();
                      },
                child: const Text('Refresh'),
              ),
            ],
          ),
  );
}
