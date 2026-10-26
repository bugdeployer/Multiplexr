import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'fixtures/legacy_library_assembly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/metadata_search_page.dart';
import 'package:multiplexr/src/metadata/metadata_review_page.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

import 'package:multiplexr/src/metadata/metadata_targets.dart';

import 'library_test.dart' show MatchingLibrary;
import 'media_foundation_test.dart' show SharedStore;
import 'grouped_media_test.dart' show audiobook;

class PagedLibrary extends MatchingLibrary {
  final pages = <String>[];
  @override
  Future<Map<String, dynamic>> searchPage(
    String type,
    String query,
    int page,
  ) async {
    pages.add('$query:$page');
    return {
      'total_pages': 2,
      'total_results': 2,
      'results': [
        {'id': 1, 'title': 'Arrival', 'release_date': '2016-11-11'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> details(
    String type,
    int id, {
    int? season,
    int? episode,
  }) async => {
    'title': 'Arrival',
    'release_date': '2016-11-11',
    'overview': 'Fetched summary',
  };
}

void main() {
  testWidgets(
    'movie lookup without installed providers preserves local metadata',
    (tester) async {
      tester.view.physicalSize = const Size(700, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = PagedLibrary();
      store.collections.add(
        const VideoCollection(
          id: 'c',
          name: 'Films',
          subtype: VideoSubtype.movies,
        ).toJson(),
      );
      store.assets.add(
        VideoAsset.fromJson({
          'id': 'film',
          'collectionId': 'c',
          'uri': 'content://film',
          'filename': 'Arrival.2016.mp4',
          'metadata': {'title': 'Local label', 'year': '2016', 'tags': 'Keep'},
        }, VideoSubtype.movies).toJson(),
      );
      final library = createLibraryController(store);
      await library.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoMetadataSearchPage(
                      library: library,
                      asset: library.items('c').single,
                      query: 'Arrival',
                    ),
                  ),
                ),
                child: const Text('Find'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Find'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No enabled metadata providers'),
        findsOneWidget,
      );
      expect(store.pages, isEmpty);
    },
  );
  testWidgets(
    'review is readable on narrow large-text screens and preserves manual cover defaults',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = createAudioLibrary(SharedStore());
      final book = audiobook('Local').withMetadata({
        'coverSource': 'manual',
        'cover': 'data:image/jpeg;base64,AA==',
      });
      await library.save([book]);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: MetadataReviewPage(
            workflow: MetadataWorkflow(
              [],
              mutations: const OwnerApplicationMutations(),
            ),
            target: AudiobookMetadataTarget(library, book.id),
            candidate: MetadataCandidate(
              provider: 'audible',
              id: 'ASIN',
              entity: MetadataEntityType.audiobook,
              values: {
                'title': 'Online',
                'narrator': 'Reader',
                'edition': 'Unabridged',
              },
              attribution: 'Audible',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Apply selected metadata'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      final coordinator = MetadataWorkflow(
        [],
        mutations: const OwnerApplicationMutations(),
      );
      final review = await coordinator.review(
        AudiobookMetadataTarget(library, book.id),
        MetadataCandidate(
          provider: 'audible',
          id: 'ASIN',
          entity: MetadataEntityType.audiobook,
          values: {'coverUrl': 'https://example.org/image.jpg'},
          attribution: 'Audible',
        ),
        MetadataCancellation(),
      );
      expect(review.defaults, isNot(contains('cover')));
    },
  );
}
