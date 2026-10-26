import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';

void main() {
  test(
    'persistence and metadata share application transaction ownership',
    () async {
      final owner = Object(),
          entered = Completer<void>(),
          release = Completer<void>();
      final events = <String>[];
      final persistence = MutationCoordinator.forOwner(owner)
          .run('shared', () async {
            events.add('persistence');
            entered.complete();
            await release.future;
          });
      await entered.future;
      final metadata = const OwnerApplicationMutations().run(
        owner,
        'shared',
        () async {
          events.add('metadata');
        },
      );
      await Future<void>.value();
      expect(events, ['persistence']);
      release.complete();
      await Future.wait([persistence, metadata]);
      expect(events, ['persistence', 'metadata']);
      expect(MutationCoordinator.forOwner(owner).revision('shared'), 2);
    },
  );

  test(
    'catalog and settings domain contracts stay independent of UI and shell',
    () {
      final directives = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
      final visited = <String>{};
      void check(File file) {
        final path = file.absolute.path;
        if (!visited.add(path)) return;
        for (final match in directives.allMatches(file.readAsStringSync())) {
          final target = match[1]!;
          expect(
            target.startsWith('package:flutter/'),
            isFalse,
            reason: '$path: $target',
          );
          expect(
            target.startsWith('package:app_shell/'),
            isFalse,
            reason: '$path: $target',
          );
          if (!target.contains(':')) {
            check(File.fromUri(file.uri.resolve(target)));
          }
        }
      }

      for (final root in [
        'lib/src/core/application',
        'lib/src/catalog/domain',
        'lib/src/settings/domain',
        'lib/src/reading/domain',
      ]) {
        for (final file in Directory(
          root,
        ).listSync(recursive: true).whereType<File>()) {
          if (file.path.endsWith('.dart')) check(file);
        }
      }
    },
  );
}
