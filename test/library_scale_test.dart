import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/video_scope.dart';

import 'library_test.dart' show MemoryLibrary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'large-library diagnostic retains all records and scoped feed results',
    () async {
      final measurements = <Map<String, int>>[];
      for (final count in [10000, 50000]) {
        final service = MemoryLibrary();
        for (var c = 0; c < 100; c++) {
          service.collections.add(
            VideoCollection(
              id: 'c$c',
              name: 'Collection $c',
              subtype: VideoSubtype.videos,
              locked: c % 10 == 0,
            ).toJson(),
          );
        }
        for (var i = 0; i < count; i++) {
          service.assets.add(
            VideoAsset(
              id: '$i',
              collectionId: 'c${i % 100}',
              uri: 'content://video/$i',
              filename: 'Clip $i.mp4',
              metadata: {
                'title': 'Clip $i',
                'tags': i.isEven ? 'Travel' : 'Family',
              },
              addedAt: i,
              rootUri: 'content://root',
              relativePath: 'Trips/Clip $i.mp4',
            ).toJson(),
          );
        }
        final library = createLibraryController(service);
        final watch = Stopwatch()..start();
        await library.load();
        final load = watch.elapsedMilliseconds;
        watch.reset();
        final items = videoSpaceItems(library);
        final aggregate = watch.elapsedMilliseconds;
        watch.reset();
        final feed = browseVideoFeed(items, tag: 'Travel');
        final filter = watch.elapsedMilliseconds;
        expect(library.assets.length, count);
        expect(items.length, count * .9);
        expect(feed.length, count * .4);
        measurements.add({
          'records': count,
          'collections': 100,
          'loadMs': load,
          'aggregateMs': aggregate,
          'filterSortMs': filter,
        });
        library.dispose();
      }
      final result = {
        'environment': 'Flutter test VM on desktop; synthetic records, not device performance',
        'measurements': measurements,
      };
      Directory('.dart_tool').createSync(recursive: true);
      File(
        '.dart_tool/library-scale.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      // ignore: avoid_print
      print(jsonEncode(result));
    },
  );
}
