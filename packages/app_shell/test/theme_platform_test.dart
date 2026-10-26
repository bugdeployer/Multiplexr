import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shell/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every semantic icon role has a readable bundled glyph', () {
    expect(appIconData.keys.toSet(), AppIconRole.values.toSet());
  });
  testWidgets(
    'all packages style shared controls in both modes, large text and RTL',
    (tester) async {
      await tester.runAsync(initializeAppShell);
      final settings = ShellSettingsController(
        const MethodChannelShellPlatform(),
      );
      await tester.runAsync(settings.load);
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final id in ['modern', 'minimal', 'retro']) {
        for (final dark in [false, true]) {
          for (final rtl in [false, true]) {
            for (final scale in [1.0, 2.0]) {
              final definition = settings.themes[id]!;
              final data = settings.previewTheme(definition, night: dark);
              await tester.pumpWidget(
                MaterialApp(
                  theme: data,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Directionality(
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: child!,
                    ),
                  ),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: ThemeGallery(data: data),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$id dark=$dark rtl=$rtl scale=$scale',
              );
              expect(data.materialTapTargetSize, MaterialTapTargetSize.padded);
              expect(
                AppThemeDefinition.contrast(
                  data.colorScheme.onSurface,
                  data.colorScheme.surface,
                ),
                greaterThanOrEqualTo(4.5),
              );
              expect(data.extension<ThemeTokens>(), isNotNull);
            }
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  testWidgets(
    'warm packaged fonts allow repeated theme selection through the picker',
    (tester) async {
      await tester.runAsync(initializeAppShell);
      final settings = ShellSettingsController(
        const MethodChannelShellPlatform(),
      );
      await tester.runAsync(settings.load);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => MaterialApp(
            theme: settings.theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ThemePicker(settings: settings),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in ['Modern', 'Minimal', 'Retro']) {
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(settings.selectedTheme!.name, name);
      }
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  testWidgets(
    'packaged icons replace every role and missing assets retain glyph fallback',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final asset = ThemeAsset.parse({
        'path': 'assets/mark.png',
        'mime': 'image/png',
        'sha256': sha256.convert(bytes).toString(),
        'author': 'Example',
        'license': 'CC0',
        'data': base64Encode(bytes),
      });
      final tokens = ThemeTokens.parse(
        {
          'iconAssets': {
            for (final role in AppIconRole.values) role.name: 'assets/mark.png',
          },
        },
        retro: false,
        pixelFont: false,
        assets: {asset.path: asset},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [tokens]),
          home: Scaffold(
            body: Wrap(
              children: [for (final role in AppIconRole.values) AppIcon(role)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(AppIconRole.values.length));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        const MaterialApp(home: AppIcon(AppIconRole.back)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Icon), findsOneWidget);
      expect(
        () => ThemeTokens.parse(
          {
            'iconAssets': {'inventedRole': 'assets/mark.png'},
          },
          retro: false,
          pixelFont: false,
          assets: {asset.path: asset},
        ),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'accessibility overrides theme motion and compact controls retain touch targets',
    (tester) async {
      Duration? duration;
      double? spacing;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [
              const AppPresentationPolicy(reducedMotion: true, compact: true),
            ],
          ),
          home: Builder(
            builder: (context) {
              duration = AppMotion.duration(context);
              spacing = AppSpacing.of(context).value(20);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(duration, Duration.zero);
      expect(spacing, 18);
    },
  );
}
