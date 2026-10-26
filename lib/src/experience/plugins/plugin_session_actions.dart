import 'package:flutter/material.dart';

import 'plugin_contribution_page.dart';

class PluginSessionActions extends StatelessWidget {
  const PluginSessionActions({super.key});
  @override
  Widget build(BuildContext context) {
    final manager = PluginPlatformScope.maybeOf(context);
    if (manager == null || manager.gateway.blocked()) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in manager.registry.family('session.hook'))
          OutlinedButton(
            onPressed: () async {
              try {
                final sessions = await manager.sessionCandidates(entry.id);
                if (!context.mounted) {
                  return;
                }
                if (sessions.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No supported session is available with plugin access.',
                      ),
                    ),
                  );
                  return;
                }
                final selected = sessions.length == 1
                    ? sessions.single
                    : await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (dialog) => SimpleDialog(
                          title: const Text('Choose current session'),
                          children: [
                            for (final session in sessions)
                              SimpleDialogOption(
                                onPressed: () => Navigator.pop(dialog, session),
                                child: Text(session['kind'] as String),
                              ),
                          ],
                        ),
                      );
                if (selected == null || !context.mounted) {
                  return;
                }
                final result = await manager.prepareSession(entry.id, selected);
                if (!context.mounted) {
                  return;
                }
                final commands = (result as Map)['commands'] as List;
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: Text(entry.title),
                    content: Text(
                      'Apply these commands to the current ${selected['kind']} session?\n${commands.map((c) => c['kind'] == 'seek' ? 'Seek to ${c['position']['milliseconds']} ms' : c['kind']).join(', ')}',
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
                if (accepted == true) {
                  await manager.applySession(entry.id, selected, result);
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Session changed or plugin access ended. Try again.',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(entry.title),
          ),
      ],
    );
  }
}
