import 'package:multiplexr/src/bootstrap/library_assembly.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/library/backup_page.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/library/library_controller.dart';
import 'package:multiplexr/src/library/tags.dart';
import 'package:multiplexr/src/library/video_scope.dart';

import 'library_test.dart' show MemoryLibrary;
import 'widget_test.dart' show TestDevice;

class ToolsLibrary extends MemoryLibrary {
  int exports = 0, restores = 0, picks = 0;
  Map<String, dynamic>? restored;
  final edits = <Map<String, dynamic>>[];
  @override
  Future<bool> exportBackup() async {
    exports++;
    return true;
  }

  @override
  Future<String?> readBackup() async {
    picks++;
    return jsonEncode({
      'format': 'multiplexr-library',
      'version': 1,
      'collections': collections,
      'assets': assets,
      'queue': [],
    });
  }

  @override
  Future<void> restoreBackup(String json) async {
    restores++;
    restored = Map<String, dynamic>.from(jsonDecode(json));
  }

  @override
  Future<void> editTags(
    List<VideoAsset> selected, {
    required String operation,
    required List<String> tags,
    String? target,
    String? collectionId,
  }) async {
    edits.add({
      'operation': operation,
      'tags': tags,
      'target': target,
      'count': selected.length,
    });
    for (final item in assets) {
      if (collectionId == item['collectionId'] ||
          selected.any(
            (a) => a.collectionId == item['collectionId'] && a.id == item['id'],
          )) {
        final metadata = Map<String, dynamic>.from(item['metadata'] ?? {});
        final old = normalizeTags(metadata['tags'] ?? '');
        metadata['tags'] = operation == 'replace'
            ? tags.join(', ')
            : normalizeTags([...old, ...tags].join(', ')).join(', ');
        item['metadata'] = metadata;
      }
    }
  }
}

Future<LibraryController> setup(
  ToolsLibrary storage, {
  bool locked = false,
}) async {
  storage.collections.add(
    VideoCollection(
      id: 'c',
      name: 'Clips',
      subtype: VideoSubtype.videos,
      locked: locked,
      roots: const [LibraryRoot('content://old', 'Clips')],
    ).toJson(),
  );
  storage.assets.add(
    const VideoAsset(
      id: 'v',
      collectionId: 'c',
      uri: 'content://old/file',
      filename: 'clip.mp4',
      metadata: {'tags': 'Travel'},
      favorite: true,
      positionMs: 500,
    ).toJson(),
  );
  final library = createLibraryController(storage);
  await library.load();
  return library;
}

void main() {
  testWidgets(
    'restore previews and requires confirmation before native replacement',
    (tester) async {
      final service = ToolsLibrary();
      final library = await setup(service);
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
      expect(find.text('Restore preview'), findsOneWidget);
      expect(service.restores, 0);
      await tester.ensureVisible(find.text('Restore this backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore this backup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.restores, 0);
      await tester.tap(find.text('Restore this backup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Replace library'));
      await tester.pumpAndSettle();
      expect(service.restores, 1);
      expect(service.restored!['assets'][0]['favorite'], true);
      expect(service.restored!['assets'][0]['positionMs'], 500);
    },
  );
  testWidgets(
    'locked collection export requires successful device authentication',
    (tester) async {
      final service = ToolsLibrary();
      final library = await setup(service, locked: true);
      final device = TestDevice()..authenticated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LibraryBackupSettings(library: library, platform: device),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export library backup'));
      await tester.pumpAndSettle();
      expect(device.authCalls, 1);
      expect(service.exports, 0);
      device.authenticated = true;
      await tester.tap(find.text('Export library backup'));
      await tester.pumpAndSettle();
      expect(service.exports, 1);
    },
  );
  testWidgets('tag editor saves normalized tags without modifying history', (
    tester,
  ) async {
    final service = ToolsLibrary();
    final library = await setup(service);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  editVideoTags(context, library, library.items('c')),
              child: const Text('Edit tags'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit tags'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      '#Travel, travel; Family',
    );
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();
    expect(videoTags(library.items('c').single), ['Travel', 'Family']);
    expect(library.items('c').single.positionMs, 500);
    expect(library.items('c').single.favorite, true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('backup preview supports large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = ToolsLibrary();
    final library = await setup(service);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LibraryBackupSettings(
                library: library,
                platform: TestDevice(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Choose backup to restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose backup to restore'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Restore this backup'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
