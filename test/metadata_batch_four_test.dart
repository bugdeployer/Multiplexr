import 'package:multiplexr/src/metadata/metadata_failures.dart';
import 'package:multiplexr/src/core/application/mutations.dart';

import 'fixtures/legacy_provider_adapters.dart';

import 'package:multiplexr/src/core/application/job_admission.dart';

import 'fixtures/legacy_metadata_assembly.dart';

import 'fixtures/legacy_library_assembly.dart';
import 'package:multiplexr/src/library/library_models.dart';

import 'library_test.dart' show MemoryLibrary;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_work_runner.dart';
import 'package:multiplexr/src/metadata/metadata_targets.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_matching.dart';
import 'package:multiplexr/src/features/metadata/application/artwork_service.dart';
import 'package:multiplexr/src/library/series.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'grouped_media_test.dart' show audiobook;
import 'phase_one_test.dart' show video;

MetadataCandidate candidate({String title = 'Online', String cover = ''}) =>
    MetadataCandidate(
      provider: 'audible',
      id: 'B012345678',
      entity: MetadataEntityType.audiobook,
      values: {'title': title, 'author': 'Writer', 'coverUrl': cover},
      attribution: 'Audible',
    );
Matcher failure(MetadataFailureKind kind) =>
    isA<MetadataFailure>().having((e) => e.kind, 'kind', kind);

class StubProvider implements MetadataProvider {
  final gate = Completer<MetadataSearchPage>();
  @override
  String get id => 'fake';
  @override
  Set<MetadataEntityType> get entities => {MetadataEntityType.audiobook};
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) =>
      gate.future;
}

