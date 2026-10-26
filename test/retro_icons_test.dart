import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelarticons/pixelarticons.dart';
import 'package:app_shell/app_shell.dart';

void main() {
  test('all app icons have a Pixelarticons equivalent', () {
    final source = File('packages/app_shell/lib/src/retro_icons.dart')
        .readAsStringSync();
    final mapped = RegExp(r'Icons\.(\w+)\s*:')
        .allMatches(source)
        .map((m) => m[1])
        .toSet();
    for (final file in [
      for (final root in ['lib', 'packages/app_shell/lib'])
        ...Directory(root).listSync(recursive: true).whereType<File>(),
    ]) {
      if (!file.path.endsWith('.dart') ||
          file.path.endsWith('retro_icons.dart')) {
        continue;
      }
      for (final match in RegExp(
        r'\bIcons\.(\w+)',
      ).allMatches(file.readAsStringSync())) {
        expect(
          mapped,
          contains(match[1]),
          reason: '${file.path}: ${match[0]} needs a Retro icon',
        );
      }
    }
    for (final icon in retroIcons.values) {
      expect(icon.fontPackage, 'pixelarticons');
      expect(icon.fontFamily, Pixel.iconFontFamily);
    }
  });

  testWidgets(
    'Retro uses library glyphs with semantics, sizing and color; Modern retains Material',
    (tester) async {
      for (final retro in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [
                ThemeTokens.parse({}, retro: retro, pixelFont: retro),
              ],
            ),
            home: const Scaffold(
              body: AppIcon(
                AppIconRole.security,
                size: 32,
                color: Colors.purple,
                semanticLabel: 'Security',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (retro) {
          final glyph = tester.widget<Icon>(find.byIcon(Pixel.shield));
          expect(glyph.size, 32);
          expect(glyph.color, Colors.purple);
        } else {
          expect(find.byIcon(Pixel.shield), findsNothing);
        }
        expect(find.bySemanticsLabel('Security'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'navigation symbols use Pixelarticons and directional arrows mirror in RTL',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [ThemeTokens.parse({}, retro: true, pixelFont: true)],
          ),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Column(
                children: [
                  PixelIcon(PixelSymbol.library),
                  PixelIcon(PixelSymbol.spaces),
                  PixelIcon(PixelSymbol.settings),
                  AppIcon(AppIconRole.back),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Pixel.grid2x22), findsOneWidget);
      expect(find.byIcon(Pixel.blocks), findsOneWidget);
      expect(find.byIcon(Pixel.slidershorizontal), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(Pixel.arrowleft),
          matching: find.byType(Transform),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
