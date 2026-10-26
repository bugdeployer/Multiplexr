import 'fixtures/legacy_library_assembly.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/backup_page.dart';
import 'package:multiplexr/src/library/series.dart';
import 'package:multiplexr/src/media/audiobook_hierarchy.dart';
import 'package:multiplexr/src/media/contracts.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'library_tools_test.dart' show ToolsLibrary, setup;
import 'widget_test.dart' show TestDevice;

void main() {
  test(
    'old V1 fixture remains readable through current video and audio adapters',
    () async {
      final input = jsonDecode(
        File('test/fixtures/batch8-backup-v1.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final store = SharedStore();
      store.collections.addAll(
        (input['collections'] as List).map((v) => Map<String, dynamic>.from(v)),
      );
      store.assets.addAll(
        (input['assets'] as List).map((v) => Map<String, dynamic>.from(v)),
      );
      final states = Map<String, dynamic>.from(input['state']);
      for (final entry in states.entries) {
        await store.writeState(
          entry.key,
          Map<String, dynamic>.from(entry.value),
        );
      }
      final library = createLibraryController(store);
      await library.load();
      expect(library.collections, hasLength(3));
      expect(
        library.collections.singleWhere((c) => c.id == 'audio').kind,
        MediaKind.audiobook,
      );
      expect(
        library.collections.singleWhere((c) => c.id == 'audio').locked,
        true,
      );
      final series = buildSeries(library.items('tv')).single;
      expect(series.episodes.single.versions, hasLength(2));
      expect(
        series.assets.every((a) => a.metadata['groupId'] == 'manual-show'),
        true,
      );
      final books = await createAudioLibrary(store).books();
      expect(books, hasLength(2));
      expect(audiobookSeries(books), hasLength(1));
      expect(books.map((b) => b.files.length), [1, 2]);
      expect(books.map((b) => b.chapterMarkers.length), [2, 2]);
      final rawProgress = states.entries
          .singleWhere((e) => e.key.startsWith('progress:'))
          .value;
      final progress = MediaProgress.fromJson(
        Map<String, dynamic>.from(rawProgress),
      ) as AudiobookProgress;
      expect(progress.bookmarks.single.label, 'Keep bookmark');
      expect(progress.positionMs, 3000);
      library.dispose();
    },
  );

  testWidgets(
    'restore preview distinguishes retained permissions from missing roots',
    (tester) async {
      final store = ToolsLibrary();
      final library = await setup(store);
      store.collections.single['roots'] = [
        {'uri': 'content://retained', 'name': 'Retained'},
        {'uri': 'content://missing', 'name': 'Missing'},
      ];
      store.collections.single['rootHealth'] = {
        'content://retained': 'Permission retained — scan to verify files',
        'content://missing': 'Unavailable — reselect this root folder',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LibraryBackupSettings(
                library: library,
                platform: TestDevice(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose backup to restore'));
      await tester.pumpAndSettle();
      expect(
        find.text('Permission retained — scan after restore'),
        findsOneWidget,
      );
      expect(find.text('Needs folder selection'), findsOneWidget);
      expect(store.restores, 0);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
