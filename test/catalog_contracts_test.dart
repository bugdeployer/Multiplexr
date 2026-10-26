import 'package:multiplexr/src/media/audio_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/contracts.dart' show MediaId, MediaKind;
import 'package:multiplexr/src/media/video_projections.dart';
import 'package:multiplexr/src/media/audio_adapter.dart';

import 'grouped_media_test.dart' show audiobook;

void main() {
  test('all eight subtypes have their declared parent; only current flows are available', () {
    expect(MediaType.values.length, 4);
    expect(appSubtypes.definitions.length, 8);
    expect(appSubtypes.enabled.map((d) => d.id).toSet(), {
      MediaSubtype.moviesTv,
      MediaSubtype.videos,
      MediaSubtype.audiobooks,
      MediaSubtype.music,
      MediaSubtype.ebook,
      MediaSubtype.comics,
    });
    for (final id in MediaSubtype.values) {
      expect(appSubtypes.definition(id).type, id.type);
      if (!appSubtypes.definition(id).enabled) {
        expect(() => appSubtypes.requireEnabled(id), throwsUnsupportedError);
        expect(
          appSubtypes.forType(id.type).map((d) => d.id),
          isNot(contains(id)),
        );
      }
    }
    expect(
      appSubtypes
          .definition(MediaSubtype.audiobooks)
          .hierarchy
          .titleRequiresGroup,
      true,
    );
    expect(appSubtypes.definition(MediaSubtype.moviesTv).hierarchy.groups, {
      CatalogGroupKind.series,
      CatalogGroupKind.season,
    });
  });
  test('registry rejects duplicates, incompatible engines and missing implementation bindings', () {
    final video = appSubtypes.definition(MediaSubtype.videos);
    expect(() => SubtypeRegistry([video, video]), throwsArgumentError);
    expect(
      () => SubtypeRegistry([
        SubtypeDefinition(
          id: MediaSubtype.photo,
          engine: MediaEngineKind.audio,
          hierarchy: HierarchyDefinition(),
          enabled: false,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => appSubtypes.validateBindings(
        collectionRoutes: {MediaSubtype.videos},
        engines: {MediaEngineKind.video},
      ),
      throwsStateError,
    );
    expect(
      () => appSubtypes.validateBindings(
        collectionRoutes: {MediaSubtype.photo},
        engines: {MediaEngineKind.audio},
      ),
      throwsUnsupportedError,
    );
  });
  for (final kind in MediaKind.values) {
    for (final subtype in VideoSubtype.values) {
      test(
        'legacy collection adapter preserves $kind/$subtype storage and roots',
        () {
          final original = VideoCollection(
            id: 'collection:[]',
            name: 'Example',
            kind: kind,
            subtype: subtype,
            locked: true,
            includeInGlobalCinema: false,
            includeInGlobalVideos: true,
            includeInGlobalAudio: false,
            roots: const [
              LibraryRoot(
                'content://root/one',
                'One',
                contentSubtype: VideoSubtype.tv,
              ),
              LibraryRoot(
                'content://root/two',
                'Two',
                contentSubtype: VideoSubtype.movies,
              ),
            ],
            audioRate: 1.5,
            autoplayNext: true,
            openAction: 'details',
          );
          final before = original.toJson();
          final neutral = original.catalogCollection;
          expect(neutral.id, original.id);
          expect(
            neutral.subtype,
            kind == MediaKind.audiobook
                ? MediaSubtype.audiobooks
                : kind == MediaKind.music
                ? MediaSubtype.music
                : subtype == VideoSubtype.videos
                ? MediaSubtype.videos
                : MediaSubtype.moviesTv,
          );
          expect(
            neutral.roots.map((r) => r.uri),
            original.roots.map((r) => r.uri),
          );
          expect(neutral.roots.first.contentHint, 'tv');
          expect(
            neutral.access.includeInGlobal,
            kind == MediaKind.video && subtype == VideoSubtype.videos,
          );
          expect(neutral.access.eligibleGlobally, false);
          expect(
            original.mediaCollection.access.includeInGlobal,
            neutral.access.includeInGlobal,
          );
          expect(() => neutral.roots.clear(), throwsUnsupportedError);
          expect(original.toJson(), before);
        },
      );
    }
  }
  test('a multi-file audiobook stays one title and legacy IDs/progress keys stay unchanged', () {
    final base = audiobook('Member', series: 'Saga');
    final book = Audiobook(
      id: base.id,
      metadata: base.metadata,
      files: [
        ...base.files,
        const AudioFile(
          id: 'second',
          uri: 'content://audio/second',
          filename: '02.mp3',
        ),
      ],
    );
    final before = book.toJson();
    final title = book.catalogTitle;
    expect(title.id.entityId, book.id.itemId);
    expect(title.sources.length, book.files.length);
    expect(title.metadata, same(book.metadata));
    expect(() => title.sources.clear(), throwsUnsupportedError);
    expect(book.toJson(), before);
    const id = MediaId(MediaKind.audiobook, 'a:[]', 'book/one');
    expect(id.key, '["audiobook","a:[]","book/one"]');
    expect(MediaId.fromJson(id.toJson()), id);
  });
  test(
    'video adapter preserves unavailable source and rejects audio subtype',
    () {
      final asset = VideoAsset(
        id: 'id',
        collectionId: 'c',
        uri: 'content://video/id',
        filename: 'movie.mkv',
        metadata: {'title': 'Movie'},
        durationMs: 1000,
        width: 1920,
        height: 1080,
        addedAt: 1,
        available: false,
      );
      final before = asset.toJson();
      final title = asset.asCatalogTitle(MediaSubtype.moviesTv);
      expect(title.sources.single.available, false);
      expect(title.id.entityId, asset.id);
      expect(() => title.metadata['title'] = 'Changed', throwsUnsupportedError);
      expect(
        () => asset.asCatalogTitle(MediaSubtype.audiobooks),
        throwsArgumentError,
      );
      expect(asset.toJson(), before);
    },
  );
  test('group identities and membership reject invalid ownership without conflating curated groups', () {
    final group = CatalogIdentity('c', 'series', CatalogEntityKind.group);
    final title = CatalogIdentity('c', 'title', CatalogEntityKind.title);
    expect(
      GroupMembership(
        parent: group,
        child: title,
        kind: MembershipKind.structural,
        order: 0,
      ).child,
      title,
    );
    expect(
      () => GroupMembership(
        parent: group,
        child: group,
        kind: MembershipKind.structural,
        order: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => GroupMembership(
        parent: group,
        child: CatalogIdentity('other', 'title', CatalogEntityKind.title),
        kind: MembershipKind.curated,
        order: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => CatalogIdentity('', 'x', CatalogEntityKind.title),
      throwsArgumentError,
    );
  });
  test(
    'single M4B preserves embedded chapters without producing separate titles',
    () {
      final base = audiobook('Compiled');
      final book = Audiobook(
        id: base.id,
        metadata: base.metadata,
        files: base.files,
        chapters: [
          AudiobookChapterMarker(
            id: 'intro',
            fileId: base.files.single.id,
            title: 'Introduction',
            endMs: 10000,
          ),
          AudiobookChapterMarker(
            id: 'chapter',
            fileId: base.files.single.id,
            title: 'Chapter 1',
            startMs: 10000,
            endMs: 60000,
          ),
        ],
      );
      final before = book.toJson();
      final title = book.catalogTitle;
      expect(title.sources.length, 1);
      expect(title.segments.map((s) => s.id), ['intro', 'chapter']);
      expect(title.segments.last.startMs, 10000);
      expect(title.segments.last.endMs, 60000);
      expect(
        title.segments.every((s) => s.sourceId == title.sources.single.id),
        true,
      );
      expect(() => title.segments.clear(), throwsUnsupportedError);
      expect(book.toJson(), before);
    },
  );
  test('title rejects invalid internal navigation references and ranges', () {
    final segment = CatalogSegment(
      id: 'chapter',
      sourceId: 'missing',
      title: 'Chapter',
      startMs: 0,
    );
    expect(
      () => CatalogTitle(
        id: CatalogIdentity('c', 't', CatalogEntityKind.title),
        subtype: MediaSubtype.audiobooks,
        title: 'Title',
        metadata: const {},
        sources: const [],
        segments: [segment],
      ),
      throwsArgumentError,
    );
    expect(
      () => CatalogSegment(
        id: 'chapter',
        sourceId: 'file',
        title: 'Chapter',
        startMs: 1000,
        endMs: 999,
      ),
      throwsArgumentError,
    );
    final source = const CatalogSource(
      id: 'missing',
      uri: 'content://audio',
      name: 'Audio',
    );
    expect(
      () => CatalogTitle(
        id: CatalogIdentity('c', 't', CatalogEntityKind.title),
        subtype: MediaSubtype.audiobooks,
        title: 'Title',
        metadata: const {},
        sources: [source],
        segments: [segment, segment],
      ),
      throwsArgumentError,
    );
  });
  test('group carries its subtype separately from structural group kind', () {
    final group = CatalogGroup(
      id: CatalogIdentity('c', 'g', CatalogEntityKind.group),
      subtype: MediaSubtype.audiobooks,
      kind: CatalogGroupKind.series,
      metadata: 'Saga',
    );
    expect(group.subtype.type, MediaType.audio);
    expect(group.kind, CatalogGroupKind.series);
  });
}
