import 'src/experience/plugins/plugin_contribution_page.dart';
import 'src/media/artwork_images.dart';
import 'src/media/source_recovery.dart';
import 'src/library/native_player.dart' show PlaybackWindow;
import 'src/bootstrap/app_composition.dart';

import 'package:flutter/material.dart';

import 'src/platform_service.dart';
import 'src/settings.dart';
import 'src/shell.dart';

import 'package:app_shell/app_shell.dart' show ShellApp, initializeAppShell;

import 'src/library/library_controller.dart';
import 'src/library/library_service.dart';
import 'src/library/collection_lock_layer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAppShell();
  runApp(const MultiplexrApp());
}

class MultiplexrApp extends StatefulWidget {
  const MultiplexrApp({
    super.key,
    this.platform = const PlatformService(),
    this.libraryService = const LibraryService(),
  });
  final PlatformService platform;
  final LibraryService libraryService;
  @override
  State<MultiplexrApp> createState() => _MultiplexrAppState();
}

class _MultiplexrAppState extends State<MultiplexrApp> {
  late final composition = AppComposition(
    platform: widget.platform,
    libraryService: widget.libraryService,
  );
  SettingsController get settings => composition.settings;
  final navigator = GlobalKey<NavigatorState>();
  LibraryController get library => composition.library;
  @override
  void initState() {
    super.initState();
    settings.systemBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    PlaybackWindow.instance.addListener(playbackVisibilityChanged);
    settings.load();
    library.load();
  }

  void playbackVisibilityChanged() {
    final window = PlaybackWindow.instance;
    if (window.active && !settings.locked) {
      settings.foreground();
    } else if (window.backgrounded) {
      settings.background();
    }
  }

  @override
  void dispose() {
    PlaybackWindow.instance.removeListener(playbackVisibilityChanged);
    composition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([settings, library]),
    builder: (context, _) => ArtworkImages(
      local: composition.localArtwork,
      child: ShellApp(
        navigatorKey: navigator,
        title: 'Multiplexr',
        settings: settings,
        contentGuard: (context, child) => CollectionLockLayer(
          library: library,
          platform: widget.platform,
          onClose: () {
            navigator.currentState?.popUntil((route) => route.isFirst);
            library.endCollectionSession();
          },
          child: PluginPlatformScope(
            manager: composition.plugins,
            child: SourceRecoveryScope(library: library, child: child),
          ),
        ),
        home: AppShell(
          settings: settings,
          library: library,
          sessions: composition.sessions,
          plugins: composition.plugins,
        ),
      ),
    ),
  );
}
