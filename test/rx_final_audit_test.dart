import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/core/application/mutations.dart';

import 'library_test.dart' show MemoryLibrary;

class CanonicalProvider implements MetadataProvider {
  @override
  String get id => 'org.example.catalog:metadata';
  @override
  Set<MetadataEntityType> get entities => {MetadataEntityType.movie};
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async =>
      MetadataSearchPage(
        request: request,
        attribution: 'Synthetic',
        candidates: [
          MetadataCandidate(
            provider: id,
            id: 'org.example.catalog:arrival',
            entity: MetadataEntityType.movie,
            values: {
              'title': 'Arrival',
              'year': 2016,
              'description': 'Canonical description',
              'genres': ['Drama', 'Science fiction'],
            },
            attribution: 'Synthetic',
          ),
        ],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('video bulk metadata uses canonical year and external candidate identity without provider parsing', () async {
    final store = MemoryLibrary();
    store.collections.add(
      const VideoCollection(
        id: 'c',
        name: 'Movies',
        subtype: VideoSubtype.movies,
      ).toJson(),
    );
    store.assets.add(
      VideoAsset.fromJson({
        'id': 'a',
        'collectionId': 'c',
        'uri': 'content://a',
        'filename': 'Arrival.2016.mp4',
      }, VideoSubtype.movies).toJson(),
    );
    final workflow = MetadataWorkflow([
      CanonicalProvider(),
    ], mutations: const OwnerApplicationMutations());
    final library = createLibraryController(
      store,
      metadataWorkflow: () => workflow,
    );
    await library.load();
    final job = createMetadataJob(
      library,
      library.collections.single,
      workflow: workflow,
    );
    await job.run();
    expect(job.matched, 1);
    final asset = library.items('c').single;
    expect(asset.metadata['description'], 'Canonical description');
    expect(asset.metadata['genres'], 'Drama, Science fiction');
    expect(asset.metadata['providerCandidate'], 'org.example.catalog:arrival');
    expect(asset.providerId, isNull);
    library.dispose();
  });
}
