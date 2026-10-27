import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'plugin_manager.dart';
import 'plugin_manager_page.dart';

/// Shared package entry point; themes are validated data and never runtime code.
class PackageManagerPage extends StatelessWidget {
  const PackageManagerPage({
    super.key,
    required this.manager,
    required this.settings,
    this.onBack,
  });
  final VoidCallback? onBack;
  final PluginManager manager;
  final ShellSettingsController settings;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Plugins & themes'),
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Extensions'),
            Tab(text: 'Themes'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          PluginManagerPage(manager: manager, embedded: true),
          ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListView(
              padding: AppSpacing.of(context).all(20),
              children: [
                AppSection(
                  title: 'Theme packages',
                  description: 'Preview fonts, icons, colors and component styles before installing.',
                  children: [
                    Padding(
                      padding: AppSpacing.of(context).all(16),
                      child: ThemePicker(settings: settings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
