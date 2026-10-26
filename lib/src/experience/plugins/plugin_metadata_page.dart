import 'package:app_shell/app_shell.dart' show AppGap, AppSpacing;

import 'package:flutter/material.dart';

import '../../features/metadata/application/metadata_contracts.dart';
import '../../features/plugins/application/installed_metadata.dart';
import '../../features/plugins/application/contribution_registry.dart';
import '../../features/catalog/application/extension_catalog.dart';
import '../../metadata/metadata_review_page.dart';
import 'plugin_contribution_page.dart';
import 'plugin_manager.dart';

class PluginMetadataPage extends StatefulWidget {
  const PluginMetadataPage({
    super.key,
    required this.collection,
    required this.kind,
    required this.entity,
    required this.query,
    this.target,
    this.selectOnly = false,
  });
  final String collection, query;
  final ExtensionMedia kind;
  final MetadataEntityType entity;
  final MetadataTarget? target;
  final bool selectOnly;
  @override
  State<PluginMetadataPage> createState() => _PluginMetadataPageState();
}

class _PluginMetadataPageState extends State<PluginMetadataPage> {
  late final query = TextEditingController(text: widget.query);
  String? provider, error, cursor;
  MetadataSearchPage? page;
  bool busy = false;
  final cancellation = MetadataCancellation();
  PluginManager? get manager => PluginPlatformScope.maybeOf(context);
  List<PluginContribution> get providers =>
      manager?.registry
          .family('metadata.provider')
          .where((c) => c.plugin.collections.contains(widget.collection))
          .toList() ??
      [];
  @override
  void dispose() {
    cancellation.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> search({bool next = false}) async {
    final host = manager;
    if (host == null || query.text.trim().isEmpty) {
      return;
    }
    final entry = providers.where((p) => p.id == provider).firstOrNull;
    if (entry == null) {
      return;
    }
    setState(() => busy = true);
    try {
      final adapter = InstalledMetadataProvider(
        entry,
        host.invokeContribution,
        [PluginScope(widget.collection, widget.kind, 'Selected collection')],
      );
      final result = await adapter.search(
        MetadataSearchRequest(
          provider: entry.id,
          entity: widget.entity,
          title: query.text.trim(),
          page: next ? (page?.request.page ?? 0) + 1 : 1,
          cursor: next ? cursor : null,
        ),
      );
      cancellation.check();
      if (!host.registry.current(entry)) {
        throw const PluginDenied();
      }
      if (mounted) {
        setState(() {
          page = result;
          cursor = result.nextCursor;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Search failed or provider access ended. Retry after checking plugin access.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> select(MetadataCandidate candidate) async {
    if (widget.selectOnly) {
      Navigator.pop(context, candidate);
      return;
    }
    if (widget.target == null) {
      return;
    }
    final applied = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MetadataReviewPage(target: widget.target!, candidate: candidate),
      ),
    );
    if (applied == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = providers;
    if (!available.any((p) => p.id == provider)) {
      provider = available.firstOrNull?.id;
      page = null;
      cursor = null;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Find metadata')),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          if (available.isEmpty)
            const Text(
              'No enabled metadata providers have access to this collection. Install a provider in Settings → Plugins, review its permissions and enable it. Manual editing remains available.',
            ),
          if (available.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: provider,
              decoration: const InputDecoration(
                labelText: 'Installed provider',
              ),
              items: [
                for (final entry in available)
                  DropdownMenuItem(
                    value: entry.id,
                    child: Text('${entry.plugin.name} · ${entry.title}'),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      provider = v;
                      page = null;
                      cursor = null;
                    }),
            ),
          const AppGap(16),
          TextField(
            controller: query,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const AppGap(16),
          FilledButton(
            onPressed: busy || available.isEmpty ? null : search,
            child: const Text('Search'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          for (final candidate in page?.candidates ?? <MetadataCandidate>[])
            ListTile(
              title: Text(candidate.values['title'] as String? ?? ''),
              subtitle: Text(candidate.attribution),
              onTap: busy ? null : () => select(candidate),
            ),
          if (cursor != null)
            TextButton(
              onPressed: busy ? null : () => search(next: true),
              child: const Text('Next page'),
            ),
        ],
      ),
    );
  }
}

class PluginCollectionMetadataFinder extends StatelessWidget {
  const PluginCollectionMetadataFinder({
    super.key,
    required this.kind,
    required this.entity,
    required this.query,
  });
  final ExtensionMedia kind;
  final MetadataEntityType entity;
  final String query;
  @override
  Widget build(BuildContext context) {
    final host = PluginPlatformScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose collection')),
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
                          final result =
                              await Navigator.push<MetadataCandidate>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PluginMetadataPage(
                                    collection: scope.collection,
                                    kind: kind,
                                    entity: entity,
                                    query: query,
                                    selectOnly: true,
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
                      child: Text(
                        'No unlocked collection is available for this media.',
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
