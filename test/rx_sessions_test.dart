import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/playback/application/video_session.dart';
import 'package:multiplexr/src/features/playback/application/audio_session_controller.dart';
import 'package:multiplexr/src/features/playback/application/audio_playback_models.dart';
import 'package:multiplexr/src/features/reading/application/reader_handoff.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';

import 'reading_r1_test.dart' show base;

class VideoStore implements VideoSessionStore {
  final writes = <VideoProgress>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> save(VideoProgress p) async {
    await gate?.future;
    if (fail) {
      fail = false;
      throw StateError('disk');
    }
    writes.add(p);
  }
}

class Engine implements AudioEnginePort {
  final reads = <Completer<AudioSnapshot?>>[];
  int opens = 0, commands = 0;
  @override
  Future<AudioSnapshot?> read() {
    final gate = Completer<AudioSnapshot?>();
    reads.add(gate);
    return gate.future;
  }

  @override
  Future<void> open(
    AudioPlaybackRequest request, {
    required bool autoplay,
  }) async {
    opens++;
  }

  @override
  Future<void> execute(AudioCommand command) async {
    commands++;
  }
}

class AudioApplication with AudioSessionApplication {
  AudioApplication(this.engine);
  @override
  final Engine engine;
  int changes = 0;
  @override
  void notifyListeners() {
    changes++;
  }
}

class Handoff implements ExternalReaderPort {
  int opens = 0, records = 0;
  Completer<void>? gate;
  bool failRecord = false;
  @override
  Future<void> open(ReadingTitle title, String package) async {
    opens++;
    await gate?.future;
  }

  @override
  Future<void> recordOpened(ReadingTitle title) async {
    records++;
    if (failRecord) throw StateError('disk');
  }
}

void main() {
  const id = MediaId(MediaKind.video, 'c', 'v');
  test(
    'completion reports once per transition and checkpoints remain bounded',
    () {
      final session = VideoSession(id, VideoStore(), authorized: () => true);
      expect(
        session
            .observe(positionMs: 100, durationMs: 10000, completed: false)
            .checkpoint,
        isFalse,
      );
      expect(
        session
            .observe(positionMs: 5000, durationMs: 10000, completed: false)
            .checkpoint,
        isTrue,
      );
      expect(
        session
            .observe(positionMs: 5100, durationMs: 10000, completed: false)
            .checkpoint,
        isFalse,
      );
      expect(
        session
            .observe(positionMs: 10000, durationMs: 10000, completed: true)
            .completion,
        isTrue,
      );
      expect(
        session
            .observe(positionMs: 10000, durationMs: 10000, completed: true)
            .completion,
        isFalse,
      );
      expect(session.completionPending, isTrue);
      session.observe(positionMs: 0, durationMs: 10000, completed: false);
      expect(session.completionPending, isFalse);
    },
  );
  test(
    'video completion waits for older checkpoint and preserves final position',
    () async {
      final store = VideoStore()..gate = Completer<void>();
      final session = VideoSession(id, store, authorized: () => true);
      final first = session.save(
        positionMs: 5000,
        durationMs: 10000,
        completed: false,
      );
      final last = session.save(
        positionMs: 9990,
        durationMs: 10000,
        completed: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.writes, isEmpty);
      store.gate!.complete();
      await Future.wait([first, last]);
      expect(store.writes.map((p) => p.positionMs), [5000, 10000]);
      expect(store.writes.last.watched, isTrue);
    },
  );
  test(
    'failed video write can retry and queued write rechecks revocation',
    () async {
      final store = VideoStore()..fail = true;
      var allowed = true;
      final session = VideoSession(id, store, authorized: () => allowed);
      Future<void> save() =>
          session.save(positionMs: 1, durationMs: 10, completed: false);
      await expectLater(save(), throwsStateError);
      await save();
      expect(store.writes, hasLength(1));
      allowed = false;
      await expectLater(save(), throwsStateError);
      expect(store.writes, hasLength(1));
    },
  );
  test('session policy never advances while hidden or revoked', () {
    const policy = SessionPolicy();
    for (final foreground in [false, true]) {
      expect(
        policy.mayAdvance(
          authorized: false,
          foreground: foreground,
          pictureInPicture: false,
        ),
        isFalse,
      );
    }
    expect(
      policy.mayAdvance(
        authorized: true,
        foreground: false,
        pictureInPicture: false,
      ),
      isFalse,
    );
    expect(
      policy.shouldPause(
        authorized: false,
        foreground: true,
        backgroundAllowed: true,
        pictureInPicture: true,
      ),
      isTrue,
    );
    expect(
      policy.shouldPause(
        authorized: true,
        foreground: false,
        backgroundAllowed: false,
        pictureInPicture: false,
      ),
      isTrue,
    );
  });
  test(
    'audio attach reads state without opening or commanding playback',
    () async {
      final engine = Engine();
      final observing = AudioApplication(engine);
      final read = observing.refresh();
      engine.reads.single.complete(
        const AudioSnapshot(AudioState({'playing': true}), 'one'),
      );
      await read;
      expect(observing.state.playing, isTrue);
      expect(engine.opens, 0);
      expect(engine.commands, 0);
      observing.disposeSession();
    },
  );
  test('disposed audio session ignores delayed native snapshot', () async {
    final engine = Engine();
    final session = AudioApplication(engine);
    final read = session.refresh();
    session.disposeSession();
    engine.reads.single.complete(
      const AudioSnapshot(AudioState({'playing': true}), 'late'),
    );
    await read;
    expect(session.changes, 0);
    expect(session.state.playing, isFalse);
  });
  test(
    'external activity write failure does not launch reader twice',
    () async {
      final port = Handoff()..failRecord = true;
      final title = ReadingCodec.decode(base()).titles.first;
      await ReaderHandoff(port, authorized: (_) => true).open(title, 'reader');
      expect(port.opens, 1);
      expect(port.records, 1);
    },
  );
  test(
    'external handoff rejects revoked access and late activity writes',
    () async {
      final port = Handoff()..gate = Completer<void>();
      final title = ReadingCodec.decode(base()).titles.first;
      var allowed = true;
      final handoff = ReaderHandoff(port, authorized: (_) => allowed);
      final opening = handoff.open(title, 'reader');
      allowed = false;
      port.gate!.complete();
      await opening;
      expect(port.records, 0);
      await expectLater(handoff.open(title, 'reader'), throwsStateError);
      expect(port.opens, 1);
    },
  );
}
