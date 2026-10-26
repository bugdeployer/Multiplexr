import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell has no host app or media dependency', () {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final directive in RegExp(
        r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
      ).allMatches(file.readAsStringSync())) {
        final target = directive[1]!;
        if (target.startsWith('dart:')) continue;
        if (target.startsWith('package:')) {
          expect(
            target.split('/').first,
            isIn([
              'package:flutter',
              'package:crypto',
              'package:pixelarticons',
              'package:app_shell',
            ]),
            reason: file.path,
          );
        } else {
          final resolved = file.uri.resolve(target).toFilePath();
          expect(
            File(resolved).absolute.path.startsWith(
              '${Directory('lib').absolute.path}${Platform.pathSeparator}',
            ),
            isTrue,
            reason: '${file.path}: $target escapes package lib',
          );
        }
      }
    }
  });
}
