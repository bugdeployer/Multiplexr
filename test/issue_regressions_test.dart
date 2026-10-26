import 'fixtures/legacy_metadata_assembly.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/features/metadata/application/video_metadata_policy.dart';

import 'metadata_recovery_test.dart' show JournalLibrary;
import 'phase_one_test.dart' show batchSetup;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('#2 partial tag metadata preserves filename inference for Movies and Videos', () {
    for (final type in [VideoSubtype.movies, VideoSubtype.videos]) {
      for (final tags in ['Favorite', '', 'Travel, Favorite']) {
        final data = {
          'id': 'a',
          'collectionId': 'c',
          'uri': 'content://a',
          'filename': 'Arrival.2016.mp4',
        };
        final before = VideoAsset.fromJson(data, type);
        final after = VideoAsset.fromJson({
          ...data,
          'metadata': {'tags': tags},
        }, type);
        expect(after.title, before.title);
        expect(after.metadata['year'], before.metadata['year']);
        expect(after.metadata['tags'], tags);
      }
      final curated = VideoAsset.fromJson({
        'id': 'a',
        'collectionId': 'c',
        'uri': 'content://a',
        'filename': 'Arrival.2016.mp4',
        'metadataSource': 'manual',
        'metadata': {'title': 'Custom', 'year': '', 'tags': 'Favorite'},
      }, type);
      expect(curated.title, 'Custom');
      expect(curated.metadata['year'], '');
    }
  });
  VideoAsset title(String value, {String year = '2020'}) =>
      VideoAsset.fromJson({
        'id': 'a',
        'collectionId': 'c',
        'uri': 'content://a',
        'filename': 'clip.mp4',
        'metadata': {'title': value, 'year': year},
      }, VideoSubtype.movies);
  Map<String, dynamic> candidate(String value, {String date = '2020-01-01'}) =>
      {'id': 1, 'title': value, 'release_date': date};
  test(
    '#3 unrelated non-Latin titles never collapse into a confident match',
    () {
      for (final pair in [
        ('英雄2', '別作2'),
        ('映画2', '別物2'),
        ('영웅2', '다른2'),
        ('Été', 'Ete'),
      ]) {
        expect(normalizedTitle(pair.$1), isNot(normalizedTitle(pair.$2)));
        expect(
          confidentMatch(title(pair.$1), VideoSubtype.movies, [
            candidate(pair.$2),
          ]),
          isNull,
        );
      }
      for (final name in ['英雄', '映画', '영웅', 'Café', 'Hero 英雄 2', '1917']) {
        expect(
          confidentMatch(title(name), VideoSubtype.movies, [candidate(name)]),
          isNotNull,
        );
      }
      expect(
        confidentMatch(title('2'), VideoSubtype.movies, [candidate('2')]),
        isNull,
      );
    },
  );
  test('#3 normalization handles canonical accents, width and punctuation without weakening year checks', () {
    expect(normalizedTitle('CAFE\u0301'), normalizedTitle('café'));
    expect(normalizedTitle('ＡＢＣ：英雄！'), normalizedTitle('ABC 英雄'));
    expect(
      confidentMatch(title('Dune', year: '1984'), VideoSubtype.movies, [
        candidate('Dune', date: '2021-01-01'),
      ]),
      isNull,
    );
    expect(
      confidentMatch(title('Dune', year: '20'), VideoSubtype.movies, [
        candidate('Dune'),
      ]),
      isNull,
    );
    expect(
      confidentMatch(title('英雄'), VideoSubtype.movies, [
        {...candidate('Hero'), 'original_title': '英雄'},
      ]),
      isNotNull,
    );
    expect(
      confidentMatch(title('Dune'), VideoSubtype.movies, [
        candidate('Dune'),
        {...candidate('Dune'), 'id': 2},
      ]),
      isNull,
    );
  });
  test('#5 resumed successes remove resolved errors and persist the corrected journal', () async {
    final service = JournalLibrary()..failCode = 'rateLimit';
    final library = await batchSetup(service, 2);
    final job = createMetadataJob(library, library.collections.single);
    await expectLater(job.run(), throwsException);
    expect(job.failures, isNotEmpty);
    service.failCode = null;
    await job.run(resume: true);
    expect(job.matched, 2);
    expect(job.remaining, isEmpty);
    expect(job.failures, isEmpty);
    expect(job.failed, 0);
    expect(job.lastError, isNull);
    final recovered = createMetadataJob(library, library.collections.single);
    await recovered.recover();
    expect(recovered.failures, isEmpty);
    expect(recovered.lastError, isNull);
  });
  test(
    '#5 recovery repairs legacy errors without clearing unresolved failures',
    () async {
      final service = JournalLibrary();
      final library = await batchSetup(service, 2);
      final job = createMetadataJob(library, library.collections.single);
      await job.run();
      final unresolved = VideoAsset.fromJson({
        ...service.assets.last,
        'metadataSource': 'filename',
        'metadataStatus': 'failed',
      }, VideoSubtype.movies);
      await service.saveAsset(unresolved);
      await library.load();
      await service.writeState(job.key, {
        'version': 2,
        'implementationEpoch': historicalVideo(library).implementationEpoch,
        'remaining': <String>[],
        'failures': {'0': 'Old error', '1': 'Network unavailable'},
        'failed': 2,
        'lastError': 'Old error',
      });
      final recovered = createMetadataJob(library, library.collections.single);
      await recovered.recover();
      expect(recovered.failures, {'1': 'Network unavailable'});
      expect(recovered.failed, 1);
      expect(recovered.lastError, 'Network unavailable');
      final again = createMetadataJob(library, library.collections.single);
      await again.recover();
      expect(again.failures, recovered.failures);
      expect(service.queries.length, 2);
    },
  );
}