class SeriesFixtureStore extends MemoryLibrary {
  final detailCalls = <int>[];
  @override
  Future<Map<String, dynamic>> details(
    String type,
    int id, {
    int? season,
    int? episode,
  }) async {
    detailCalls.add(episode!);
    return {
      'id': 100 + episode,
      'name': 'Episode $episode',
      'overview': 'Description $episode',
      'episode_number': episode,
      'series': {'name': 'Provider Series'},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audio = MethodChannel('multiplexr/audio');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audio, null),
  );
  test(
    'provider pages preserve edition, locale, continuation and attribution',
    () async {
      Map? request;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audio, (call) async {
            request = call.arguments as Map;
            return jsonEncode([
              {
                'providerId': 'B012345678',
                'title': 'Volume 1',
                'edition': 'Unabridged',
                'narrator': 'Reader',
                'language': 'English',
              },
            ]);
          });
      final page =
          await MetadataWorkflow([
            const AudiobookMetadataProvider('audible'),
          ], mutations: const OwnerApplicationMutations()).search(
            const MetadataSearchRequest(
              provider: 'audible',
              entity: MetadataEntityType.audiobook,
              title: 'Volume',
              creator: 'Author',
              locale: 'uk',
              page: 2,
            ),
            MetadataCancellation(),
          );
      expect(request!['page'], 2);
      expect(request!['region'], 'uk');
      expect(request!['author'], 'Author');
      expect(page.nextPage, 3);
      expect(page.total, isNull);
      expect(page.attribution, contains('UK'));
      final values = page.candidates.single.values;
      values['edition'] = 'changed';
      expect(page.candidates.single.values['edition'], 'Unabridged');
      expect(page.candidates.single.values['narrator'], 'Reader');
    },
  );
  test('cancelled search cannot publish an in-flight result', () async {
    final provider = StubProvider();
    final coordinator = MetadataWorkflow([
      provider,
    ], mutations: const OwnerApplicationMutations());
    final cancellation = MetadataCancellation();
    const request = MetadataSearchRequest(
      provider: 'fake',
      entity: MetadataEntityType.audiobook,
      title: 'Title',
    );
    final pending = coordinator.search(request, cancellation);
    cancellation.cancel();
    provider.gate.complete(
      MetadataSearchPage(
        candidates: [],
        request: request,
        attribution: 'Fixture',
      ),
    );
    await expectLater(pending, throwsA(failure(MetadataFailureKind.cancelled)));
    await expectLater(
      coordinator.search(
        const MetadataSearchRequest(
          provider: 'fake',
          entity: MetadataEntityType.movie,
          title: 'Title',
        ),
        MetadataCancellation(),
      ),
      throwsA(failure(MetadataFailureKind.unavailable)),
    );
  });
  test(
    'single and bulk scorer rejects ambiguous works and distinguishes book one',
    () {
      final rows = [
        {'title': 'The Primal Hunter', 'author': 'Zogarth', 'id': 1},
        {'title': 'The Primal Hunter 2', 'author': 'Zogarth', 'id': 2},
      ];
      expect(
        MetadataScorer.uniqueExact(
          title: 'The Primal Hunter',
          creator: 'Zogarth',
          candidates: rows,
          titleFields: ['title'],
        )!['id'],
        1,
      );
      expect(
        MetadataScorer.uniqueExact(
          title: 'The Primal Hunter',
          candidates: [rows.first, rows.first],
          titleFields: ['title'],
        ),
        isNull,
      );
    },
  );
  test('selected apply is idempotent and preserves sources, series, chapters and tags', () async {
    final library = createAudioLibrary(SharedStore());
    final book = audiobook('Local', series: 'Manual series').withMetadata({
      'tags': ['Keep'],
    });
    await library.save([book]);
    final target = AudiobookMetadataTarget(library, book.id);
    final coordinator = MetadataWorkflow(
      [],
      mutations: const OwnerApplicationMutations(),
    );
    final token = MetadataCancellation();
    final review = await coordinator.review(target, candidate(), token);
    await coordinator.apply(target, review, {'title'}, token);
    final once = (await library.books()).single.toJson();
    await coordinator.apply(target, review, {'title'}, token);
    expect((await library.books()).single.toJson(), once);
    final updated = (await library.books()).single;
    expect(updated.metadata.author, '');
    expect(updated.metadata.series, 'Manual series');
    expect(updated.metadata.tags, ['Keep']);
    expect(updated.files.first.uri, book.files.first.uri);
    expect(updated.chapterMarkers.first.id, book.chapterMarkers.first.id);
  });
  test(
    'manual fields and artwork remain opt-in and retain provenance',
    () async {
      final library = createAudioLibrary(SharedStore());
      final book = audiobook('Local').withMetadata({
        'metadataSource': 'manual',
        'cover': 'manual-cover',
        'coverSource': 'manual',
      });
      await library.save([book]);
      final target = AudiobookMetadataTarget(library, book.id);
      final coordinator = MetadataWorkflow(
        [],
        mutations: const OwnerApplicationMutations(),
      );
      final token = MetadataCancellation();
      final review = await coordinator.review(
        target,
        candidate(cover: 'https://example.org/cover.jpg'),
        token,
      );
      expect(review.defaults, isNot(contains('title')));
      expect(review.defaults, isNot(contains('cover')));
      await coordinator.apply(target, review, {'author'}, token);
      final updated = (await library.books()).single;
      expect(updated.metadata.title, 'Local');
      expect(updated.metadata.cover, 'manual-cover');
      expect(updated.metadata.metadataSource, 'manual');
    },
  );
  test(
    'review conflicts reject changed selected fields and preserve later tags',
    () async {
      final library = createAudioLibrary(SharedStore());
      final book = audiobook('Local');
      await library.save([book]);
      final target = AudiobookMetadataTarget(library, book.id);
      final coordinator = MetadataWorkflow(
        [],
        mutations: const OwnerApplicationMutations(),
      );
      final token = MetadataCancellation();
      final review = await coordinator.review(target, candidate(), token);
      await library.replace(
        book.withMetadata({
          'title': 'Edited meanwhile',
          'tags': ['New tag'],
        }),
      );
      await expectLater(
        coordinator.apply(target, review, {'title'}, token),
        throwsA(failure(MetadataFailureKind.conflict)),
      );
      await coordinator.apply(target, review, {'author'}, token);
      expect((await library.books()).single.metadata.title, 'Edited meanwhile');
      expect((await library.books()).single.metadata.tags, ['New tag']);
    },
  );
  test(
    'cancel or revoke access during artwork download never commits metadata',
    () async {
      for (final revoke in [false, true]) {
        final gate = Completer<String>();
        var allowed = true;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(audio, (call) => gate.future);
        final library = createAudioLibrary(
          SharedStore(),
          authorized: (_) => allowed,
        );
        final book = audiobook('Local');
        await library.save([book]);
        final coordinator = MetadataWorkflow(
          [],
          mutations: const OwnerApplicationMutations(),
        );
        final target = AudiobookMetadataTarget(library, book.id);
        final token = MetadataCancellation();
        final review = await coordinator.review(
          target,
          candidate(cover: 'https://example.org/cover.jpg'),
          token,
        );
        final applying = coordinator.apply(target, review, {
          'title',
          'cover',
        }, token);
        await Future<void>.delayed(Duration.zero);
        if (revoke) {
          allowed = false;
        } else {
          token.cancel();
        }
        gate.complete('downloaded-cover');
        await expectLater(
          applying,
          throwsA(
            failure(
              revoke
                  ? MetadataFailureKind.permission
                  : MetadataFailureKind.cancelled,
            ),
          ),
        );
        expect((await library.books()).single.metadata.title, 'Local');
        expect((await library.books()).single.metadata.cover, '');
      }
    },
  );
  test(
    'edit during artwork I/O is detected at the catalog commit boundary',
    () async {
      final gate = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audio, (call) => gate.future);
      final library = createAudioLibrary(SharedStore());
      final book = audiobook('Local');
      await library.save([book]);
      final coordinator = MetadataWorkflow(
        [],
        mutations: const OwnerApplicationMutations(),
      );
      final target = AudiobookMetadataTarget(library, book.id);
      final token = MetadataCancellation();
      final review = await coordinator.review(
        target,
        candidate(cover: 'https://example.org/cover.jpg'),
        token,
      );
      final applying = coordinator.apply(target, review, {
        'title',
        'cover',
      }, token);
      await Future<void>.delayed(Duration.zero);
      await library.replace(
        book.withMetadata({'title': 'Manual while downloading'}),
      );
      gate.complete('cover');
      await expectLater(
        applying,
        throwsA(failure(MetadataFailureKind.conflict)),
      );
      expect(
        (await library.books()).single.metadata.title,
        'Manual while downloading',
      );
    },
  );
  test(
    'shared runner retries only transient requests with bounded backoff',
    () async {
      final runner = MetadataWorkRunner(classify: metadataFailure);
      final delays = <Duration>[];
      var attempts = 0;
      final value = await runner.request(
        () async {
          if (++attempts < 3) throw PlatformException(code: 'network');
          return 42;
        },
        MetadataCancellation(),
        delay: (d) async => delays.add(d),
      );
      expect(value, 42);
      expect(attempts, 3);
      expect(delays.map((d) => d.inMilliseconds), [200, 400]);
      attempts = 0;
      await expectLater(
        runner.request(() async {
          attempts++;
          throw PlatformException(code: 'authentication');
        }, MetadataCancellation()),
        throwsA(isA<PlatformException>()),
      );
      expect(attempts, 1);
    },
  );
  test(
    'second runner cannot overwrite an active collection checkpoint',
    () async {
      final runner = MetadataWorkRunner(classify: metadataFailure);
      final owner = Object();
      final gate = Completer<void>();
      var checkpoints = 0;
      final first = runner.run(
        owner: owner,
        key: 'job',
        work: [1],
        cancellation: MetadataCancellation(),
        checkpoint: () async => checkpoints++,
        process: (_) async => gate.future,
        completed: (_) async {},
      );
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        runner.run(
          owner: owner,
          key: 'job',
          work: [2],
          cancellation: MetadataCancellation(),
          checkpoint: () async => checkpoints++,
          process: (_) async {},
          completed: (_) async {},
        ),
        throwsA(isA<MetadataJobBusy>()),
      );
      expect(checkpoints, 1);
      gate.complete();
      await first;
      expect(checkpoints, 2);
    },
  );
  test(
    'audiobook durable IDs resume without repeating successful lookups',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audio, (call) async {
            if (call.method == 'metadataDbConfigured') return true;
            final title = (call.arguments as Map)['title'] as String;
            calls.add(title);
            return jsonEncode([
              {'title': title, 'providerId': 'audiobookdb:edition:recording'},
            ]);
          });
      final library = createAudioLibrary(SharedStore(), collectionId: 'a');
      await library.save([
        audiobook('One'),
        audiobook('Two'),
        audiobook('Three'),
      ]);
      final job = createAudiobookMetadataJob(library, collectionId: 'a');
      job.addListener(() {
        if (job.done == 1 && job.running) job.cancel();
      });
      await job.run();
      expect(calls, ['One']);
      expect(job.remaining.length, 2);
      final recovered = createAudiobookMetadataJob(library, collectionId: 'a');
      await recovered.recover();
      expect(calls.length, 1);
      expect(recovered.remaining.length, 2);
      await recovered.run(resume: true);
      expect(calls, ['One', 'Two', 'Three']);
      expect(recovered.remaining, isEmpty);
      expect(
        recovered.entries.values.every((v) => (v as Map)['status'] == 'review'),
        true,
      );
      expect(
        (await library.books()).every((b) => b.metadata.providerId.isEmpty),
        true,
      );
      await recovered.markApplied(audiobook('One').id.key);
      await recovered.checkpoint();
      expect(
        ((await library.service.readState(recovered.key))!['entries']
            as Map)[audiobook('One').id.key]['status'],
        'applied',
      );
    },
  );
  test(
    'incompatible audiobook journals are discarded without provider I/O',
    () async {
      final library = createAudioLibrary(SharedStore(), collectionId: 'a');
      await library.save([audiobook('One')]);
      final job = createAudiobookMetadataJob(library, collectionId: 'a');
      await library.service.writeState(job.key, {
        'entries': {
          audiobook('One').id.key: {
            'title': 'One',
            'status': 'failed',
            'error': 'offline',
          },
        },
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(audio, (call) async => false);
      await job.recover();
      expect(job.entries, isEmpty);
      expect(job.remaining, isEmpty);
      expect(job.running, false);
      final restored = createAudiobookMetadataJob(library, collectionId: 'a');
      await restored.recover();
      expect(restored.remaining, job.remaining);
    },
  );
  test('artwork cache is owner scoped, cancellable and never changes child posters', () async {
    final service = ArtworkService();
    var downloads = 0;
    final token = MetadataCancellation();
    const cover = ArtworkCandidate(
      location: 'https://example.org/cover.jpg',
      role: ArtworkRole.cover,
      source: ArtworkSource.online,
      ownerId: 'series',
      provider: 'fixture',
    );
    Future<String> download(String url) async {
      downloads++;
      return 'data:image/jpeg;base64,AA==';
    }

    expect(
      await service.select(cover, token, download: download),
      startsWith('data:'),
    );
    await service.select(cover, token, download: download);
    expect(downloads, 1);
    await service.select(
      const ArtworkCandidate(
        location: 'https://example.org/cover.jpg',
        role: ArtworkRole.cover,
        source: ArtworkSource.online,
        ownerId: 'other',
      ),
      token,
      download: download,
    );
    expect(downloads, 2);
    final original = video('episode');
    final changed = withSelectedArtwork(
      original,
      'posters',
      'series-cover',
      series: true,
    );
    expect(changed.poster, original.poster);
    expect(changed.localPoster, original.localPoster);
    expect(changed.metadata['seriesPoster'], 'series-cover');
  });
  test(
    'series matching resumes durable IDs after provider grouping changes',
    () async {
      final store = SeriesFixtureStore();
      store.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'TV',
          subtype: VideoSubtype.cinema,
        ).toJson(),
      );
      for (var n = 1; n <= 3; n++) {
        store.assets.add(
          VideoAsset.fromJson({
            'id': 'e$n',
            'collectionId': 'c',
            'uri': 'content://e$n',
            'filename': 'Show S01E0$n.mp4',
            'rootUri': 'root',
            'relativePath': 'Show/Season 1/E$n.mp4',
            'metadata': {
              'title': 'Local $n',
              'series': 'Local Show',
              'season': '1',
              'episode': '$n',
            },
          }, VideoSubtype.tv).toJson(),
        );
      }
      final library = createLibraryController(store);
      await library.load();
      final original = buildSeries(library.items('c')).single;
      final job = library.metadataJobs.series(original);
      expect(identical(job, library.metadataJobs.series(original)), true);
      job.addListener(() {
        if (job.done == 1 && job.running) job.cancel();
      });
      final match = MetadataCandidate(
        provider: 'tmdb',
        id: '7',
        entity: MetadataEntityType.television,
        values: {'title': 'Provider episode', 'series': 'Provider Series', 'description': 'Description from provider'},
        attribution: 'TMDB',
      );
      await job.run(match, {'title', 'description', 'series'});
      expect(store.detailCalls, isEmpty);
        expect(job.remaining.toSet(), {'e2', 'e3'});
      expect(job.remaining.length, 2);
      final now = buildSeries(library.items('c'))
          .firstWhere((s) => s.assets.any((a) => a.id == 'e1'));
      final recovered = createSeriesMetadataJob(library, now);
      expect(recovered.key, job.key);
      final receipts = await store.maintenance.jobs.status((_) => true);
      expect(
        receipts.singleWhere((r) => r.key == job.key).outcome,
        JobOutcome.cancelled,
      );
      final held = Completer<void>();
      final conflict = store.maintenance.jobs.run<void>('scan:c', [
        'c',
      ], () => held.future);
      await expectLater(
        recovered.run(match, {'title'}, resume: true),
        throwsA(isA<JobAdmissionBusy>()),
      );
      held.complete();
      await conflict;
      await recovered.run(match, {
        'title',
        'description',
        'series',
      }, resume: true);
      expect(store.detailCalls, isEmpty);
      expect(recovered.remaining, isEmpty);
      expect(
        library
            .items('c')
            .every((a) => a.metadata['description']!.startsWith('Description')),
        true,
      );
    },
  );
  test('review cannot be applied to another title or subtype', () async {
    final library = createAudioLibrary(SharedStore());
    final a = audiobook('One');
    final b = audiobook('Two');
    await library.save([a, b]);
    final coordinator = MetadataWorkflow(
      [],
      mutations: const OwnerApplicationMutations(),
    );
    final token = MetadataCancellation();
    final review = await coordinator.review(
      AudiobookMetadataTarget(library, a.id),
      candidate(),
      token,
    );
    await expectLater(
      coordinator.apply(AudiobookMetadataTarget(library, b.id), review, {
        'title',
      }, token),
      throwsA(failure(MetadataFailureKind.conflict)),
    );
    await expectLater(
      coordinator.review(
        AudiobookMetadataTarget(library, a.id),
        MetadataCandidate(
          provider: 'tmdb',
          id: '1',
          entity: MetadataEntityType.movie,
          values: {},
          attribution: 'TMDB',
        ),
        token,
      ),
      throwsA(failure(MetadataFailureKind.invalidResponse)),
    );
  });
}
