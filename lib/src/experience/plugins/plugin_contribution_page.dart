import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';

import '../../features/plugins/application/contribution_registry.dart';
import '../../features/catalog/application/extension_catalog.dart';
import 'plugin_manager.dart';

class PluginPlatformScope extends InheritedNotifier<PluginManager> {
  const PluginPlatformScope({
    super.key,
    required PluginManager manager,
    required super.child,
  }) : super(notifier: manager);
  static PluginManager? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PluginPlatformScope>()?.notifier;
  static PluginManager? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PluginPlatformScope>()
      ?.notifier;
}

class PluginContributionPage extends StatefulWidget {
  const PluginContributionPage({
    super.key,
    required this.manager,
    required this.contribution,
    this.scopes = const [],
    this.selection = const [],
  });
  final PluginManager manager;
  final PluginContribution contribution;
  final List<PluginScope> scopes;
  final List<ExtensionTitle> selection;
  @override
  State<PluginContributionPage> createState() => _PluginContributionPageState();
}

class _PluginContributionPageState extends State<PluginContributionPage> {
  Object? view;
  String? error;
  bool busy = false;
  bool get active =>
      widget.manager.registry.current(widget.contribution) &&
      !widget.manager.gateway.blocked() &&
      widget.scopes.every(
        (s) => widget.manager.gateway.authorized(s.collection, s.kind),
      );
  @override
  void initState() {
    super.initState();
    widget.manager.addListener(changed);
    load(widget.contribution.id);
  }

  void changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(changed);
    if (busy) {
      widget.manager.gateway.revoke(widget.contribution.plugin.id);
      widget.manager.backend.command('cancel').catchError((_) => null);
    }
    super.dispose();
  }

  Future<void> load(String id) async {
    setState(() => busy = true);
    try {
      final entry = widget.manager.registry.require(id);
      if (entry.plugin.id != widget.contribution.plugin.id ||
          !entry.family.startsWith('ui.')) {
        throw const PluginDenied();
      }
      final result = await widget.manager.invokeContribution(
        id,
        {},
        widget.scopes,
        selection: widget.selection,
      );
      if (mounted && active) {
        setState(() {
          view = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Extension view failed or access ended.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget node(Map value) {
    switch (value['kind']) {
      case 'text':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(value['text'] as String),
        );
      case 'action':
        return FilledButton(
          onPressed: busy ? null : () => load(value['action'] as String),
          child: Text(value['label'] as String),
        );
      case 'group':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in value['children'] as List) node(child as Map),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.contribution.title)),
    body: !active
        ? const Center(child: Text('Extension access ended.'))
        : ListView(
            padding: AppSpacing.of(context).all(20),
            children: [
              Text(
                widget.contribution.plugin.name,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              if (view is Map) node(view as Map),
              TextButton(
                onPressed: busy ? null : () => load(widget.contribution.id),
                child: const Text('Refresh'),
              ),
            ],
          ),
  );
}

/// Shared detail extension slot. Nothing executes until the user opens a section.
class PluginDetailExtensions extends StatelessWidget {
  const PluginDetailExtensions({
    super.key,
    required this.collection,
    required this.kind,
    required this.titleId,
  });
  final String collection, titleId;
  final ExtensionMedia kind;
  @override
  Widget build(BuildContext context) {
    final host = PluginPlatformScope.maybeOf(context);
    if (host == null ||
        host.gateway.blocked() ||
        !host.gateway.authorized(collection, kind)) {
      return const SizedBox.shrink();
    }
    final entries = host.registry.all
        .where(
          (entry) =>
              {'ui.section', 'ui.action'}.contains(entry.family) &&
              entry.plugin.collections.contains(collection),
        )
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          ListTile(
            title: Text(entry.title),
            subtitle: Text(entry.plugin.name),
            trailing: const AppIcon(AppIconRole.disclosure),
            onTap: () async {
              try {
                final title = (await host.gateway.catalog.source.titles(
                  collection,
                  kind,
                )).where((t) => t.id == titleId).firstOrNull;
                if (!context.mounted ||
                    title == null ||
                    !host.registry.current(entry) ||
                    host.gateway.blocked() ||
                    !host.gateway.authorized(collection, kind)) {
                  return;
                }
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PluginContributionPage(
                      manager: host,
                      contribution: entry,
                      scopes: [
                        PluginScope(collection, kind, 'Selected collection'),
                      ],
                      selection: [title],
                    ),
                  ),
                );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Extension unavailable. Reopen the title to retry.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
      ],
    );
  }
}
