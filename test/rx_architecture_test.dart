import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'domain and application dependency graphs stay framework and I/O free',
    () {
      final visited = <String>{};
      final directives = RegExp(
        r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
      );
      void check(File file) {
        if (!visited.add(file.absolute.path)) return;
        for (final directive in directives.allMatches(
          file.readAsStringSync(),
        )) {
          final uri = directive[1]!;
          expect(
            uri.startsWith('package:flutter/') ||
                uri.startsWith('package:app_shell/') ||
                {'dart:io', 'dart:ui', 'dart:ffi'}.contains(uri),
            false,
            reason: '${file.path} -> $uri: use an application port',
          );
          if (!uri.contains(':')) check(File.fromUri(file.uri.resolve(uri)));
          if (uri.startsWith('package:multiplexr/')) {
            check(File('lib/${uri.substring('package:multiplexr/'.length)}'));
          }
        }
      }

      for (final file in Directory(
        'lib/src',
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path.replaceAll('\\', '/');
        if (path.endsWith('.dart') &&
            (path.contains('/domain/') || path.contains('/application/'))) {
          check(file);
        }
      }
      expect(visited, isNotEmpty);
    },
  );
}
