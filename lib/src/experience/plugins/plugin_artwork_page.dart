import 'package:app_shell/app_shell.dart' show AppSpacing;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/catalog/application/extension_catalog.dart';
import '../../features/plugins/application/contribution_registry.dart';
import 'plugin_contribution_page.dart';
import 'plugin_manager.dart';

class PluginArtworkPage extends StatefulWidget {
  const PluginArtworkPage({
    super.key,
    required this.collection,
    required this.kind,
    required this.titleId,
    required this.title,
    this.role = 'cover',
  });
  final String collection, titleId, title, role;
  final ExtensionMedia kind;
  @override
  State<PluginArtworkPage> createState() => _PluginArtworkPageState();
}

class _PluginArtworkPageState extends State<PluginArtworkPage> {
  String? provider, error;
  List<Map<String, dynamic>> items = [];
  bool busy = false;
  PluginManager? get manager => PluginPlatformScope.maybeOf(context);
  List<PluginContribution> get providers =>
      manager?.registry
          .family('artwork.provider')
          .where((c) => c.plugin.collections.contains(widget.collection))
          .toList() ??
      [];
  List<PluginScope> get scopes => [
    PluginScope(widget.collection, widget.kind, 'Selected collection'),
  ];
  Future<void> search() async {
    final host = manager;
    if (host == null || provider == null) {
      return;
    }
    setState(() => busy = true);
    try {
      final current = host.registry.require(provider!);
      final result = await host.invokeContribution(
        provider!,
        {
          'roles': [widget.role],
        },
        scopes,
        selection: [
          ExtensionTitle(
            id: widget.titleId,
            collection: widget.collection,
            kind: widget.kind,
            title: widget.title,
            revision: 'artwork-context',
          ),
        ],
      );
      if (!host.registry.current(current)) {
        throw const PluginDenied();
      }
      if (mounted) {
        setState(() {
          items = [
            for (final item in (result as Map)['items'] as List)
              Map<String, dynamic>.from(item as Map),
          ];
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Artwork lookup failed or access ended.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> select(Map<String, dynamic> item) async {
    final host = manager;
    if (host == null || provider == null) {
      return;
    }
    setState(() => busy = true);
    try {
      final entry = host.registry.require(provider!);
      final image = await host.materializeArtwork(provider!, item, scopes);
      if (!mounted) {
        return;
      }
      final use = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Use this artwork?'),
          content: Image.memory(
            base64Decode(image.substring(image.indexOf(',') + 1)),
            width: 256,
            height: 256,
            fit: BoxFit.contain,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Use image'),
            ),
          ],
        ),
      );
      if (use == true &&
          mounted &&
          host.registry.current(entry) &&
          host.gateway.authorized(widget.collection, widget.kind) &&
          !host.gateway.blocked() &&
          host.gateway.authorized(widget.collection, widget.kind)) {
        Navigator.pop(context, image);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Image rejected or access ended. Your existing artwork is retained.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = providers;
    if (!available.any((c) => c.id == provider)) {
      provider = available.firstOrNull?.id;
      items = [];
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Find artwork')),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          if (available.isEmpty)
            const Text(
              'No enabled artwork provider has collection access. Install and enable one in Settings → Plugins. Device images remain available.',
            ),
          if (available.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: provider,
              items: [
                for (final entry in available)
                  DropdownMenuItem(value: entry.id, child: Text(entry.title)),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      provider = v;
                      items = [];
                    }),
            ),
          FilledButton(
            onPressed: busy || available.isEmpty ? null : search,
            child: const Text('Search artwork'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          for (final item in items)
            ListTile(
              title: Text(item['role'] as String),
              subtitle: Text(item['attribution'] as String),
              onTap: busy ? null : () => select(item),
            ),
        ],
      ),
    );
  }
}

class PluginCollectionArtworkFinder extends StatelessWidget {
  const PluginCollectionArtworkFinder({
    super.key,
    required this.kind,
    required this.title,
  });
  final ExtensionMedia kind;
  final String title;
  @override
  Widget build(BuildContext context) {
    final host = PluginPlatformScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Artwork collection')),
      body: host == null
          ? const Center(child: Text('No plugin platform is available.'))
          : FutureBuilder<List<PluginScope>>(
              future: host.scopes(),
              builder: (context, snapshot) => ListView(
                children: [
                  for (final scope in snapshot.data ?? <PluginScope>[])
                    if (scope.kind == kind)
                      ListTile(
                        title: Text(scope.label),
                        onTap: () async {
                          final result = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PluginArtworkPage(
                                collection: scope.collection,
                                kind: kind,
                                titleId: 'collection-artwork-context',
                                title: title,
                              ),
                            ),
                          );
                          if (context.mounted && result != null) {
                            Navigator.pop(context, result);
                          }
                        },
                      ),
                  if (snapshot.hasData &&
                      !snapshot.data!.any((s) => s.kind == kind))
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No unlocked collection is available.'),
                    ),
                ],
              ),
            ),
    );
  }
}
