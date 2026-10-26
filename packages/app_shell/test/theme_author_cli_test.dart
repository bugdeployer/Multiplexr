import 'dart:io';

import 'package:app_shell/theme_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Platform.environment['APP_SHELL_THEME_INPUT'];
  final output = Platform.environment['APP_SHELL_THEME_RESULT'];
  test(
    'validate author package with the production theme compiler',
    () async {
      final file = File(source!);
      if (file.lengthSync() > 4194304) {
        throw const FormatException('Theme exceeds 4 MiB.');
      }
      final theme = await ThemePackageAuthor.validate(file.readAsStringSync());
      File(output!).writeAsStringSync(theme.encode());
    },
    skip: source == null || output == null
        ? 'Run through tool/theme_author.py'
        : false,
  );
}
