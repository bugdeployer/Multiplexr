import 'package:multiplexr/src/bootstrap/audio_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/storage.dart';

import 'grouped_media_test.dart' show audiobook;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/core/platform/library_events.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/library/library_repository.dart';

import 'media_foundation_test.dart' show SharedStore;

class EventStore extends SharedStore {
  EventStore(this.hub);
  final LibraryEventHub hub;
  @override
  Stream<ScanProgressEvent> get scanEvents => hub.scanProgress;
}

class DelayedStore extends SharedStore {
  final gate = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> load() => gate.future;
}

class DelayedAudioTransport implements PlatformTransport {
  final oldState = Completer<String>();
  int reads = 0;
  @override
  Future<T?> invokeMethod<T>(String method, [Object? args]) async {
    Object? value;
    if (method == 'state') {
      value = ++reads == 1 ? await oldState.future : '{"index":1}';
    }
    return value as T?;
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? args,
  ]) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'state updates serialize read modify write and recover after failure',
    () async {
      final store = SharedStore();
      final a = JsonStateRepository(store), b = JsonStateRepository(store);
      await Future.wait([
        a.update('shared', (v) async {
          await Future<void>.delayed(Duration.zero);
          return {...?v, 'a': 1};
        }),
        b.update('shared', (v) async => {...?v, 'b': 2}),
      ]);
      expect(await store.readState('shared'), {'a': 1, 'b': 2});
      expect(a.mutations.revision('shared'), 2);
      await expectLater(
        a.update('shared', (_) async => throw StateError('failed')),
        throwsStateError,
      );
      expect(a.mutations.revision('shared'), 2);
      await b.update('shared', (v) async => {...?v, 'c': 3});
      expect(await store.readState('shared'), {'a': 1, 'b': 2, 'c': 3});
    },
  );
  test('independent keys do not block each other and independent stores do not mix', () async {
    final first = SharedStore(), second = SharedStore();
    final gate = Completer<void>();
    final a = JsonStateRepository(first), b = JsonStateRepository(second);
    final pending = a.update('slow', (_) async {
      await gate.future;
      return {'slow': true};
    });
    await a.update('fast', (_) async => {'fast': true});
    await b.update('slow', (_) async => {'second': true});
    expect(await second.readState('slow'), {'second': true});
    gate.complete();
    await pending;
    expect(await first.readState('slow'), {'slow': true});
  });
  testWidgets(
    'event hub supports multiple controllers, rejects malformed/inactive events, detaches disposal',
    (tester) async {
      const channel = MethodChannel('multiplexr/batch2-events');
      final store = EventStore(LibraryEventHub(channel));
      final a = createLibraryController(store),
          b = createLibraryController(store);
      a.scanning.add('c');
      b.scanning.add('c');
      Future<void> send(Object? arguments) async {
        final done = Completer<void>();
        tester.binding.channelBuffers.push(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('scanProgress', arguments),
          ),
          (_) => done.complete(),
        );
        await done.future;
        await tester.pump();
      }

      await send({'id': 'c', 'found': 3, 'folder': 'Root'});
      expect(a.scanProgress['c']?['found'], 3);
      expect(b.scanProgress['c']?['found'], 3);
      await send({'id': 'c', 'found': -1, 'folder': 'Invalid'});
      await send({'id': 'not-scanning', 'found': 10, 'folder': ''});
      expect(a.scanProgress.length, 1);
      a.dispose();
      await send({'id': 'c', 'found': 4, 'folder': 'Next'});
      expect(a.scanProgress['c']?['found'], 3);
      expect(b.scanProgress['c']?['found'], 4);
      b.dispose();
    },
  );
  testWidgets(
    'transport preserves wire payloads and typed error compatibility',
    (tester) async {
      const channel = MethodChannel('multiplexr/batch2-transport');
      final service = LibraryService(transport: ChannelTransport(channel));
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'metadataSearch') {
          throw PlatformException(code: 'rateLimit', message: 'Slow down');
        }
        if (call.method == 'readState') return '[]';
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await service.writeState('key', {'one': 1});
      expect(calls.last.arguments, {
        'key': 'key',
        'value': jsonEncode({'one': 1}),
      });
      await expectLater(
        service.searchPage('movie', 'Dune', 2),
        throwsA(
          isA<PlatformFailure>()
              .having((e) => e.kind, 'kind', PlatformFailureKind.rateLimit)
              .having((e) => e.code, 'legacy code', 'rateLimit'),
        ),
      );
      expect(calls.last.arguments, {
        'type': 'movie',
        'query': 'Dune',
        'page': 2,
      });
      await expectLater(service.readState('key'), throwsFormatException);
    },
  );
  test(
    'repository snapshots isolate their collection and queue lists',
    () async {
      final store = SharedStore();
      final snapshot = await LegacyLibraryRepository(store).load();
      expect(() => snapshot.collections.clear(), throwsUnsupportedError);
      final queue = <String>['one'];
      final isolated = LibrarySnapshot(
        collections: [],
        assets: [],
        audioCounts: {},
        queue: queue,
        seriesIndexSupported: false,
      );
      queue.clear();
      expect(isolated.queue, ['one']);
    },
  );
  test('disposed controller rejects an outstanding snapshot', () async {
    final store = DelayedStore();
    final controller = createLibraryController(store);
    final loading = controller.load();
    controller.dispose();
    store.gate.complete({'collections': [], 'assets': []});
    await loading;
    expect(controller.ready, false);
    expect(controller.collections, isEmpty);
  });
  test('audio transport drops state from a superseded session', () async {
    final transport = DelayedAudioTransport();
    final controller = createAudioController(transport: transport);
    addTearDown(controller.dispose);
    final oldRead = controller.refresh();
    final opening = controller.openBook(
      audiobook('New'),
      MediaStorage(SharedStore()),
    );
    await Future<void>.delayed(Duration.zero);
    // Opening a new session must not wait for an unrelated old status request.
    await opening.timeout(const Duration(seconds: 1));
    expect(controller.state.data['index'], 1);
    transport.oldState.complete('{"index":42}');
    await oldRead;
    expect(controller.state.data['index'], isNot(42));
    await controller.refresh();
    expect(controller.state.data['index'], 1);
  });
  test(
    'failed mutable update cannot alter the stored nested snapshot',
    () async {
      final store = SharedStore();
      await store.writeState('nested', {
        'data': {'value': 1},
      });
      final repository = JsonStateRepository(store);
      await expectLater(
        repository.update('nested', (draft) async {
          (draft!['data'] as Map)['value'] = 9;
          throw StateError('abort');
        }),
        throwsStateError,
      );
      expect((await store.readState('nested'))!['data'], {'value': 1});
      Map<String, dynamic>? retained;
      await repository.update('nested', (draft) async {
        retained = draft;
        return draft;
      });
      (retained!['data'] as Map)['value'] = 8;
      expect((await store.readState('nested'))!['data'], {'value': 1});
    },
  );
  test('event hubs reuse ownership for the same messenger and channel', () {
    final first = LibraryEventHub(
      const MethodChannel('multiplexr/shared-owner'),
    );
    final second = LibraryEventHub(
      const MethodChannel('multiplexr/shared-owner'),
    );
    expect(second, same(first));
    expect(
      LibraryEventHub(const MethodChannel('multiplexr/other-owner')),
      isNot(same(first)),
    );
  });
  test(
    'disposed controllers do not initiate loads or audio requests',
    () async {
      final store = DelayedStore();
      final library = createLibraryController(store)..dispose();
      await library.load().timeout(const Duration(seconds: 1));
      expect(library.ready, false);
      final transport = DelayedAudioTransport();
      final audio = createAudioController(transport: transport)..dispose();
      await audio.refresh();
      await audio.openBook(
        audiobook('Not opened'),
        MediaStorage(SharedStore()),
      );
      await audio.execute(const AudioCommand.action(AudioAction.playPause));
      expect(transport.reads, 0);
    },
  );
}
