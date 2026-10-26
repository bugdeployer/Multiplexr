import 'fixtures/legacy_video_adapter.dart';
import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:app_shell/app_shell.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/storage.dart';
import 'package:multiplexr/src/library/library_models.dart';

import 'library_test.dart' show MemoryLibrary;
import 'widget_test.dart' show TestDevice;

class SharedStore extends MemoryLibrary {
  Map<String, dynamic>? videoWrite;
  @override
  Future<Map<String, dynamic>> load() async => {
    ...await super.load(),
    'queue': savedQueue,
  };
  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    if (value == null) {
      states.remove(key);
    } else {
      states[key] = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
    }
  }

  @override
  Future<void> writeVideoProgress(Map<String, dynamic> progress) async {
    videoWrite = progress;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test(
    'media identity includes kind and collection and survives punctuation',
    () {
      const a = MediaId(MediaKind.video, 'a:[]', 'same');
      expect(MediaId.fromJson(a.toJson()), a);
      expect(a, isNot(const MediaId(MediaKind.music, 'a:[]', 'same')));
      expect(a, isNot(const MediaId(MediaKind.video, 'b', 'same')));
    },
  );
  test('book, music and video progress round trip without sharing watched semantics', () {
    final progresses = <MediaProgress>[
      VideoProgress(
        const MediaId(MediaKind.video, 'v', '1'),
        positionMs: 3000,
        durationMs: 10000,
        watched: false,
      ),
      AudiobookProgress(
        const MediaId(MediaKind.audiobook, 'b', 'book'),
        chapterId: 'chapter-7',
        positionMs: 4000,
        finished: false,
        bookmarks: const [AudiobookBookmark('chapter-3', 2000, 'Quote')],
        sleep: SleepTimer(SleepTimerMode.endOfChapter),
      ),
      MusicProgress(
        const MediaId(MediaKind.music, 'm', 'track'),
        positionMs: 1200,
        playCount: 3,
      ),
    ];
    for (final p in progresses) {
      expect(
        MediaProgress.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(p.toJson()))),
        ).toJson(),
        p.toJson(),
      );
    }
    expect(progresses[1].toJson().containsKey('watched'), false);
    expect(progresses[2].toJson().containsKey('finished'), false);
    expect(
      () => VideoProgress(
        const MediaId(MediaKind.music, 'x', '1'),
        positionMs: 0,
        durationMs: 0,
        watched: false,
      ),
      throwsArgumentError,
    );
    final timer = SleepTimer(SleepTimerMode.deadline, deadlineUtcMs: 1000);
    expect(timer.expiredAt(DateTime.fromMillisecondsSinceEpoch(1000)), true);
    expect(timer.expiredAt(DateTime.fromMillisecondsSinceEpoch(999)), false);
    expect(() => SleepTimer(SleepTimerMode.deadline), throwsArgumentError);
  });
  test('future media storage keeps audio queues separate and bridges legacy video bytes', () async {
    final service = SharedStore();
    final store = MediaStorage(service);
    const book = MediaId(MediaKind.audiobook, 'c', 'same');
    const song = MediaId(MediaKind.music, 'c', 'same');
    const video = MediaId(MediaKind.video, 'c', 'same');
    await store.writeQueue(MediaKind.audiobook, [book]);
    await store.writeQueue(MediaKind.music, [song]);
    await store.writeQueue(MediaKind.video, [video]);
    expect(service.savedQueue, [
      jsonEncode(['c', 'same']),
    ]);
    expect(await store.readQueue(MediaKind.video), [video]);
    expect(await store.readQueue(MediaKind.audiobook), [book]);
    expect(await store.readQueue(MediaKind.music), [song]);
    expect(
      () => store.writeQueue(MediaKind.music, [book]),
      throwsArgumentError,
    );
    expect(
      () => store.writeQueue(MediaKind.music, [song, song]),
      throwsArgumentError,
    );
    final progress = AudiobookProgress(
      book,
      chapterId: 'chapter',
      positionMs: 50,
      finished: false,
    );
    await store.write(progress);
    expect((await store.read(book))!.toJson(), progress.toJson());
    expect(await store.read(song), isNull);
    final old = VideoAsset(
      id: 'same',
      collectionId: 'c',
      uri: 'content://x',
      filename: 'x.mp4',
      metadata: const {},
      positionMs: 850,
      watched: true,
    );
    service.assets.add(old.toJson());
    expect((await store.read(video))!.toJson(), old.progress.toJson());
    await store.write(old.progress);
    expect(service.videoWrite, old.progress.toJson());
    expect(service.states.containsKey('progress:${video.key}'), false);
  });
  test('video collection adapter retains privacy and inclusion settings', () {
    const local = VideoCollection(
      id: 'c',
      name: 'Clips',
      subtype: VideoSubtype.videos,
      locked: true,
      includeInGlobalVideos: true,
    );
    expect(local.mediaCollection.access.eligibleGlobally, false);
    expect(local.toJson()['type'], 'video');
    expect(TmdbVideoProvider(MemoryLibrary()).supportedKinds, {
      MediaKind.video,
    });
    expect(
      () => TmdbVideoProvider(MemoryLibrary()).search(MediaKind.music, 'test'),
      throwsUnsupportedError,
    );
  });
  test('playback routing rejects unsupported and mismatched kinds', () async {
    final router = PlaybackRegistry();
    var opened = 0;
    router.register(MediaKind.video, (_) async {
      opened++;
    });
    await router.open(
      const VideoRecord(
        MediaId(MediaKind.video, 'c', 'v'),
        'Clip',
        uri: 'content://v',
        available: true,
      ),
    );
    expect(opened, 1);
    expect(
      () => router.open(
        const MusicRecord(
          MediaId(MediaKind.music, 'c', 's'),
          'Song',
          albumId: 'album',
          artistId: 'artist',
          disc: 1,
          track: 2,
          uri: 'content://s',
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => router.open(
        const VideoRecord(
          MediaId(MediaKind.music, 'c', 's'),
          'Bad',
          uri: 'content://s',
          available: true,
        ),
      ),
      throwsArgumentError,
    );
  });
  test(
    'all 128 base/accent pairs retain readable text and primary controls',
    () {
      double ratio(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
      }

      final s = createSettingsController(TestDevice());
      for (final dark in [true, false]) {
        s.dark = dark;
        for (var base = 0; base < 8; base++) {
          for (var accent = 0; accent < 8; accent++) {
            if (dark) {
              s.darkBase = base;
              s.darkAccent = accent;
            } else {
              s.lightBase = base;
              s.lightAccent = accent;
            }
            final t = s.theme, c = t.colorScheme;
            final label = '$dark base $base accent $accent';
            expect(
              ratio(c.onSurface, t.scaffoldBackgroundColor),
              greaterThanOrEqualTo(4.5),
              reason: label,
            );
            expect(
              ratio(c.onSurfaceVariant, c.surface),
              greaterThanOrEqualTo(4.5),
              reason: label,
            );
            expect(
              ratio(c.primary, t.scaffoldBackgroundColor),
              greaterThanOrEqualTo(4.5),
              reason: label,
            );
            expect(
              ratio(c.primary, c.onPrimary),
              greaterThanOrEqualTo(4.5),
              reason: label,
            );
          }
        }
      }
    },
  );
}
