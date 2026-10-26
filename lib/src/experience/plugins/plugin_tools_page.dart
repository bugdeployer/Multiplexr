import 'package:app_shell/app_shell.dart' show AppSpacing;

import 'package:flutter/material.dart';

import '../../features/catalog/application/extension_catalog.dart';
import '../../features/plugins/application/contribution_registry.dart';
import '../../metadata/metadata_review_page.dart';
import 'plugin_manager.dart';
import 'plugin_contribution_page.dart';

class PluginToolsPage extends StatefulWidget {
  const PluginToolsPage({super.key, required this.manager});
  final PluginManager manager;
  @override
  State<PluginToolsPage> createState() => _PluginToolsPageState();
}

class _PluginToolsPageState extends State<PluginToolsPage> {
  List<PluginScope> available = [];
  PluginScope? scope;
  List<ExtensionTitle> titles = [];
  final selected = <String, ExtensionTitle>{};
  bool busy = true;
  String? error, cursor;
  List<Map<String, dynamic>> evidence = [];
  PluginManager get manager => widget.manager;
  @override
  void initState() {
    super.initState();
    manager.addListener(changed);
    load();
  }

  void changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    manager.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool next = false}) async {
    setState(() => busy = true);
    try {
      final scopes = await manager.scopes();
      if (scope != null &&
          !scopes.any(
            (s) => s.collection == scope!.collection && s.kind == scope!.kind,
          )) {
        scope = null;
        selected.clear();
        titles = [];
      }
      scope ??= scopes.firstOrNull;
      if (scope != null) {
        final page = await manager.gateway.catalog.titles(
          scope!.collection,
          scope!.kind,
          limit: 100,
          cursor: next ? cursor : null,
        );
        titles = page.items;
        cursor = page.nextCursor;
      }
      if (mounted) {
        setState(() {
          available = scopes;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Collection access ended. Refresh to choose an available collection.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> reviewFields(PluginProposal proposal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Apply extension fields to ${proposal.title.title}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(proposal.plugin.name),
              for (final entry in proposal.fields!.entries)
                Text(
                  '${entry.key.split(':').last}: ${entry.value ?? 'Remove value'}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await manager.withOrigin(proposal.plugin.id, () async {
        await manager.gateway.confirm(proposal.id);
        manager.signalCatalogChange({proposal.title.collection});
      });
      if (mounted) setState(() => error = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Access ended or data changed. Reopen the tool and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> run(PluginContribution entry) async {
    final current = scope;
    if (current == null) {
      return;
    }
    setState(() => busy = true);
    try {
      Map<String, Object?> params = {};
      if (entry.family == 'import.handler') {
        final file = await manager.openImport(entry.id, [current]);
        if (file == null) {
          return;
        }
        params = {'input': file['handle'], 'mime': file['mime']};
      }
      final result = await manager.invokeContribution(entry.id, params, [
        current,
      ], selection: selected.values.toList());
      if (entry.family == 'export.handler') {
        await manager.exportResult(entry.id, result, [current]);
      }
      if (entry.family == 'source.provider' && mounted) {
        setState(
          () => evidence = [
            for (final item in (result as Map)['items'] as List)
              Map<String, dynamic>.from(item as Map),
          ],
        );
      }
      if (mounted) {
        setState(() => error = null);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Extension operation failed or access changed. Library data is retained.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> review(PluginEditReview edit) async {
    try {
      final (target, candidate) = await manager.editReview(edit);
      if (!mounted) {
        return;
      }
      final applied = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MetadataReviewPage(target: target, candidate: candidate),
        ),
      );
      if (applied == true) {
        manager.dismissEdit(edit.id);
        await load();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Proposal expired or the title changed. Run the tool again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = scope;
    final allowed =
        current != null &&
        !manager.gateway.blocked() &&
        manager.gateway.authorized(current.collection, current.kind);
    return Scaffold(
      appBar: AppBar(title: const Text('Extension tools')),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          if (available.isEmpty && !busy)
            const Text(
              'Create and unlock a collection to use scoped extension tools.',
            ),
          if (available.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: current == null
                  ? null
                  : '${current.collection}/${current.kind.name}',
              decoration: const InputDecoration(labelText: 'Collection'),
              items: [
                for (final item in available)
                  DropdownMenuItem(
                    value: '${item.collection}/${item.kind.name}',
                    child: Text(item.label),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (id) {
                      setState(() {
                        scope = available.singleWhere(
                          (s) => '${s.collection}/${s.kind.name}' == id,
                        );
                        selected.clear();
                        evidence = [];
                        cursor = null;
                      });
                      load();
                    },
            ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (allowed) ...[
            Text('${selected.length} selected · at most 100'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in manager.registry.all.where(
                  (c) =>
                      {
                        'library.tool',
                        'import.handler',
                        'export.handler',
                        'source.provider',
                      }.contains(c.family) &&
                      c.plugin.collections.contains(current.collection),
                ))
                  OutlinedButton(
                    onPressed:
                        busy ||
                            entry.family != 'source.provider' &&
                                selected.isEmpty
                        ? null
                        : () => run(entry),
                    child: Text(entry.title),
                  ),
              ],
            ),
            for (final entry
                in manager.registry
                    .family('ui.action')
                    .where(
                      (c) => c.plugin.collections.contains(current.collection),
                    ))
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PluginContributionPage(
                            manager: manager,
                            contribution: entry,
                            scopes: [current],
                            selection: selected.length == 1
                                ? selected.values.toList()
                                : const [],
                          ),
                        ),
                      ),
                child: Text(entry.title),
              ),
            for (final title in titles)
              CheckboxListTile(
                title: Text(title.title),
                value: selected.containsKey(title.id),
                onChanged: busy
                    ? null
                    : (checked) => setState(() {
                        if (checked == true && selected.length < 100) {
                          selected[title.id] = title;
                        } else {
                          selected.remove(title.id);
                        }
                      }),
              ),
            if (cursor != null)
              TextButton(
                onPressed: busy ? null : () => load(next: true),
                child: const Text('Next 100 titles'),
              ),
          ],
          for (final item in evidence)
            ListTile(
              title: Text(item['name'] as String),
              subtitle: Text(
                '${item['mime']} · discovery evidence only${manager.registry.descriptorsForFile(item['name'] as String).map((d) => '\n${d.title} · ${d.definition['engine']}').join()}',
              ),
            ),
          for (final proposal in manager.gateway.proposals.where(
            (p) => p.fields != null && p.title.collection == scope?.collection,
          ))
            ListTile(
              title: Text(proposal.title.title),
              subtitle: Text(proposal.plugin.name),
              trailing: TextButton(
                onPressed: busy ? null : () => reviewFields(proposal),
                child: const Text('Review extension fields'),
              ),
            ),
          for (final edit in manager.edits)
            Card(
              child: ListTile(
                title: Text(edit.title.title),
                subtitle: Text(
                  '${edit.contribution.plugin.name}: ${edit.changes.keys.join(', ')}',
                ),
                trailing: TextButton(
                  onPressed: busy ? null : () => review(edit),
                  child: const Text('Review proposed changes'),
                ),
              ),
            ),
          TextButton(
            onPressed: busy ? null : () => load(),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
