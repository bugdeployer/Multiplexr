import 'package:multiplexr/src/bootstrap/audio_assembly.dart';
import 'package:multiplexr/src/bootstrap/reading_assembly.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:multiplexr/src/core/application/maintenance.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';
import 'fixtures/legacy_library_service.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/legacy_video_playback_host.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/reading/native_reading_text_source.dart';
import 'package:multiplexr/src/bootstrap/reader_assembly.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';

import 'reading_r1_test.dart' show base;
import 'reading_r5_test.dart' show ReadingWorkflowHarness;

import 'package:multiplexr/src/reading/reading_app_controller.dart';

class ResourceTransport implements PlatformTransport {
  final closes = <String>[];
  bool fail = true;
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (method == 'openReadingText') return 'reader-token' as T;
    if (method == 'closeReadingText' || method == 'stop') {
      closes.add('$method:$arguments');
      if (fail) {
        fail = false;
        throw StateError('native cleanup failed');
      }
    }
    return null;
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'old reading route stays closed after identical public IDs reload',
    (tester) async {
      final harness = ReadingWorkflowHarness();
      final app = createReadingAppController(
        harness.service,
        authenticate: () async => true,
        appBlocked: () => false,
      );
      await app.load();
      await tester.pumpWidget(
        MaterialApp(
          home: ReadingAccessGuard(
            controller: app,
            collectionId: 'books:[]',
            child: const Scaffold(body: Text('publication-content')),
          ),
        ),
      );
      expect(find.text('publication-content'), findsOneWidget);
      await harness.service.maintenance.exclusively(() async {});
      await app.load();
      expect(app.canAccess('books:[]'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('publication-content'), findsNothing);
      expect(find.text('Collection unavailable · Back'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  test('failed native reader close blocks restore and is retried before replacement', () async {
    final transport = ResourceTransport();
    final service = LibraryService(transport: transport);
    final source = NativeReadingTextSource(service);
    await source.open(ReadingCodec.decode(base()).titles.first);
    var restored = false;
    await expectLater(
      service.maintenance.exclusively(() async {
        restored = true;
      }),
      throwsStateError,
    );
    expect(restored, isFalse);
    await service.maintenance.exclusively(() async {
      restored = true;
    });
    expect(restored, isTrue);
    expect(transport.closes, [
      'closeReadingText:reader-token',
      'closeReadingText:reader-token',
    ]);
    await service.maintenance.exclusively(() async {});
    expect(transport.closes.length, 2);
  });
  test(
    'failed audio stop is retried even after its Dart projection was cleared',
    () async {
      final gate = Maintenance(), transport = ResourceTransport();
      final audio = createAudioController(
        transport: transport,
        maintenance: gate,
      );
      audio.state = const AudioState({'playing': false});
      await expectLater(gate.exclusively(() async {}), throwsStateError);
      expect(audio.state.data, isEmpty);
      await gate.exclusively(() async {});
      expect(transport.closes, ['stop:null', 'stop:null']);
      await gate.exclusively(() async {});
      expect(transport.closes.length, 2);
      audio.dispose();
    },
  );
  test('restoring identical IDs still revokes old video checkpoints and reader controllers', () async {
    final service = LibraryService(
      transport: ResourceTransport()..fail = false,
    );
    final session = LegacyVideoPlaybackHost(service).session(
      const VideoAsset(
        id: 'title',
        collectionId: 'collection',
        uri: 'content://title',
        filename: 'title.mp4',
        metadata: {},
      ),
      authorized: () => true,
    );
    var drains = 0;
    session.bindDrain(() async {
      drains++;
    });
    final reader = ReaderSessionFactory(
      service,
      authorized: (_) => true,
    ).text();
    expect(reader.controller.authorized('collection'), isTrue);
    await service.maintenance.exclusively(() async {});
    expect(drains, 1);
    expect(reader.controller.authorized('collection'), isFalse);
    await expectLater(
      session.save(positionMs: 1, durationMs: 100, completed: false),
      throwsStateError,
    );
    session.dispose();
    reader.controller.dispose();
  });
}
