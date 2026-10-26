import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/application/clock.dart';
import 'package:multiplexr/src/features/backup/application/backup_workflow.dart';
import 'package:multiplexr/src/features/backup/application/backup_document.dart';
import 'package:multiplexr/src/features/jobs/application/job_registry.dart';
import 'package:multiplexr/src/features/jobs/application/activity_queries.dart';
import 'package:multiplexr/src/features/catalog/application/collection_presenter.dart';
import 'package:multiplexr/src/features/settings/application/device_settings.dart';
import 'package:multiplexr/src/features/settings/application/reader_preference_commands.dart';
import 'package:multiplexr/src/features/reading/application/reading_progress_store.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';

import 'package:multiplexr/src/features/sources/application/reading_scan_jobs.dart';
import 'package:multiplexr/src/features/sources/application/reading_scan_workflow.dart';
import 'package:multiplexr/src/features/sources/application/reading_scan_plan.dart';

import 'reading_r1_test.dart' show base;
import 'media_foundation_test.dart' show SharedStore;

class ClockStub implements Clock {
  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(12345);
}

class BackupStub implements BackupPort {
  bool locked = false, allowed = true, failTimestamp = false;
  int exports = 0, restores = 0, auths = 0;
  bool busy = false;
  String? text;
  final checks = <String>[];
  List<BackupVerificationTarget> targets = [];
  @override
  Future<bool> authenticate() async {
    auths++;
    return allowed;
  }

  @override
  Future<bool> hasLockedCollections() async => locked;
  @override
  Future<int> lastExport() async => 0;
  @override
  Future<void> saveLastExport(int milliseconds) async {
    expect(milliseconds, 12345);
    if (failTimestamp) throw StateError('disk');
  }

  @override
  Future<bool> export() async {
    exports++;
    return true;
  }

  @override
  Future<String?> pick() async => text;
  @override
  Future<void> prepareRestore() async {
    if (busy) throw const BackupBusy();
  }

  @override
  Future<void> restore(Map<String, dynamic> document) async {
    restores++;
  }

  @override
  Future<LibraryRoot?> pickRoot() async => const LibraryRoot('new', 'New');
  @override
  Future<List<BackupVerificationTarget>> verificationTargets() async => targets;
  @override
  Future<bool> verify(BackupVerificationTarget target) async {
    checks.add(target.id);
    return target.id != 'failed';
  }
}

class JobStub implements CollectionJob, PreparingJob {
  @override
  bool preparing = false;
  @override
  bool running = true;
  @override
  int done = 0, total = 2;
  int cancellations = 0, disposals = 0;
  @override
  void cancel() {
    cancellations++;
  }

  @override
  void dispose() {
    disposals++;
  }
}

class DeviceStub implements DeviceSettingsPort {
  bool allow = false;
  final writes = <String>[];
  @override
  Future<bool> authenticate() async => allow;
  @override
  Future<void> setLock(bool enabled) async {
    writes.add('lock');
  }

  @override
  Future<void> saveSecurity(Map<String, Object> values) async {
    writes.add('security');
  }

  @override
  Future<bool> requestNotifications() async => allow;
  @override
  Future<void> setNotifications(bool enabled) async {
    writes.add('notifications');
  }

  @override
  Future<void> setCategory(String id, bool enabled) async {
    writes.add('category');
  }

  @override
  Future<void> savePreferences(Map<String, Object> values) async {
    writes.add('preferences');
  }

  @override
  Future<void> openSecuritySettings() async {
    writes.add('settings');
  }
}

class ReadingStoreStub implements ReadingProgressStore {
  ReadingCatalog catalog = ReadingCodec.decode(base());
  @override
  Future<ReadingCatalog> read() async => catalog;
  @override
  Future<void> update(
    Future<ReadingCatalog> Function(ReadingCatalog) change,
  ) async {
    catalog = await change(catalog);
  }
}

class ActivityStub implements ActivitySource {
  final gate = Completer<Map<String, dynamic>?>();
  @override
  Future<Map<String, dynamic>?> journal(VideoCollection collection) =>
      gate.future;
  @override
  Future<Set<String>> eligibleAudioIds(VideoCollection collection) async => {};
}

class ScanTaskStub implements ReadingScanTask {
  final gate = Completer<ReadingScanPreview>();
  int previews = 0, applies = 0, cancellations = 0;
  @override
  Future<ReadingScanPreview> preview(String id) {
    previews++;
    return gate.future;
  }

