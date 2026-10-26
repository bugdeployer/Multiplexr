import 'pixel_theme.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// Sits above Navigator so dialogs and full-screen routes cannot bypass
/// the same privacy gate used by the home screen.
class AppLockLayer extends StatefulWidget {
  const AppLockLayer({
    super.key,
    required this.settings,
    required this.child,
    this.appName = 'App',
  });
  final ShellSettingsController settings;
  final Widget child;
  final String appName;
  @override
  State<AppLockLayer> createState() => _AppLockLayerState();
}

class _AppLockLayerState extends State<AppLockLayer> {
  bool busy = false;
  String? failure;
  Future<void> unlock() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      if (!await widget.settings.unlock() && mounted) {
        setState(() => failure = 'Not unlocked. You can try again.');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => failure = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final hidden = s.ready && (s.locked || s.covered);
    return Stack(
      children: [
        Offstage(
          offstage: hidden,
          child: TickerMode(enabled: !hidden, child: widget.child),
        ),
        if (hidden)
          if (!s.locked)
            Positioned.fill(
              child: ColoredBox(color: Theme.of(context).colorScheme.surface),
            )
          else
            Positioned.fill(
              child: Scaffold(
                body: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(AppIconRole.lock, size: 40, color: s.accent),
                          const AppGap(24),
                          Text(
                            '${widget.appName} is locked',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const AppGap(12),
                          Text(
                            s.error ??
                                (s.useBiometrics
                                    ? 'Unlock with biometrics or your device screen lock.'
                                    : 'Unlock with your device screen lock.'),
                            textAlign: TextAlign.center,
                          ),
                          if (failure != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(failure!),
                            ),
                          const AppGap(24),
                          FilledButton.icon(
                            onPressed: busy || s.error != null ? null : unlock,
                            icon: const AppIcon(AppIconRole.biometric),
                            label: Text(busy ? 'Authenticating…' : 'Unlock'),
                          ),
                          if (!s.secureDevice)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : s.platform.securitySettings,
                              child: const Text('Set up device screen lock'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
