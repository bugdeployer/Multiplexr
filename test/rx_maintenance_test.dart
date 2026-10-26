import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/application/maintenance.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/features/backup/application/backup_workflow.dart';
import 'package:multiplexr/src/library/legacy_backup_port.dart';

import 'media_foundation_test.dart' show SharedStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('restore drains foreground snapshot queries after revocation without admitting new reads', () async {
    final gate = Maintenance();
    final release = Completer<void>();
    final events = <String>[];
    final read = gate.query(() async {
      events.add('read');
      await release.future;
      events.add('read-complete');
    });
    gate.register(invalidate: () => events.add('revoke'));
    final restore = gate.exclusively(() async => events.add('restore'));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['read', 'revoke']);
    await expectLater(gate.query(() async {}), throwsA(isA<MaintenanceBusy>()));
    release.complete();
    await read;
    await restore;
    expect(events, ['read', 'revoke', 'read-complete', 'restore']);
  });
  test('a stalled snapshot query aborts restore with no replacement and releases admission', () async {
    final gate = Maintenance(
      queryDrainTimeout: const Duration(milliseconds: 5),
    );
    final release = Completer<void>();
    final read = gate.query(() => release.future);
    var replaced = false;
    await expectLater(
      gate.exclusively(() async {
        replaced = true;
      }),
      throwsA(isA<MaintenanceBusy>()),
    );
    expect(replaced, false);
    expect(gate.exclusive, false);
    release.complete();
    await read;
    await gate.exclusively(() async {});
  });
  test(
    'maintenance revokes all generations before draining and replacing',
    () async {
      final gate = Maintenance();
      final generation = gate.generation;
      final events = <String>[];
      final release = Completer<void>();
      final draining = Completer<void>();
      final detach = gate.register(
        invalidate: () => events.add('invalidate'),
        drain: () async {
          expect(gate.isCurrent(generation), isFalse);
          events.add('drain');
          draining.complete();
          await release.future;
        },
      );
      final restoring = gate.exclusively(() async => events.add('replace'));
      await draining.future;
      expect(events, ['invalidate', 'drain']);
      expect(() => gate.register(), throwsA(isA<MaintenanceBusy>()));
      release.complete();
      await restoring;
      expect(events, ['invalidate', 'drain', 'replace']);
      expect(gate.isCurrent(generation), isFalse);
      detach();
      await gate.exclusively(() async {});
      expect(events.length, 3);
    },
  );
  test('failed drain aborts restore, drains other resources and keeps old sessions revoked', () async {
    final gate = Maintenance();
    final old = gate.generation;
    var drained = false, replaced = false;
    final detach = gate.register(
      drain: () async => throw StateError('native close'),
    );
    gate.register(
      drain: () async {
        drained = true;
      },
    );
    await expectLater(
      gate.exclusively(() async {
        replaced = true;
      }),
      throwsStateError,
    );
    expect(drained, isTrue);
    expect(replaced, isFalse);
    expect(gate.isCurrent(old), isFalse);
    expect(gate.exclusive, isFalse);
    detach();
    await gate.exclusively(() async {});
  });
  test(
    'maintenance is shared by owner and excludes other tasks until released',
    () async {
      final owner = Object();
      final gate = Maintenance.forOwner(owner);
      expect(identical(gate, Maintenance.forOwner(owner)), isTrue);
      final entered = Completer<void>(), release = Completer<void>();
      final work = gate.exclusively(() async {
        await gate.activity(() async {}); // restore's own reload is allowed
        entered.complete();
        await release.future;
      });
      await entered.future;
      expect(gate.activity(() async {}), throwsA(isA<MaintenanceBusy>()));
      expect(gate.exclusively(() async {}), throwsA(isA<MaintenanceBusy>()));
      release.complete();
      await work;
      await gate.activity(() async {});
      expect(gate.exclusive, isFalse);
    },
  );
  test(
    'active work prevents maintenance and failure releases both leases',
    () async {
      final gate = Maintenance();
      final release = Completer<void>();
      final work = gate.activity(() => release.future);
      expect(gate.exclusively(() async {}), throwsA(isA<MaintenanceBusy>()));
      release.complete();
      await work;
      await expectLater(
        gate.exclusively(() async => throw StateError('disk')),
        throwsStateError,
      );
      await expectLater(
        gate.activity(() async => throw StateError('job')),
        throwsStateError,
      );
      expect(gate.active, isFalse);
      await gate.exclusively(() async {});
    },
  );
  test(
    'restore cannot overtake a queued read-modify-write transaction',
    () async {
      final store = SharedStore();
      final library = createLibraryController(store);
      final entered = Completer<void>(), release = Completer<void>();
      final write = JsonStateRepository(store).update('audit', (_) async {
        entered.complete();
        await release.future;
        return {'retained': true};
      });
      await entered.future;
      final restore = LegacyBackupPort(
        library,
        authentication: () async => true,
      );
      await expectLater(restore.restore({}), throwsA(isA<BackupBusy>()));
      release.complete();
      await write;
      expect((await store.readState('audit'))?['retained'], isTrue);
      library.dispose();
    },
  );
}
