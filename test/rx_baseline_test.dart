import 'fixtures/legacy_library_assembly.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/backup_page.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/music_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_annotations.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';
import 'package:multiplexr/src/reading/domain/reading_index.dart';
import 'package:multiplexr/src/reading/domain/reading_management.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'music_catalog_test.dart' show scan, source;

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('RX mixed seed retains identities and all reading styles through codecs', () async {
    final backup = fixture('batch8-backup-v1');
    final reading = fixture('reading-management-v1');
    final catalog = reading['catalog'] as Map<String, dynamic>;
    // Clone existing valid comic rows, retaining publication/source structure.
    for (final style in ['manga', 'manhua', 'manhwa']) {
      for (final key in ['collections', 'groups', 'titles', 'memberships']) {
        final rows = catalog[key] as List;
        for (final original
            in rows
                .where(
                  (r) => key == 'collections'
                      ? r['id'] == 'comics'
                      : r['collectionId'] == 'comics',
                )
                .toList()) {
          final row = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
          if (key == 'collections') {
            row['id'] = style;
            row['name'] = 'RX $style';
          } else {
            row['collectionId'] = style;
          }
          if (row['metadata'] is Map) row['metadata']['comicStyle'] = style;
          rows.add(row);
        }
      }
    }
    catalog['progress'] = fixture('reading-v1')['base']['progress'];
    catalog['collections'][0]['locked'] = true;
    catalog['collections'][0]['includeInGlobal'] = false;
    catalog['titles'][0]['source']['available'] = false;
    reading['index']['entries'][0]['manualFields'] = ['title'];
    final decoded = ReadingCodec.decode(catalog);
    ReadingIndex(reading['index'], decoded);
    ReadingManagement(reading['management'], decoded);
    final annotationData = fixture('reading-annotations-v1')['annotations'];
    ReadingAnnotationCodec.decode(annotationData, decoded);
    final music = scan([source('rx-track', track: 1)], collection: 'rx-music');
    final musicCollection = const VideoCollection(
      id: 'rx-music',
      name: 'RX Music',
      kind: MediaKind.music,
      subtype: VideoSubtype.videos,
    ).toJson();
    (backup['collections'] as List).add(musicCollection);
    (backup['state'] as Map<String, dynamic>).addAll(<String, dynamic>{
      ReadingCodec.key: ReadingCodec.encode(decoded),
      ReadingIndex.key: reading['index'],
      ReadingManagement.key: reading['management'],
      ReadingAnnotationCodec.key: annotationData,
      MusicCatalogRepository.key: music.toJson(),
    });
    final restored = jsonDecode(jsonEncode(backup)) as Map<String, dynamic>;
    expect(
      restored,
      fixture('rx-mixed-backup-v1'),
      reason: 'Preserve the reviewed seed across architecture changes.',
    );
    final states = restored['state'] as Map<String, dynamic>;
    final restoredReading = ReadingCodec.decode(states[ReadingCodec.key]);
    expect(ReadingCodec.encode(restoredReading), ReadingCodec.encode(decoded));
    expect(
      restoredReading.titles.map((t) => t.catalog.metadata.comicStyle?.name),
      containsAll(['manga', 'manhua', 'manhwa']),
    );
    expect(
      MusicCatalog.fromJson(states[MusicCatalogRepository.key]).toJson(),
      music.toJson(),
    );
    final store = SharedStore();
    store.collections.addAll(
      (restored['collections'] as List).cast<Map<String, dynamic>>(),
    );
    store.assets.addAll(
      (restored['assets'] as List).cast<Map<String, dynamic>>(),
    );
    for (final e in states.entries) {
      await store.writeState(e.key, Map<String, dynamic>.from(e.value));
    }
    final library = createLibraryController(store);
    await library.load();
    expect(library.collections, hasLength(4));
    expect(await createAudioLibrary(store).books(), hasLength(2));
    expect(backupSummary(restored), contains('1 music tracks'));
    library.dispose();
    final output = File('build/test-fixtures/mixed-backup.json');
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(restored),
    );
  });
}
