import 'package:flutter/material.dart';

/// Keeps package routes inside the app's persistent navigation area.
class PluginNavigationShell extends StatefulWidget {
  const PluginNavigationShell({
    super.key,
    required this.page,
    required this.bottomBar,
  });

  final Widget page;
  final Widget? Function() bottomBar;

  @override
  State<PluginNavigationShell> createState() => _PluginNavigationShellState();
}

class _PluginNavigationShellState extends State<PluginNavigationShell> {
  final navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: NavigatorPopHandler<void>(
      onPopWithResult: (result) => navigator.currentState!.pop(),
      child: Navigator(
        key: navigator,
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => widget.page),
      ),
    ),
    bottomNavigationBar: widget.bottomBar(),
  );
}
