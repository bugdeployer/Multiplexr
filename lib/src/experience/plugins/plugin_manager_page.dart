import 'dart:convert';

import 'plugin_tools_page.dart';
import 'plugin_settings_page.dart';
import 'plugin_metadata_page.dart';
import '../../features/metadata/application/metadata_contracts.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:app_shell/app_shell.dart';

import 'plugin_manager.dart';

class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({
    super.key,
    required this.manager,
    this.embedded = false,
  });
  final bool embedded;
  final PluginManager manager;
  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  PluginManager get manager => widget.manager;
  String filter = '';
  bool browse = false;
  Iterable<PluginRecord> get visiblePlugins => manager.installed.where(
    (p) => '${p.name} ${p.id}'.toLowerCase().contains(filter.toLowerCase()),
  );
  @override
  void initState() {
    super.initState();
    manager.refresh();
  }

  Future<void> action(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error, stack) {
      debugPrintStack(
        label: 'Plugin action failed (${error.runtimeType})',
        stackTrace: stack,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plugin operation could not complete.')),
        );
      }
    }
  }

  Future<void> install({bool website = false, String? packageUrl}) async {
    String? url = packageUrl;
    website = website || packageUrl != null;
    if (website && url == null) {
      final field = TextEditingController();
      url = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Install from website'),
          content: TextField(
            controller: field,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'HTTPS package URL'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, field.text.trim()),
              child: const Text('Download for review'),
            ),
          ],
        ),
      );
      field.dispose();
      if (url == null) return;
    }
    final value = await manager.perform(
      website ? 'stageUrl' : 'pick',
      website ? {'url': url} : const {},
    );
    if (value == null || !mounted) return;
    final review = Map<String, dynamic>.from(value as Map);
    final permissions = (review['permissions'] as List).cast<String>().toSet();
    final origins = (review['origins'] as List).cast<String>().toSet();
    final available = await manager.scopes();
    if (!mounted) return;
    final collections = <String>{};
    bool publisherReviewed = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Review ${review['name']}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Version ${review['version']}'),
                  const AppGap(12),
                  const Text('Community publisher fingerprint'),
                  SelectableText(review['publisher'] as String),
                  if (review['expanded'] == true)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'This update requests broader access. Review every grant.',
                      ),
                    ),
                  if (review['publisherChanged'] == true)
                    CheckboxListTile(
                      value: publisherReviewed,
                      onChanged: (v) =>
                          update(() => publisherReviewed = v == true),
                      title: const Text('Approve this publisher change'),
                      subtitle: const Text(
                        'Review the fingerprint independently before trusting a new key.',
                      ),
                    ),
                  const AppGap(12),
                  const Text('Capabilities'),
                  for (final permission
                      in (review['permissions'] as List).cast<String>())
                    CheckboxListTile(
                      value: permissions.contains(permission),
                      title: Text(permission),
                      onChanged: (v) => update(
                        () => v == true
                            ? permissions.add(permission)
                            : permissions.remove(permission),
                      ),
                    ),
                  if (origins.isNotEmpty) const Text('HTTPS destinations'),
                  for (final origin
                      in (review['origins'] as List).cast<String>())
                    CheckboxListTile(
                      value: origins.contains(origin),
                      title: Text(origin),
                      onChanged: (v) => update(
                        () => v == true
                            ? origins.add(origin)
                            : origins.remove(origin),
                      ),
                    ),
                  const Text('Collection access'),
                  const Text(
                    'Only selected, currently unlocked collections are available.',
                  ),
                  for (final scope in available)
                    CheckboxListTile(
                      value: collections.contains(scope.collection),
                      title: Text(scope.label),
                      onChanged: (v) => update(
                        () => v == true
                            ? collections.add(scope.collection)
                            : collections.remove(scope.collection),
                      ),
                    ),
                  const Text(
                    'Installing keeps the plugin disabled until you enable it. Signatures identify a publisher; they do not certify its behavior.',
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
              onPressed:
                  review['publisherChanged'] == true && !publisherReviewed
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('Install reviewed package'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      await manager.perform('discard', {'token': review['token']});
      return;
    }
    await manager.perform('activate', {
      'token': review['token'],
      'expected': review['expected'],
      'permissions': permissions.toList(),
      'origins': origins.toList(),
      'collections': collections.toList(),
      'publisherReviewed': publisherReviewed,
    });
  }

  Future<void> permissions(PluginRecord plugin) async {
    final available = await manager.scopes();
    if (!mounted) return;
    final grants = plugin.permissions.toSet(),
        origins = plugin.origins.toSet(),
        collections = plugin.collections.toSet();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Access for ${plugin.name}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final value in plugin.requestedPermissions)
                    CheckboxListTile(
                      title: Text(value),
                      value: grants.contains(value),
                      onChanged: (on) => update(
                        () => on == true
                            ? grants.add(value)
                            : grants.remove(value),
                      ),
                    ),
                  for (final value in plugin.requestedOrigins)
                    CheckboxListTile(
                      title: Text(value),
                      value: origins.contains(value),
                      onChanged: (on) => update(
                        () => on == true
                            ? origins.add(value)
                            : origins.remove(value),
                      ),
                    ),
                  for (final scope in available)
                    CheckboxListTile(
                      title: Text(scope.label),
                      value: collections.contains(scope.collection),
                      onChanged: (on) => update(
                        () => on == true
                            ? collections.add(scope.collection)
                            : collections.remove(scope.collection),
                      ),
                    ),
                  const Text(
                    'Saving access disables the plugin. Enable it again after reviewing the grants.',
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
              child: const Text('Save access'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await manager.perform('permissions', {
        'id': plugin.id,
        'expected': plugin.revision,
        'permissions': grants.toList(),
        'origins': origins.toList(),
        'collections': collections.toList(),
      });
    }
  }

  Future<void> testMetadata(PluginRecord plugin) async {
    final contribution = plugin.contributions.firstWhere(
      (c) => c['family'] == 'metadata.provider',
    );
    final scopes = (await manager.scopes())
        .where(
          (scope) =>
              plugin.collections.contains(scope.collection) &&
              MetadataEntityType.values.any(
                (entity) => entity.name == scope.kind.name,
              ) &&
              ((contribution['kinds'] as List?)?.contains(scope.kind.name) ??
                  true),
        )
        .toList();
    if (!mounted) return;
    if (scopes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Allow a compatible collection in Permissions first.'),
        ),
      );
      return;
    }
    final selected = await showDialog<PluginScope>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Test lookup in collection'),
        children: [
          for (final scope in scopes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, scope),
              child: Text(scope.label),
            ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => PluginMetadataPage(
          collection: selected.collection,
          kind: selected.kind,
          entity: MetadataEntityType.values.byName(selected.kind.name),
          query: '',
          selectOnly: true,
          initialProvider: contribution['id'] as String,
        ),
      ),
    );
  }

  Future<void> remove(PluginRecord plugin) async {
    bool cleanup = false;
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Remove plugin?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Revoke access and delete credentials. Library records and applied metadata are kept.',
              ),
              CheckboxListTile(
                title: Text(
                  'Delete settings and private data (${plugin.privateBytes} bytes)',
                ),
                value: cleanup,
                onChanged: (v) => update(() => cleanup = v == true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (remove == true) {
      await manager.perform('remove', {'id': plugin.id, 'cleanup': cleanup});
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> secret(PluginRecord plugin) async {
    if (plugin.origins.isEmpty) return;
    String origin = plugin.origins.first;
    final field = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Host-managed credential'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: origin,
                items: [
                  for (final value in plugin.origins)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: (value) => update(() => origin = value!),
              ),
              TextField(
                controller: field,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Token or API key (empty removes it)',
                ),
              ),
              const Text(
                'Use the credential type requested by the provider. Only the host sends it to this destination.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    try {
      if (save == true) {
        await manager.perform('credential', {
          'id': plugin.id,
          'origin': origin,
          'value': field.text,
        });
      }
    } finally {
      field.clear();
      field.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: manager,
    builder: (context, _) => Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Plugins'),
              actions: [
                IconButton(
                  tooltip: 'Disable all plugins',
                  onPressed: () => action(() async {
                    await manager.perform('disableAll');
                  }),
                  icon: const AppIcon(AppIconRole.stop),
                ),
              ],
            ),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Extensions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh extensions',
                onPressed: manager.busy ? null : () => action(manager.refresh),
                icon: const AppIcon(AppIconRole.refresh),
              ),
              PopupMenuButton<String>(
                tooltip: 'Extension options',
                enabled: !manager.busy,
                onSelected: (value) {
                  if (value == 'file') action(() => install());
                  if (value == 'url') action(() => install(website: true));
                  if (value == 'disable') {
                    action(() async {
                      await manager.perform('disableAll');
                    });
                  }
                  if (value == 'tools') {
                    Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PluginToolsPage(manager: manager),
                      ),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'file', child: Text('Install file')),
                  PopupMenuItem(
                    value: 'url',
                    child: Text('Install from website'),
                  ),
                  PopupMenuItem(value: 'tools', child: Text('Extension tools')),
                  PopupMenuItem(
                    value: 'disable',
                    child: Text('Disable all plugins'),
                  ),
                ],
              ),
            ],
          ),
          const AppGap(16),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: const Text('Installed')),
              const ButtonSegment(value: true, label: Text('Browse')),
            ],
            selected: {browse},
            onSelectionChanged: (value) =>
                setState(() => browse = value.single),
          ),
          const AppGap(16),
          TextField(
            onChanged: (value) => setState(() => filter = value),
            decoration: const InputDecoration(
              prefixIcon: AppIcon(AppIconRole.search),
              hintText: 'Search extensions',
            ),
          ),
          const AppGap(20),
          if (browse) ...[
            Text('Providers', style: Theme.of(context).textTheme.titleMedium),
            const AppGap(8),
            const Text('Review access before enabling a provider.'),
            const AppGap(12),
            for (final provider in const [
              (
                slug: 'tmdb',
                id: 'com.bugdeployer.tmdb',
                name: 'TMDB',
                detail: 'Movies & TV · Read Access Token required',
                available: true,
              ),
              (
                slug: 'open-library',
                id: 'com.bugdeployer.openlibrary',
                name: 'Open Library',
                detail: 'Books · No API key required',
                available: true,
              ),
              (
                slug: 'audible',
                id: 'com.bugdeployer.audible',
                name: 'Audible US',
                detail: 'Audiobooks · Experimental public catalog',
                available: true,
              ),
              (
                slug: 'audiobookdb',
                id: 'com.bugdeployer.audiobookdb',
                name: 'AudiobookDB',
                detail: 'Audiobooks · Integration approval required',
                available: false,
              ),
            ])
              if ('${provider.name} ${provider.detail}'.toLowerCase().contains(
                filter.toLowerCase(),
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: AppIcon(AppIconRole.metadata),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              provider.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const AppGap(4),
                            Text(
                              provider.detail,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: manager.busy || !provider.available
                                    ? null
                                    : () => action(
                                        () => install(
                                          packageUrl:
                                              'https://github.com/bugdeployer/multiplexr-plugin-${provider.slug}/releases/download/v0.2.0/${provider.id}-0.2.0.mpx.json',
                                        ),
                                      ),
                                child: Text(
                                  !provider.available
                                      ? 'Unavailable'
                                      : manager.installed.any(
                                          (p) => p.id == provider.id,
                                        )
                                      ? 'Review update'
                                      : 'Install',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            const AppGap(16),
            OutlinedButton.icon(
              onPressed: manager.busy
                  ? null
                  : () => action(() => install(website: true)),
              icon: const AppIcon(AppIconRole.add),
              label: const Text('Install from another website'),
            ),
          ],
          if (manager.busy) const LinearProgressIndicator(),
          if (manager.invocationResult != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(manager.invocationResult!),
            ),
          if (manager.error?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(manager.error!),
            ),
          if (!browse && manager.installed.isEmpty && !manager.busy)
            Card(
              child: Padding(
                padding: AppSpacing.of(context).all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No plugins installed',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const AppGap(8),
                    Text(
                      'Browse providers or install a signed plugin file from the options menu.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!browse && manager.installed.isNotEmpty && visiblePlugins.isEmpty)
            const Text('No matching extensions'),
          for (final plugin in browse ? <PluginRecord>[] : visiblePlugins)
            Card(
              child: Padding(
                padding: AppSpacing.of(context).all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(plugin.name),
                      subtitle: Text(
                        '${plugin.version} · ${plugin.enabled ? 'Enabled' : 'Disabled'}',
                      ),
                      value: plugin.enabled,
                      onChanged: manager.busy
                          ? null
                          : (enabled) => action(() async {
                              await manager.perform(
                                enabled ? 'enable' : 'disable',
                                {'id': plugin.id},
                              );
                            }),
                    ),
                    Text(
                      plugin.contributions.any(
                            (c) => c['family'] == 'metadata.provider',
                          )
                          ? 'Metadata provider'
                          : 'Tools & settings',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    if (plugin.contributions.any(
                          (c) => c['family'] == 'metadata.provider',
                        ) &&
                        plugin.collections.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Setup needed: allow collection access in Manage > Permissions.',
                        ),
                      ),
                    if (plugin.id.startsWith('com.bugdeployer.') &&
                        plugin.version == '0.1.0' &&
                        !plugin.contributions.any(
                          (c) => c['family'] == 'metadata.provider',
                        ))
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Starter package: metadata lookup is not included. Install a provider update from Browse.',
                        ),
                      ),
                    if (plugin.error.isNotEmpty)
                      Text(
                        plugin.error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const AppGap(12),
                    ExpansionTile(
                      key: ValueKey('manage:${plugin.id}'),
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Manage'),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  action(() => permissions(plugin)),
                              child: const Text('Permissions'),
                            ),
                            if (plugin.enabled &&
                                plugin.contributions.any(
                                  (d) => d['family'] == 'settings.section',
                                ))
                              TextButton(
                                onPressed: () => Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PluginSettingsPage(
                                      manager: manager,
                                      plugin: plugin,
                                    ),
                                  ),
                                ),
                                child: const Text('Settings'),
                              ),
                            if (plugin.enabled &&
                                plugin.contributions.any(
                                  (c) => c['family'] == 'metadata.provider',
                                ))
                              TextButton(
                                onPressed: () =>
                                    action(() => testMetadata(plugin)),
                                child: const Text('Test lookup'),
                              ),
                            TextButton(
                              onPressed: () => action(() => install()),
                              child: const Text('Update'),
                            ),
                            if (plugin.permissions.contains('credentials.use'))
                              TextButton(
                                onPressed: () => action(() => secret(plugin)),
                                child: const Text('Credentials'),
                              ),
                            if (plugin.rollback)
                              TextButton(
                                onPressed: () => action(() async {
                                  if (await confirm(
                                    'Roll back plugin?',
                                    'Restore the previous package in a disabled state. Library data is kept.',
                                  )) {
                                    await manager.perform('rollback', {
                                      'id': plugin.id,
                                    });
                                  }
                                }),
                                child: const Text('Roll back'),
                              ),
                            TextButton(
                              onPressed: () => action(() async {
                                if (await confirm(
                                  'Reset plugin settings?',
                                  'Delete this publisher’s saved settings and disable the plugin. Use this before retrying an incompatible settings update. Library data is kept.',
                                )) {
                                  await manager.perform('resetSettings', {
                                    'id': plugin.id,
                                  });
                                }
                              }),
                              child: const Text('Reset settings'),
                            ),
                            TextButton(
                              onPressed: () => action(() => remove(plugin)),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                        ExpansionTile(
                          key: ValueKey('package-details:${plugin.id}'),
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Package details'),
                          childrenPadding: AppSpacing.of(context)
                              .symmetric(vertical: 8),
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Package ID'),
                              subtitle: SelectableText(plugin.id),
                              trailing: IconButton(
                                tooltip: 'Copy package ID',
                                icon: const AppIcon(AppIconRole.copy),
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: plugin.id),
                                ),
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Publisher fingerprint'),
                              subtitle: SelectableText(plugin.publisher),
                              trailing: IconButton(
                                tooltip: 'Copy publisher fingerprint',
                                icon: const AppIcon(AppIconRole.copy),
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: plugin.publisher),
                                ),
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Permissions'),
                              subtitle: Text(
                                plugin.permissions.isEmpty
                                    ? 'None'
                                    : plugin.permissions.join(', '),
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Approved destinations'),
                              subtitle: Text(
                                plugin.origins.isEmpty
                                    ? 'None'
                                    : plugin.origins.join(', '),
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Approved collections'),
                              subtitle: Text('${plugin.collections.length}'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          for (final row in manager.restored)
            Card(
              child: ListTile(
                title: Text('Backup: ${row['id']} ${row['version']}'),
                subtitle: const Text(
                  'Inventory is informational. Packages are never installed or enabled by restore.',
                ),
                trailing:
                    row['settings'] != null &&
                        manager.installed.any(
                          (p) =>
                              p.id == row['id'] &&
                              p.publisher == row['publisher'] &&
                              p.enabled,
                        )
                    ? TextButton(
                        onPressed: manager.busy
                            ? null
                            : () => action(() async {
                                final plugin = manager.installed.singleWhere(
                                  (p) => p.id == row['id'],
                                );
                                if (await confirm(
                                  'Restore plugin settings?',
                                  'Replace compatible non-secret values from the backup. The plugin will be disabled. No code or permissions are restored.',
                                )) {
                                  await manager.perform('restoreSettings', {
                                    'id': plugin.id,
                                    'revision': plugin.revision,
                                    'publisher': row['publisher'],
                                    'settings': row['settings'],
                                  });
                                }
                              }),
                        child: const Text('Restore settings'),
                      )
                    : null,
              ),
            ),
          for (final proposal in manager.gateway.proposals)
            Card(
              child: ListTile(
                title: Text(
                  'Proposed ${proposal.fields == null ? 'tags' : 'extension fields'}: ${proposal.title.title}',
                ),
                subtitle: Text(
                  proposal.fields == null
                      ? proposal.tags.join(', ')
                      : jsonEncode(proposal.fields),
                ),
                trailing: TextButton(
                  child: const Text('Review'),
                  onPressed: () => action(() async {
                    if (await confirm(
                      'Apply plugin proposal?',
                      '${proposal.plugin.name} proposes ${proposal.fields == null ? 'tags' : 'extension fields'} on ${proposal.title.title}: ${proposal.fields == null ? proposal.tags.join(', ') : jsonEncode(proposal.fields)}',
                    )) {
                      await manager.withOrigin(
                        proposal.plugin.id,
                        () => manager.gateway.confirm(proposal.id),
                      );
                      await manager.refresh();
                    }
                  }),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
