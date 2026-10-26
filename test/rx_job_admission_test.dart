import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/application/job_admission.dart';

class Receipts implements JobReceiptStore {
  List<JobReceipt> saved = [];
  bool fail = false;
  @override
  Future<List<JobReceipt>> read() async => List.of(saved);
  @override
  Future<void> write(List<JobReceipt> value) async {
    if (fail) throw StateError('disk');
    saved = List.of(value);
  }
}

void main() {
  test(
    'cancellation during durable admission never starts the operation',
    () async {
      final jobs = JobAdmission();
      var cancelled = true, ran = false;
      final work = jobs.run<void>(
        'metadata:a',
        ['a'],
        () async {
          ran = true;
        },
        admitted: () {
          cancelled = false;
        },
        cancelled: () => cancelled,
        cancelledResult: () {},
      );
      cancelled = true;
      await work;
      expect(ran, isFalse);
      expect(
        (await jobs.status((_) => true)).single.outcome,
        JobOutcome.cancelled,
      );
    },
  );
  test('one owner coalesces identical work and excludes other writers in its scope', () async {
    final jobs = JobAdmission();
    final release = Completer<int>();
    var calls = 0;
    final first = jobs.run('metadata:music:a', ['a'], () {
      calls++;
      return release.future;
    });
    final attached = jobs.run('metadata:music:a', ['a'], () async => 99);
    await expectLater(
      jobs.run('scan:a', ['a'], () async => 0),
      throwsA(isA<JobAdmissionBusy>()),
    );
    await expectLater(
      jobs.run('global', [], () async => 0),
      throwsA(isA<JobAdmissionBusy>()),
    );
    expect(
      () => jobs.run('metadata:music:a', ['b'], () async => 0),
      throwsArgumentError,
    );
    expect(await jobs.run('scan:b', ['b'], () async => 7), 7);
    release.complete(3);
    expect(await first, 3);
    expect(await attached, 3);
    expect(calls, 1);
    expect(jobs.running, isFalse);
  });
  for (final family in ['video', 'music', 'audiobooks', 'reading', 'scan']) {
    test(
      '$family durable running receipt recovers as interrupted without replay',
      () async {
        final disk = Receipts();
        final oldProcess = JobAdmission()..configure(disk);
        final entered = Completer<void>(), release = Completer<void>();
        final key = '$family:collection';
        final work = oldProcess.run(key, ['collection'], () async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        expect(disk.saved.single.outcome, JobOutcome.running);
        final recoveredDisk = Receipts()..saved = List.of(disk.saved);
        final newProcess = JobAdmission()..configure(recoveredDisk);
        expect(
          (await newProcess.status((_) => true)).single.outcome,
          JobOutcome.interrupted,
        );
        expect(newProcess.running, isFalse);
        expect(await newProcess.status((_) => false), isEmpty);
        release.complete();
        await work;
      },
    );
  }
  test('admission persistence failure never starts side effects and releases scope', () async {
    final disk = Receipts()..fail = true;
    final jobs = JobAdmission()..configure(disk);
    var ran = false;
    await expectLater(
      jobs.run('scan:a', ['a'], () async {
        ran = true;
      }),
      throwsStateError,
    );
    expect(ran, isFalse);
    expect(jobs.running, isFalse);
    disk.fail = false;
    await jobs.run('retry:a', ['a'], () async {
      ran = true;
    });
    expect(ran, isTrue);
  });
  test('cancelled and failed outcomes remain distinct and subsequent work can proceed', () async {
    final disk = Receipts();
    final jobs = JobAdmission()..configure(disk);
    await jobs.run('cancelled:a', ['a'], () async {}, cancelled: () => true);
    await expectLater(
      jobs.run('failed:a', ['a'], () async => throw StateError('provider')),
      throwsStateError,
    );
    await jobs.run('next:a', ['a'], () async {});
    expect((await jobs.status((_) => true)).map((r) => r.outcome), [
      JobOutcome.cancelled,
      JobOutcome.failed,
      JobOutcome.completed,
    ]);
  });
}
