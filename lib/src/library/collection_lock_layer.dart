import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/settings/application/collection_privacy.dart';
import 'library_models.dart';
import 'library_controller.dart';

/// Above Navigator: detail routes, dialogs and playback share the collection gate.
class CollectionLockLayer extends StatefulWidget {
  const CollectionLockLayer({
    super.key,
    required this.library,
    required this.platform,
    required this.onClose,
    required this.child,
  });
  final LibraryController library;
  final CollectionPrivacy platform;
  final VoidCallback onClose;
  final Widget child;
  @override
  State<CollectionLockLayer> createState() => _CollectionLockLayerState();
}

class _CollectionLockLayerState extends State<CollectionLockLayer>
    with WidgetsBindingObserver {
  bool busy = false, covered = false;
  bool? privacy;
  String? error;
  VideoCollection? get collection => widget.library.collections
      .where((c) => c.id == widget.library.activeCollectionId)
      .firstOrNull;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.library.addListener(changed);
    changed();
  }

  void changed() {
    final enabled = collection?.locked == true;
    if (privacy != enabled) {
      privacy = enabled;
      widget.platform.collectionPrivacy(enabled).catchError((Object _) {});
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (busy) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      covered = true;
      widget.library.relockCollections();
    } else if (state == AppLifecycleState.inactive) {
      setState(() => covered = true);
    } else if (state == AppLifecycleState.resumed) {
      setState(() => covered = false);
    }
  }

  Future<void> unlock() async {
    final id = collection?.id;
    if (id == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.platform.collectionPrivacy(true);
      final authenticated = await widget.platform.authenticate();
      if (!mounted || collection?.id != id) return;
      if (authenticated) {
        covered = false;
        widget.library.authorizeCollection(id);
      } else {
        setState(() => error = 'Not unlocked. Try again.');
      }
    } on PlatformException catch (failure) {
      if (mounted) {
        setState(() => error = failure.message ?? 'Could not authenticate.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Device authentication is unavailable.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.library.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden =
        collection?.locked == true &&
        (covered || !widget.library.canAccessCollection(collection!.id));
    return PopScope(
      canPop: !hidden,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) widget.onClose();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: hidden,
            child: TickerMode(enabled: !hidden, child: widget.child),
          ),
          if (hidden &&
              covered &&
              widget.library.canAccessCollection(collection!.id))
            Positioned.fill(
              child: ColoredBox(color: Theme.of(context).colorScheme.surface),
            )
          else if (hidden)
            Positioned.fill(
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(AppIconRole.lock, size: 40),
                          const AppGap(20),
                          const Text('LOCKED COLLECTION'),
                          const AppGap(8),
                          Text(
                            collection?.name ?? 'Collection locked',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const AppGap(12),
                          const Text(
                            'Unlock this collection with biometrics or your device screen lock.',
                            textAlign: TextAlign.center,
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(error!),
                            ),
                          const AppGap(24),
                          FilledButton.icon(
                            onPressed: busy ? null : unlock,
                            icon: const AppIcon(AppIconRole.biometric),
                            label: Text(
                              busy ? 'Authenticating…' : 'Unlock collection',
                            ),
                          ),
                          TextButton(
                            onPressed: busy ? null : widget.onClose,
                            child: const Text('Back to library'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