  @override
  Future<void> apply(String id, ReadingScanPreview preview) async {
    applies++;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

ReadingScanPreview scanPreview() => ReadingScanPreview(
  collectionId: 'c',
  requestId: 'test',
  complete: true,
  added: 1,
  relinked: 0,
  missing: 0,
);
Map<String, dynamic> document({bool locked = false}) => {
  'format': 'multiplexr-library',
  'version': 1,
  'collections': [
    {
      'id': 'c',
      'locked': locked,
      'roots': [
        {'uri': 'old', 'name': 'Old', 'contentSubtype': 'tv'},
      ],
    },
  ],
  'assets': [
    {'collectionId': 'c', 'id': 'v', 'rootUri': 'old', 'positionMs': 123},
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BackupWorkflow workflow(BackupStub port, {bool Function()? active}) =>
      BackupWorkflow(port, clock: ClockStub(), active: active ?? () => true);
  test('automatic reading scan survives route reattachment without duplicate discovery', () async {
    final task = ScanTaskStub();
    var changes = 0, creates = 0;
    final jobs = ReadingScanJobs(
      () {
        creates++;
        return task;
      },
      authorized: (_) => true,
      changed: () {
        changes++;
      },
    );
    final firstRoute = jobs.run('c'), secondRoute = jobs.run('c');
    expect(secondRoute, same(firstRoute));
    expect(creates, 1);
    task.gate.complete(scanPreview());
    expect(await firstRoute, isTrue);
    expect(await secondRoute, isTrue);
    expect(task.previews, 1);
    expect(task.applies, 1);
    expect(jobs.running, isEmpty);
    expect(changes, 2);
    jobs.dispose();
  });
  test(
    'revoked automatic reading scan cannot apply a late discovery',
    () async {
      final task = ScanTaskStub();
      var allowed = true;
      final jobs = ReadingScanJobs(
        () => task,
        authorized: (_) => allowed,
        changed: () {},
      );
      final scan = jobs.run('c');
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      jobs.refreshAccess();
      task.gate.complete(scanPreview());
      await expectLater(scan, throwsStateError);
      expect(task.applies, 0);
      expect(task.cancellations, 1);
      jobs.dispose();
    },
  );
  test(
    'cancellation before reading discovery starts performs no source I/O',
    () async {
      final task = ScanTaskStub();
      final jobs = ReadingScanJobs(
        () => task,
        authorized: (_) => true,
        changed: () {},
      );
      final scan = jobs.run('c');
      await jobs.cancel('c');
      await expectLater(scan, throwsStateError);
      expect(task.previews, 0);
      expect(task.applies, 0);
      expect(jobs.running, isEmpty);
      jobs.dispose();
    },
  );
  test('job preparation counts as an active writer for restore exclusion', () {
    final registry = ApplicationJobs();
    final job = registry.obtain(
      'metadata:c',
      JobStub.new,
      authorized: () => true,
    );
    job.running = false;
    job.preparing = true;
    expect(registry.running, isTrue);
    job.preparing = false;
    expect(registry.running, isFalse);
    registry.dispose();
  });
  test(
    'restore rejects active writers before confirmation and preserves draft',
    () async {
      final port = BackupStub()..busy = true;
      final data = document();
      var confirms = 0;
      await expectLater(
        workflow(port).restore(data, () async {
          confirms++;
          return true;
        }),
        throwsA(isA<BackupBusy>()),
      );
      expect(port.restores, 0);
      expect(confirms, 0);
      expect(data['assets'].single['positionMs'], 123);
    },
  );
  test(
    'locked backup cannot export or restore after authentication cancellation',
    () async {
      final port = BackupStub()
        ..locked = true
        ..allowed = false;
      final app = workflow(port);
      expect(await app.export(), BackupExportResult.authenticationCancelled);
      var confirms = 0;
      expect(
        await app.restore(document(), () async {
          confirms++;
          return true;
        }),
        isFalse,
      );
      expect(port.exports, 0);
      expect(port.restores, 0);
      expect(confirms, 0);
    },
  );
  test(
    'successful export remains successful after timestamp failure',
    () async {
      final port = BackupStub()..failTimestamp = true;
      expect(await workflow(port).export(), BackupExportResult.saved);
      expect(port.exports, 1);
    },
  );
  test(
    'incoming locked preview requires authentication before exposure',
    () async {
      final port = BackupStub()
        ..allowed = false
        ..text = jsonEncode(document(locked: true));
      expect(await workflow(port).pick(), isNull);
      expect(port.auths, 1);
      expect(port.restores, 0);
    },
  );
  test('restore cancellation and route disposal do not commit', () async {
    final port = BackupStub();
    var active = true;
    final app = workflow(port, active: () => active);
    expect(await app.restore(document(), () async => false), isFalse);
    expect(
      await app.restore(document(), () async {
        active = false;
        return true;
      }),
      isFalse,
    );
    expect(port.restores, 0);
  });
  test('folder remap preserves progress, IDs and subtype', () async {
    final data = document();
    expect(
      await workflow(
        BackupStub(),
      ).relink(data, (data['collections'] as List).single, 0, reading: false),
      isTrue,
    );
    expect(data['assets'].single, {
      'collectionId': 'c',
      'id': 'v',
      'rootUri': 'new',
      'positionMs': 123,
    });
    expect(data['collections'].single['roots'].single['contentSubtype'], 'tv');
    expect(backupSummary(data), contains('1 videos'));
  });
  test(
    'source verification skips locked collections and retains failures',
    () async {
      final port = BackupStub()
        ..targets = [
          const BackupVerificationTarget(
            'locked',
            'Private',
            reading: false,
            allowed: false,
          ),
          const BackupVerificationTarget(
            'ok',
            'Good',
            reading: true,
            allowed: true,
          ),
          const BackupVerificationTarget(
            'failed',
            'Missing',
            reading: false,
            allowed: true,
          ),
        ];
      final result = await workflow(port).verify();
      expect(port.checks, ['ok', 'failed']);
      expect(result.verified, 1);
      expect(result.skipped, 1);
      expect(result.failed, ['Missing']);
    },
  );
  test('host metadata jobs reattach by identity and revoke without route ownership', () {
    final library = createLibraryController(SharedStore());
    final collection = VideoCollection(
      id: 'c',
      name: 'Movies',
      subtype: VideoSubtype.movies,
    );
    library.collections = [collection];
    final first = library.metadataJobs.video(collection);
    expect(library.metadataJobs.video(collection), same(first));
    var notifications = 0;
    library.addListener(() {
      notifications++;
    });
    first.changed();
    expect(notifications, 1);
    library.collections = [];
    library.notifyListeners();
    expect(first.cancelled, isTrue);
    expect(library.metadataJobs.registry.visible, isEmpty);
    library.dispose();
  });
  test(
    'job registry survives route reattachment and creates only one runner',
    () {
      final registry = ApplicationJobs();
      var created = 0;
      JobStub create() {
        created++;
        return JobStub();
      }

      final first = registry.obtain(
        'metadata:c',
        create,
        authorized: () => true,
      );
      final nextRoute = registry.obtain(
        'metadata:c',
        create,
        authorized: () => true,
      );
      expect(identical(first, nextRoute), isTrue);
      expect(created, 1);
      expect(first.cancellations, 0);
      registry.dispose();
      registry.dispose();
      expect(first.disposals, 1);
      expect(
        () => registry.obtain('new', create, authorized: () => true),
        throwsStateError,
      );
    },
  );
  test(
    'job revocation hides and cancels once while retaining its journal owner',
    () {
      final registry = ApplicationJobs();
      var allowed = true;
      final job = registry.obtain(
        'metadata:c',
        JobStub.new,
        authorized: () => allowed,
      );
      allowed = false;
      registry.refreshAccess();
      registry.refreshAccess();
      expect(registry.visible, isEmpty);
      expect(job.cancellations, 1);
      allowed = true;
      registry.refreshAccess();
      expect(registry.visible.single, same(job));
      registry.dispose();
    },
  );
  test('device commands cannot save protected settings after denied authentication', () async {
    final port = DeviceStub();
    final app = DeviceSettingsCommands(port);
    expect(await app.changeLock(true), isFalse);
    expect(await app.security({'lockDelay': 30}, locked: true), isFalse);
    await app.notifications(true);
    expect(port.writes, isEmpty);
    await app.homeView(spaces: true, value: 1, persist: false);
    await expectLater(
      app.homeView(spaces: false, value: 3, persist: true),
      throwsArgumentError,
    );
    expect(port.writes, isEmpty);
  });
  test(
    'reader preference preparation failure preserves the previous catalog',
    () async {
      final store = ReadingStoreStub();
      final commands = ReaderPreferenceCommands(store, authorized: (_) => true);
      final previous = store.catalog;
      await expectLater(
        commands.setTitle(previous.titles.first, {
          'fontSize': 20.0,
        }, prepare: (_) async => throw StateError('renderer')),
        throwsStateError,
      );
      expect(store.catalog, same(previous));
    },
  );
  test(
    'Activity drops scan and journal rows revoked during an awaited read',
    () async {
      final source = ActivityStub();
      var allowed = true;
      final collection = VideoCollection(
        id: 'c',
        name: 'Private',
        subtype: VideoSubtype.videos,
      );
      final queries = ActivityQueries(
        source,
        collections: () => [collection],
        authorized: (_) => allowed,
        scanning: (_) => true,
        found: (_) => 5,
        indexed: (_) => [],
      );
      final reading = queries.read();
      allowed = false;
      source.gate.complete({
        'remaining': ['v'],
      });
      expect(await reading, isEmpty);
    },
  );
}
