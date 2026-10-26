import 'package:multiplexr/src/metadata/metadata_failures.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/space_preferences.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_work_runner.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

import 'media_foundation_test.dart' show SharedStore;

class HeldSpaceStore extends SharedStore {
  final entered = Completer<void>(), release = Completer<void>();
  bool hold = false;
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> readState(String key) async {
    if (hold) {
      entered.complete();
      await release.future;
      hold = false;
    }
    return super.readState(key);
  }

  @override
  Future<void> writeState(String key, Map<String, dynamic>? value) async {
    writes++;
    await super.writeState(key, value);
  }
}

void main() {
  test(
    'malformed space fields recover independently without losing other spaces',
    () async {
      final store = SharedStore();
      store.states['spaces:display'] = {
        'cinema': {
          'startTab': 'bad',
          'pins': ['one', 9, null, 'one', '', 'two'],
          'counts': false,
        },
        'videos': {'startTab': 2, 'source': 'favorites'},
        'audiobooks': {'pins': false, 'hideWatched': true},
      };
      final settings = SpacePreferences();
      await settings.load(store.userPreferences);
      expect(settings.cinema.startTab, 0);
      expect(settings.cinema.pins, ['one', 'two']);
      expect(settings.cinema.counts, isFalse);
      expect(settings.videos.startTab, 2);
      expect(settings.videos.source, 'favorites');
      expect(settings.audiobooks.pins, isEmpty);
      expect(settings.audiobooks.hideWatched, isTrue);
    },
  );
  test(
    'queued space save snapshots pins and leaves later edits dirty',
    () async {
      final store = HeldSpaceStore();
      final settings = SpacePreferences();
      await settings.load(store.userPreferences);
      settings.cinema.pins = ['first'];
      store.hold = true;
      final save = settings.save(store.userPreferences);
      await store.entered.future;
      settings.cinema.pins.add('later');
      store.release.complete();
      await save;
      expect(store.states['spaces:display']!['cinema']['pins'], ['first']);
      await settings.save(store.userPreferences);
      expect(store.states['spaces:display']!['cinema']['pins'], [
        'first',
        'later',
      ]);
      final writes = store.writes;
      await settings.save(store.userPreferences);
      expect(store.writes, writes);
    },
  );
  test('metadata cancellation skips provider preparation and releases job ownership', () async {
    final runner = MetadataWorkRunner(classify: metadataFailure),
        owner = Object();
    for (final duringCheckpoint in [false, true]) {
      final token = MetadataCancellation();
      if (!duringCheckpoint) token.cancel();
      var prepared = false, processed = false;
      expect(
        await runner.run<int>(
          owner: owner,
          key: 'same',
          work: [1],
          cancellation: token,
          checkpoint: () async {
            token.cancel();
          },
          prepare: () async {
            prepared = true;
          },
          process: (_) async {
            processed = true;
          },
          completed: (_) async {},
        ),
        isFalse,
      );
      expect(prepared, isFalse);
      expect(processed, isFalse);
    }
    expect(
      await runner.run<int>(
        owner: owner,
        key: 'same',
        work: [],
        cancellation: MetadataCancellation(),
        checkpoint: () async {},
        process: (_) async {},
        completed: (_) async {},
      ),
      isTrue,
    );
  });
}
