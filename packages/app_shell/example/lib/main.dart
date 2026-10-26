import 'package:flutter/material.dart';
import 'package:app_shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAppShell();
  runApp(const Example());
}

class Example extends StatefulWidget {
  const Example({super.key});
  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  final settings = ShellSettingsController(const MethodChannelShellPlatform());
  final navigation = ShellNavigationController(['notes', 'settings']);
  @override
  void initState() {
    super.initState();
    settings.load();
  }

  @override
  void dispose() {
    navigation.dispose();
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellApp(
    title: 'Notebook',
    settings: settings,
    home: ListenableBuilder(
      listenable: navigation,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(navigation.selectedIndex == 0 ? 'Notes' : 'Settings'),
        ),
        body: navigation.selectedIndex == 0
            ? const Center(child: Text('Your app content goes here.'))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'This preview has no native backend. Appearance changes last for this session; device security and notifications are unavailable.',
                  ),
                  const SizedBox(height: 20),
                  for (final section in ShellSettingsSection.values)
                    ListTile(
                      title: Text(section.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            appBar: AppBar(title: Text(section.name)),
                            body: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                ShellSettingsPanel(
                                  settings: settings,
                                  section: section,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
        bottomNavigationBar: ShellNavigationBar(
          selectedIndex: navigation.selectedIndex,
          onDestinationSelected: navigation.select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.note_outlined),
              label: 'Notes',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              label: 'Settings',
            ),
          ],
        ),
      ),
    ),
  );
}
