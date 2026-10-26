import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/bootstrap/app_composition.dart';
import 'package:multiplexr/src/core/application/application_failure.dart';
import 'package:multiplexr/src/core/application/clock.dart';
import 'package:multiplexr/src/core/application/request_scope.dart';
import 'package:multiplexr/src/core/platform/application_failure_adapter.dart';
import 'package:multiplexr/src/domain/access/collection_session_access.dart';
import 'package:multiplexr/src/features/catalog/application/library_ports.dart';
import 'package:multiplexr/src/features/catalog/application/load_library.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_repository.dart'
    show LegacyLibraryRepository;
import 'package:app_shell/app_shell.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'widget_test.dart' show TestDevice;

LibrarySnapshot snapshot(String name) => LibrarySnapshot(
  collections: [
    VideoCollection(id: name, name: name, subtype: VideoSubtype.videos),
  ],
  assets: [],
  audioCounts: {},
  queue: [name],
  seriesIndexSupported: false,
);

class ReadPort implements LibraryRepository {
  final pending = <Completer<LibrarySnapshot>>[];
  @override
  Future<LibrarySnapshot> load() {
    final result = Completer<LibrarySnapshot>();
    pending.add(result);
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class FixedClock implements Clock {
  @override
  DateTime now() => DateTime(2026, 10, 23, 9);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppThemeDefinition.loadBundled);

  test(
    'pure request scope rejects cancelled, superseded and closed work',
    () async {
      final port = ReadPort(), scope = RequestScope();
      final first = LoadLibrary(port)(scope.begin());
      final superseded = expectLater(
        first,
        throwsA(
          isA<ApplicationFailure>().having(
            (e) => e.kind,
            'kind',
            ApplicationFailureKind.cancelled,
          ),
        ),
      );
      final next = scope.begin();
      port.pending.single.complete(snapshot('old'));
      await superseded;
      expect(next.isCurrent, true);
      next.cancel();
      await expectLater(
        LoadLibrary(port)(next),
        throwsA(isA<ApplicationFailure>()),
      );
      expect(
        port.pending,
        hasLength(1),
        reason: 'Cancelled work performs no I/O.',
      );
      scope.close();
      expect(scope.begin, throwsA(isA<ApplicationFailure>()));
    },
  );

  test('controller publishes only the newest injected load and suppresses stale errors', () async {
    final port = ReadPort();
    final controller = createLibraryController(SharedStore(), repository: port);
    final first = controller.load(), next = controller.load();
    port.pending[1].complete(snapshot('new'));
    await next;
    port.pending[0].completeError(StateError('old private error'));
    await first;
    expect(controller.collections.single.id, 'new');
    expect(controller.queue, ['new']);
    expect(controller.error, null);
    controller.dispose();
  });

  test('disposed controller cannot publish an in-flight result', () async {
    final port = ReadPort();
    final controller = createLibraryController(SharedStore(), repository: port);
    final pending = controller.load();
    controller.dispose();
    port.pending.single.complete(snapshot('closed'));
    await pending;
    expect(controller.collections, isEmpty);
    expect(controller.ready, false);
  });

  test('platform failure details are translated outside application code', () {
    expect(
      applicationFailure(MissingPluginException()).kind,
      ApplicationFailureKind.unavailable,
    );
    expect(
      applicationFailure(const FormatException('private payload')).kind,
      ApplicationFailureKind.invalidResponse,
    );
    final conflict = applicationFailure(
      PlatformException(code: 'conflict', message: 'credential=private'),
    );
    expect(conflict.kind, ApplicationFailureKind.conflict);
    expect(conflict.toString(), isNot(contains('private')));
  });

  test(
    'composition injects one port, clock and lazily shared session scope',
    () async {
      final store = SharedStore(), device = TestDevice(), port = ReadPort();
      final root = AppComposition(
        platform: device,
        libraryService: store,
        repository: port,
        clock: FixedClock(),
      );
      expect(root.library.repository, same(port));
      expect(
        root.library.service.persistenceOwner,
        same(store.persistenceOwner),
      );
      expect(root.library.clock.now(), DateTime(2026, 10, 23, 9));
      final load = root.library.load();
      port.pending.single.complete(snapshot('injected'));
      await load;
      expect(root.library.collections.single.name, 'injected');
      expect(root.sessions, same(root.sessions));
      expect(root.sessions.reading.service, same(store));
      expect(root.sessions.music.library, same(root.library));
      expect(
        root.sessions.music.jobFor('injected'),
        same(root.sessions.music.jobFor('injected')),
      );
      root.sessions.dispose();
      root.dispose();
      root.dispose();
      expect(() => root.sessions, throwsStateError);
    },
  );

  test('legacy port still decodes the same injected service and session grants revoke', () async {
    final store = SharedStore();
    store.collections.add(
      const VideoCollection(
        id: 'legacy',
        name: 'Legacy',
        subtype: VideoSubtype.videos,
      ).toJson(),
    );
    final result = await LoadLibrary(LegacyLibraryRepository(store))(
      RequestScope().begin(),
    );
    expect(result.collections.single.id, 'legacy');
    final access = CollectionSessionAccess();
    access.begin('legacy');
    expect(access.canAccess('legacy', locked: true), false);
    access.authorize('legacy');
    expect(access.canAccess('legacy', locked: true), true);
    access.begin('other');
    expect(access.canAccess('legacy', locked: true), false);
    access.end();
    expect(access.activeCollectionId, null);
  });
}
