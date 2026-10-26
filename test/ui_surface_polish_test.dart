import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/bootstrap/library_assembly.dart';
import 'package:multiplexr/src/experience/collection/collection_experience.dart';
import 'package:multiplexr/src/library/library_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/session_mini_player.dart';

import 'media_foundation_test.dart' show SharedStore;
import 'music_playback_test.dart' show FakeAudio;
import 'music_catalog_test.dart' show scan, source;

void main() {
  testWidgets(
    'selection remains inside the same card bounds in rows and grids',
    (tester) async {
      for (final row in [false, true]) {
        Size? original;
        for (final selected in <bool?>[null, false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 280,
                  child: MediaItemSelection(
                    selected: selected,
                    reserveLeading: row,
                    onToggle: () {},
                    child: const Card(
                      margin: EdgeInsets.zero,
                      child: SizedBox(height: 120, width: double.infinity),
                    ),
                  ),
                ),
              ),
            ),
          );
          final card = tester.getRect(find.byType(Card));
          original ??= card.size;
          expect(card.size, original);
          if (selected != null) {
            final box = tester.getRect(find.byType(Checkbox));
            expect(box.left - card.left, 4);
            expect(box.top - card.top, 4);
            expect(
              find.ancestor(
                of: find.byType(Checkbox),
                matching: find.byType(Card),
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
  testWidgets(
    'mini-player progress never paints outside rounded corners at progress endpoints',
    (tester) async {
      final library = createLibraryController(SharedStore());
      library.collections = [
        const VideoCollection(
          id: 'c',
          name: 'Music',
          kind: MediaKind.music,
          subtype: VideoSubtype.videos,
        ),
      ];
      final audio = FakeAudio();
      final playback = createMusicPlayback(library: library, audio: audio);
      final track = scan([source('1')]).tracks.single;
      await playback.play([track], start: track.id, collectionId: 'c');
      final boundary = GlobalKey();
      for (final position in [0, 1, 500, 990, 1000]) {
        audio.state = AudioState({
          'id': track.id.toJson(),
          'positionMs': position,
          'durationMs': 1000,
          'playing': false,
        });
        audio.notifyListeners();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: ThemeData(
                cardTheme: const CardThemeData(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
              ),
              home: Scaffold(
                backgroundColor: const Color(0xffff00ff),
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: SessionMiniPlayer(playback: playback),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final material = find
            .descendant(of: find.byType(Card), matching: find.byType(Material))
            .first;
        final bounds = tester.getRect(material);
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          for (final x in [
            (bounds.left + 1).floor(),
            (bounds.right - 2).floor(),
          ]) {
            final y = (bounds.bottom - 2).floor(),
                offset = ((bounds.bottom - 2).floor() * image.width + x) * 4;
            expect(y, greaterThan(0));
            expect(
              bytes!.buffer.asUint8List(offset, 4),
              [255, 0, 255, 255],
              reason:
                  'Progress $position must remain inside the rounded surface',
            );
          }
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      playback.dispose();
      library.dispose();
    },
  );
}
