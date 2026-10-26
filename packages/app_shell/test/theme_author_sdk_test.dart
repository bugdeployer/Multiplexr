import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_shell/theme_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in ['rounded-modern', 'square-minimal', 'stepped-retro']) {
    test('author $name package uses the same parser and round trips', () async {
      final source = File('theme_examples/$name.theme.json').readAsStringSync();
      final first = await ThemePackageAuthor.validate(source);
      final built = await ThemePackageAuthor.build(
        jsonDecode(source) as Map<String, dynamic>,
      );
      final second = await ThemePackageAuthor.validate(built);
      expect(second.toJson(), first.toJson());
    });
  }
  test(
    'author rejects legacy formats, executable fields and bad assets',
    () async {
      final data = jsonDecode(
        File('theme_examples/rounded-modern.theme.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      await expectLater(
        ThemePackageAuthor.validate(jsonEncode({...data, 'version': 1})),
        throwsFormatException,
      );
      await expectLater(
        ThemePackageAuthor.validate(jsonEncode({...data, 'script': 'evil()'})),
        throwsFormatException,
      );
      expect(
        () => ThemePackageAuthor.asset(
          path: '../escape.png',
          mime: 'image/png',
          bytes: Uint8List(1),
          author: 'Author',
          license: 'CC0',
        ),
        throwsFormatException,
      );
    },
  );
}
