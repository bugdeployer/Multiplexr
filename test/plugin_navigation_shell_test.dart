import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/plugins/plugin_navigation_shell.dart';

void main() {
  testWidgets(
    'package routes retain navigation and return to the main section',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (routeContext) => PluginNavigationShell(
                      bottomBar: () => NavigationBar(
                        selectedIndex: 2,
                        onDestinationSelected: (_) =>
                            Navigator.pop(routeContext),
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home),
                            label: 'Library',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.grid_view),
                            label: 'Spaces',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.settings),
                            label: 'Settings',
                          ),
                        ],
                      ),
                      page: Builder(
                        builder: (context) => Scaffold(
                          appBar: AppBar(title: const Text('Plugins')),
                          body: TextButton(
                            onPressed: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('Manage')),
                                ),
                              ),
                            ),
                            child: const Text('Open manage'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open plugins'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open plugins'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Open manage'));
      await tester.pumpAndSettle();
      expect(find.text('Manage'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open manage'), findsOneWidget);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Open plugins'), findsOneWidget);
      expect(find.text('Manage'), findsNothing);
    },
  );
}
