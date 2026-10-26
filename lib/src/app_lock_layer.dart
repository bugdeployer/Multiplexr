import 'package:app_shell/app_shell.dart' as shell;

import 'settings.dart';

class AppLockLayer extends shell.AppLockLayer {
  const AppLockLayer({
    super.key,
    required SettingsController settings,
    required super.child,
  }) : super(settings: settings, appName: 'Multiplexr');
}
