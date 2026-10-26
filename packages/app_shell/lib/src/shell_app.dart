import 'package:flutter/material.dart';

import 'app_lock_layer.dart';
import 'settings.dart';

/// Owns common presentation and lifecycle. The host owns controller disposal.
class ShellApp extends StatefulWidget {
  const ShellApp({
    super.key,
    required this.title,
    required this.settings,
    required this.home,
    this.navigatorKey,
    this.contentGuard,
    this.onDeviceError,
  });
  final String title;
  final ShellSettingsController settings;
  final Widget home;
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget Function(BuildContext, Widget)? contentGuard;
  final ValueChanged<Object>? onDeviceError;
  @override
  State<ShellApp> createState() => _ShellAppState();
}

class _ShellAppState extends State<ShellApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    brightness();
  }

  void brightness() => widget.settings.systemBrightness(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );
  @override
  void didChangePlatformBrightness() => brightness();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = widget.settings;
    if (state == AppLifecycleState.inactive) s.obscure();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      s.background();
    }
    if (state == AppLifecycleState.resumed) {
      s.foreground();
      s.refresh().catchError((Object error) {
        if (mounted) widget.onDeviceError?.call(error);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) => MaterialApp(
      title: widget.title,
      navigatorKey: widget.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: widget.settings.theme,
      themeAnimationDuration: widget.settings.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              widget.settings.reduceMotion ||
              MediaQuery.of(context).disableAnimations,
        ),
        child: AppLockLayer(
          settings: widget.settings,
          appName: widget.title,
          child: widget.contentGuard?.call(context, child!) ?? child!,
        ),
      ),
      home: widget.home,
    ),
  );
}

/// Stable destination identities keep app-specific routes out of the shell.
class ShellNavigationController extends ChangeNotifier {
  ShellNavigationController(Iterable<String> destinations)
    : destinations = List.unmodifiable(destinations) {
    if (this.destinations.length < 2 ||
        this.destinations.toSet().length != this.destinations.length ||
        this.destinations.any((id) => id.trim().isEmpty)) {
      throw ArgumentError(
        'Provide at least two unique, nonempty destination IDs.',
      );
    }
  }
  final List<String> destinations;
  int _index = 0;
  int get selectedIndex => _index;
  String get selectedId => destinations[_index];
  void select(int index) {
    RangeError.checkValidIndex(index, destinations);
    if (_index == index) return;
    _index = index;
    notifyListeners();
  }

  void selectId(String id) {
    final index = destinations.indexOf(id);
    if (index < 0) throw ArgumentError.value(id, 'id', 'Unknown destination');
    select(index);
  }
}

class ShellNavigationBar extends StatelessWidget {
  const ShellNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.animationDuration,
  });
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;
  final Duration? animationDuration;
  @override
  Widget build(BuildContext context) => NavigationBar(
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
    destinations: destinations,
    animationDuration: animationDuration,
  );
}
