import 'support/space_controls.dart';

import 'package:multiplexr/src/core/application/mutations.dart';

import 'fixtures/legacy_music_provider.dart';

import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/music_page.dart';
import 'package:multiplexr/src/media/music_player.dart';
import 'package:multiplexr/src/media/music_repository.dart';
import 'package:multiplexr/src/media/music_catalog.dart';
import 'package:multiplexr/src/catalog/domain/playlist.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'music_playback_test.dart' show FakeAudio;
import 'music_catalog_test.dart' show scan, source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedStore store;
  late LibraryController library;
  late MusicRepository repository;
  setUp(() {
    store = SharedStore();
    library = createLibraryController(store);
    const collection = VideoCollection(
      id: 'c',
      name: 'Music QA',
      kind: MediaKind.music,
      subtype: VideoSubtype.videos,
      openAction: 'details',
    );
    library.collections = [collection];
    store.collections.add(collection.toJson());
    repository = MusicRepository(library);
    store.states[MusicCatalogRepository.key] = scan([source('1'), source('2')])
        .toJson();
  });
  tearDown(() => library.dispose());
  testWidgets(
    'collection album grid opens contents and Play reaches the Music player',
    (tester) async {
      final audio = FakeAudio(),
          playback = createMusicPlayback(library: library, audio: FakeAudio());
      await tester.pumpWidget(
        MaterialApp(
          home: MusicPage(
            library: library,
            playback: playback,
            collectionId: 'c',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Album'), findsOneWidget);
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.scrollUntilVisible(
        find.text('Play album'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await openSpaceControls(tester);
      await tester.tap(find.text('Play album'));
      await tester.pumpAndSettle();
      expect(find.byType(MusicPlayer), findsOneWidget);
      expect(playback.current, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      playback.dispose();
      audio.dispose();
    },
  );
  testWidgets(
    'local Music space remains available for an excluded collection and returns directly',
    (tester) async {
      library.collections = [
        VideoCollection.fromJson({
          ...library.collections.single.toJson(),
          'includeInGlobalAudio': false,
        }),
      ];
      final playback = createMusicPlayback(
        library: library,
        audio: FakeAudio(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MusicPage(
            library: library,
            playback: playback,
            collectionId: 'c',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openSpaceControls(tester);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Exit Music?'), findsNothing);
      expect(find.text('Music QA'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      playback.dispose();
    },
  );
  test('global playlists retain hidden entries while access projections exclude them', () async {
    final tracks = (await repository.catalog.read()).tracks;
    final playlist = MusicPlaylist(
      id: 'p',
      name: 'Mix',
      scope: const PlaylistScope.global(),
      entries: [
        PlaylistEntry(id: 'one', track: tracks.first.catalogTitle.id),
        PlaylistEntry(id: 'two', track: tracks.first.catalogTitle.id),
      ],
    );
    await repository.savePlaylist(playlist);
    expect(repository.playlistTracks(playlist, tracks), hasLength(2));
    library.collections = [
      VideoCollection.fromJson({
        ...library.collections.single.toJson(),
        'locked': true,
      }),
    ];
    expect(repository.playlistTracks(playlist, tracks), isEmpty);
    expect((await repository.playlists(null)).single.entries, hasLength(2));
    await expectLater(
      repository.savePlaylist(
        MusicPlaylist(
          id: 'new',
          name: 'Denied',
          scope: const PlaylistScope.global(),
          entries: [
            PlaylistEntry(id: 'new', track: tracks.last.catalogTitle.id),
          ],
        ),
      ),
      throwsStateError,
    );
  });
  test('provider paginates releases and maps recording and edition fields separately', () async {
    final uris = <Uri>[];
    final provider = MusicBrainzProvider(
      rateLimit: false,
      get: (uri) async {
        uris.add(uri);
        return MusicResponse(
          200,
          utf8.encode(
            jsonEncode({
              'count': 41,
              'recordings': [
                {
                  'id': 'recording',
                  'title': 'Song',
                  'artist-credit': [
                    {'name': 'Artist'},
                  ],
                  'releases': [
                    {
                      'id': '12345678-1234-1234-1234-123456789abc',
                      'title': 'Album',
                      'date': '2020-01-01',
                      'country': 'US',
                    },
                  ],
                },
              ],
            }),
          ),
        );
      },
    );
    final page =
        await MetadataWorkflow([
          provider,
        ], mutations: const OwnerApplicationMutations()).search(
          const MetadataSearchRequest(
            provider: 'musicbrainz',
            entity: MetadataEntityType.musicTrack,
            title: 'Song',
            creator: 'Artist',
            page: 2,
          ),
          MetadataCancellation(),
        );
    expect(uris.single.queryParameters['offset'], '20');
    expect(page.nextPage, 3);
    expect(page.candidates.single.values['recordingId'], 'recording');
    expect(page.candidates.single.values['album'], 'Album');
    expect(page.candidates.single.values['year'], 2020);
    final target = MusicMetadataTarget(
      repository,
      trackId: (await repository.catalog.read()).tracks.first.id,
    );
    store.states['metadata:music:c'] = {
      'version': 1,
      'entries': {
        target.trackId!.key: {'status': 'review'},
      },
    };
    final coordinator = MetadataWorkflow([
      provider,
    ], mutations: const OwnerApplicationMutations());
    final review = await coordinator.review(
      target,
      page.candidates.single,
      MetadataCancellation(),
    );
    await coordinator.apply(target, review, {
      'title',
      'artist',
    }, MetadataCancellation());
    final track = (await repository.catalog.read()).tracks.first;
    expect(track.metadata.title, 'Song');
    expect(
      store.states['metadata:music:c']!['entries'][track.id.key]['status'],
      'applied',
    );
    expect(track.source.filename, 'Track 1.mp3');
    expect(track.albumId, isNotNull);
  });
  test('bulk lookup checkpoints reviews and retry failures without auto-picking an edition', () async {
    var fail = true;
    final provider = MusicBrainzProvider(
      rateLimit: false,
      get: (_) async => fail
          ? const MusicResponse(429, [])
          : MusicResponse(
              200,
              utf8.encode(
                jsonEncode({
                  'count': 1,
                  'recordings': [
                    {'id': 'r', 'title': 'Track', 'artist-credit': []},
                  ],
                }),
              ),
            ),
    );
    final job = createMusicMetadataJob(repository, 'c', provider);
    await expectLater(
      job.start((await repository.catalog.read()).tracks),
      throwsA(isA<MetadataFailure>()),
    );
    expect(job.entries.values.every((v) => v['status'] == 'failed'), true);
    expect(job.remaining, hasLength(2));
    fail = false;
    await job.start((await repository.catalog.read()).tracks, resume: true);
    expect(job.entries.values.every((v) => v['status'] == 'review'), true);
    expect(job.remaining, isEmpty);
    final savedReviews = jsonEncode(job.entries);
    await job.start((await repository.catalog.read()).tracks);
    expect(jsonEncode(job.entries), savedReviews);
    expect(job.total, 0);
    expect(store.states[job.key]!['entries'], isNotEmpty);
    job.dispose();
  });
  test('cancelled Music lookup never returns a reviewable result', () async {
    final cancellation = MetadataCancellation()..cancel();
    var called = false;
    final provider = MusicBrainzProvider(
      rateLimit: false,
      get: (_) async {
        called = true;
        return const MusicResponse(200, []);
      },
    );
    await expectLater(
      MetadataWorkflow([
        provider,
      ], mutations: const OwnerApplicationMutations()).search(
        const MetadataSearchRequest(
          provider: 'musicbrainz',
          entity: MetadataEntityType.musicTrack,
          title: 'Song',
        ),
        cancellation,
      ),
      throwsA(isA<MetadataFailure>()),
    );
    expect(called, false);
  });
  test('Music metadata review rejects changes made after review', () async {
    final track = (await repository.catalog.read()).tracks.first;
    final target = MusicMetadataTarget(repository, trackId: track.id);
    final candidate = MetadataCandidate(
      provider: 'musicbrainz',
      id: 'r',
      entity: MetadataEntityType.musicTrack,
      values: {'title': 'Online title'},
      attribution: 'MusicBrainz',
    );
    final coordinator = MetadataWorkflow(
      [],
      mutations: const OwnerApplicationMutations(),
    );
    final review = await coordinator.review(
      target,
      candidate,
      MetadataCancellation(),
    );
    await repository.patchTrack(
      track.id,
      (t) => t.corrected({'title': 'My corrected title'}),
    );
    await expectLater(
      coordinator.apply(target, review, {'title'}, MetadataCancellation()),
      throwsA(isA<MetadataFailure>()),
    );
    expect(
      (await repository.catalog.read()).tracks.first.metadata.title,
      'My corrected title',
    );
  });
  test(
    'Music artwork lists square thumbnails and treats absent covers as empty',
    () async {
      final provider = MusicBrainzProvider(
        rateLimit: false,
        get: (_) async => MusicResponse(
          200,
          utf8.encode(
            jsonEncode({
              'images': [
                {
                  'thumbnails': {'500': 'http://archive.org/cover.jpg'},
                },
              ],
            }),
          ),
        ),
      );
      expect(await provider.artwork('12345678-1234-1234-1234-123456789abc'), [
        'https://archive.org/cover.jpg',
      ]);
      expect(await provider.artwork('invalid'), isEmpty);
    },
  );
  for (final view in [
    CatalogView.grid,
    CatalogView.list,
    CatalogView.compact,
  ]) {
    testWidgets(
      'Music $view layout remains usable at narrow width and large text',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        library.collections = [
          VideoCollection.fromJson({
            ...library.collections.single.toJson(),
            'view': view.name,
          }),
        ];
        final playback = createMusicPlayback(
          library: library,
          audio: FakeAudio(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: MusicPage(
                library: library,
                playback: playback,
                collectionId: 'c',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Album'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        playback.dispose();
      },
    );
  }
  testWidgets(
    'Music collection clears revoked artwork before asynchronous reload',
    (tester) async {
      final playback = createMusicPlayback(
        library: library,
        audio: FakeAudio(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MusicPage(
            library: library,
            playback: playback,
            collectionId: 'c',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Album'), findsOneWidget);
      library.collections = [
        VideoCollection.fromJson({
          ...library.collections.single.toJson(),
          'locked': true,
        }),
      ];
      library.notifyListeners();
      await tester.pump();
      expect(find.text('Album'), findsNothing);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      playback.dispose();
    },
  );
  test('showcase ordering uses added and playback timestamps instead of alphabetic order', () async {
    final sourceTracks = (await repository.catalog.read()).tracks;
    final first = MusicAlbum(
      CatalogIdentity('c', 'a', CatalogEntityKind.group),
      [sourceTracks.first],
      {'title': 'A'},
    );
    final last = MusicAlbum(
      CatalogIdentity('c', 'z', CatalogEntityKind.group),
      [sourceTracks.last],
      {'title': 'Z'},
    );
    final extras = {
      'titles': {
        sourceTracks.first.id.key: {'addedAt': 1},
        sourceTracks.last.id.key: {'addedAt': 2},
      },
    };
    expect(
      orderedMusicAlbums([first, last], extras, {}, 'recent').first.title,
      'Z',
    );
    expect(
      orderedMusicAlbums(
        [first, last],
        extras,
        {sourceTracks.first.id: 5},
        'progress',
      ).first.title,
      'A',
    );
  });
}
