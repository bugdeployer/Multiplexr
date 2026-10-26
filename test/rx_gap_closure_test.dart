import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/application/job_notifications.dart';
import 'package:multiplexr/src/core/application/maintenance.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/features/playback/application/audio_commands.dart';
import 'package:multiplexr/src/features/playback/application/video_session.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/contracts.dart';

class ProgressMemory implements VideoSessionStore {
  @override
  Future<void> save(VideoProgress progress) async {}
}

void main() {
  const id = MediaId(MediaKind.video, 'c', 'current');
  const next = VideoAsset(
    id: 'next',
    collectionId: 'c',
    uri: 'content://next',
    filename: 'next.mp4',
    metadata: {},
  );
  test('completion keeps pending while hidden, then advances the queued title once', () async {
    final session = VideoSession(id, ProgressMemory(), authorized: () => true)
      ..completionPending = true;
    var foreground = false;
    Future<VideoAsset?> finish() => session.finish(
      checkpoint: () async {},
      reload: () async {},
      active: () => true,
      foreground: () => foreground,
      pictureInPicture: () => false,
      autoplayNext: () => false,
      queued: () => next,
      episodeVersions: () => [],
    );
    expect(await finish(), isNull);
    expect(session.completionPending, isTrue);
    foreground = true;
    expect(await finish(), same(next));
    expect(await finish(), isNull);
  });
  test(
    'revocation during checkpoint prevents completion navigation and handoff',
    () async {
      var authorized = true;
      final session = VideoSession(
        id,
        ProgressMemory(),
        authorized: () => authorized,
      )..completionPending = true;
      final gate = Completer<void>();
      final finishing = session.finish(
        checkpoint: () => gate.future,
        reload: () async {},
        active: () => true,
        foreground: () => true,
        pictureInPicture: () => false,
        autoplayNext: () => true,
        queued: () => next,
        episodeVersions: () => [next],
      );
      authorized = false;
      gate.complete();
      expect(await finishing, isNull);
      expect(session.completionPending, isTrue);
      authorized = true;
      var launched = false;
      await expectLater(
        session.handoff(
          pause: () async {},
          checkpoint: () async {},
          disableBackground: () async {
            authorized = false;
          },
          launch: () async {
            launched = true;
          },
        ),
        throwsStateError,
      );
      expect(launched, isFalse);
    },
  );
  test('invalid typed commands cannot pass application validation', () {
    for (final command in <AudioCommand>[
      const AudioCommand.seek(-1),
      const AudioCommand.chapter(-1),
      const AudioCommand.rate(double.nan),
      const AudioCommand.sleep(-2),
      const AudioCommand.external(''),
      const AudioCommand.bookmark(' '),
    ]) {
      expect(command.validate, throwsArgumentError);
    }
    expect(const AudioCommand.seek(0).validate, returnsNormally);
  });
  test(
    'a cancelling subscriber cannot recursively overflow job notifications',
    () {
      final job = JobNotifications();
      var notifications = 0;
      job.addListener(() {
        notifications++;
        job.notifyListeners();
      });
      job.notifyListeners();
      expect(notifications, 1);
      job.dispose();
      job.notifyListeners();
      expect(notifications, 1);
    },
  );
  test(
    'all queued adapters hold admission while waiting on another mutation',
    () async {
      final owner = Object(), first = Completer<void>();
      final coordinator = MutationCoordinator.forOwner(owner);
      final a = coordinator.run('same', () => first.future);
      var secondStarted = false;
      final b = coordinator.run('same', () async {
        secondStarted = true;
      });
      await expectLater(
        Maintenance.forOwner(owner).exclusively(() async {}),
        throwsA(isA<MaintenanceBusy>()),
      );
      expect(secondStarted, isFalse);
      first.complete();
      await Future.wait([a, b]);
      expect(secondStarted, isTrue);
      await Maintenance.forOwner(owner).exclusively(() async {});
    },
  );
}
