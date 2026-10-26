import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'theme_definition.dart';

bool _licensesRegistered = false;

/// Load bundled fonts/themes and register their third-party notices once.
Future<void> initializeAppShell() async {
  if (!_licensesRegistered) {
    _licensesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        ['Silkscreen'],
        await rootBundle.loadString('packages/app_shell/assets/fonts/OFL.txt'),
      );
      yield LicenseEntryWithLineBreaks(
        ['Pixelarticons'],
        await rootBundle.loadString(
          'packages/app_shell/assets/licenses/Pixelarticons-LICENSE.txt',
        ),
      );
    });
  }
  await AppThemeDefinition.loadBundled();
}
