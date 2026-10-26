import 'package:multiplexr/src/bootstrap/settings_assembly.dart';

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shell/app_shell.dart';

import 'widget_test.dart' show TestDevice;

Map<String, dynamic> package({
  Map<String, dynamic> tokens = const {},
  List<Map<String, dynamic>> assets = const [],
}) => {
  ...AppThemeDefinition.bundled!['retro']!.toJson(),
  'version': 2,
  'id': 'custom-v2',
  'name': 'Custom V2',
  'tokens': tokens,
  'assets': assets,
};
Map<String, dynamic> asset(String path, String mime, List<int> bytes) => {
  'path': path,
  'mime': mime,
  'sha256': sha256.convert(bytes).toString(),
  'license': 'OFL-1.1',
  'author': 'Test attribution',
  'data': base64Encode(bytes),
};
const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  test('shared document bounds fixture matches Dart import gates', () {
    final limits = jsonDecode(
      File('test/fixtures/theme_limits.json').readAsStringSync(),
    );
    final v1 = jsonEncode({
      ...AppThemeDefinition.bundled!['retro']!.toJson(),
      'version': 1,
      'padding': 'x' * (limits['v1Bytes'] as int),
    });
    expect(() => AppThemeDefinition.parse(v1), throwsFormatException);
    final v2 = jsonEncode({
      ...package(),
      'padding': 'x' * (limits['packageBytes'] as int),
    });
    expect(() => AppThemeDefinition.parse(v2), throwsFormatException);
  });
  testWidgets('palette reset is visible and usable beside theme selection', (
    tester,
  ) async {
    final settings = createSettingsController(TestDevice());
    await settings.load();
    await settings.appearance(baseChoice: 2);
    await tester.pumpWidget(
      MaterialApp(
        theme: settings.theme,
        home: Scaffold(body: ThemePicker(settings: settings)),
      ),
    );
    final reset = find.byTooltip('Reset theme colors');
    expect(reset.hitTestable(), findsOneWidget);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(settings.themeOverrides, 0);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
  test(
    'exported target packages preserve resolved components and typography',
    () async {
      for (final id in ['retro', 'modern']) {
        final settings = createSettingsController(TestDevice());
        await settings.load();
        await settings.selectTheme(id);
        final old = settings.theme;
        final data = jsonDecode(settings.exportThemeV2());
        await settings.importTheme(jsonEncode(data));
        expect(settings.theme.cardTheme, old.cardTheme);
        final actual = settings.theme.filledButtonTheme.style!,
            before = old.filledButtonTheme.style!;
        for (final states in [
          <WidgetState>{},
          <WidgetState>{WidgetState.disabled},
          <WidgetState>{WidgetState.pressed},
        ]) {
          expect(actual.shape?.resolve(states), before.shape?.resolve(states));
          expect(
            actual.foregroundColor?.resolve(states),
            before.foregroundColor?.resolve(states),
          );
          expect(
            actual.minimumSize?.resolve(states),
            before.minimumSize?.resolve(states),
          );
        }
        expect(settings.theme.inputDecorationTheme, old.inputDecorationTheme);
        expect(settings.theme.textTheme, old.textTheme);
        settings.dispose();
      }
    },
  );
  test(
    'geometry, font and icons vary independently and tokens round trip',
    () async {
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await settings.importTheme(
        jsonEncode(
          package(
            tokens: {
              'geometry': 'rounded',
              'font': 'system',
              'icons': 'pixel',
              'cardRadius': 8,
              'buttonRadius': 3,
              'spacing': 1.2,
              'borderWidth': 2,
              'typography': {
                'heading': {'size': 28, 'weight': 700},
                'body': {'size': 18, 'height': 1.4},
              },
            },
          ),
        ),
      );
      final theme = settings.theme;
      expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Roboto');
      expect(theme.textTheme.bodyMedium!.fontSize, 18);
      expect(theme.extension<ThemeTokens>()!.pixelIcons, true);
      expect(
        AppThemeDefinition.parse(settings.exportTheme()).tokens.toJson(),
        settings.selectedTheme!.tokens.toJson(),
      );
      settings.dispose();
    },
  );
  test('packaged font loads with digest identity and persists across settings reload', () async {
    final bytes = File('packages/app_shell/assets/fonts/Silkscreen-Regular.ttf')
        .readAsBytesSync();
    final settings = createSettingsController(TestDevice());
    await settings.load();
    await settings.importTheme(
      jsonEncode(
        package(
          tokens: {'font': 'assets/custom.ttf'},
          assets: [asset('assets/custom.ttf', 'font/ttf', bytes)],
        ),
      ),
    );
    final family = settings.theme.textTheme.bodyMedium!.fontFamily;
    expect(family, startsWith('multiplexr-'));
    final restored = createSettingsController(settings.platform);
    await restored.load();
    expect(restored.theme.textTheme.bodyMedium!.fontFamily, family);
    await restored.removeTheme('custom-v2');
    expect(restored.selectedTheme!.id, 'retro');
    settings.dispose();
    restored.dispose();
  });
  testWidgets(
    'packaged semantic icon renders offline and material fallback remains available',
    (tester) async {
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await tester.runAsync(
        () => settings.importTheme(
          jsonEncode(
            package(
              tokens: {
                'icons': 'material',
                'iconAssets': {'play': 'assets/play.png'},
              },
              assets: [
                asset('assets/play.png', 'image/png', base64Decode(png)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: settings.theme,
          home: const Scaffold(
            body: Row(
              children: [
                AppIcon(AppIconRole.play, semanticLabel: 'Play'),
                AppIcon(AppIconRole.search),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
  test('invalid assets, references, bounds and nesting cannot replace active theme', () async {
    final settings = createSettingsController(TestDevice());
    await settings.load();
    final before = settings.exportTheme();
    final image = asset('assets/play.png', 'image/png', base64Decode(png));
    final invalid = [
      package(tokens: {'spacing': 10}),
      package(tokens: {'motionMs': 601}),
      package(tokens: {'unknown': 1}),
      package(tokens: {'font': 'https://example.com/font.ttf'}),
      package(
        tokens: {
          'iconAssets': {'play': 'assets/missing.png'},
        },
      ),
      package(
        assets: [
          {...image, 'path': '../play.png'},
        ],
      ),
      package(
        assets: [
          {...image, 'sha256': 'bad'},
        ],
      ),
      package(
        assets: [
          {...image, 'license': ''},
        ],
      ),
      package(assets: [image, image]),
      package(
        assets: [
          asset('assets/bad.ttf', 'font/ttf', [1, 2, 3]),
        ],
      ),
      package(
        tokens: {
          'typography': {
            'body': {'size': 2},
          },
        },
      ),
    ];
    for (final data in invalid) {
      await expectLater(
        settings.importTheme(jsonEncode(data)),
        throwsFormatException,
      );
      expect(settings.exportTheme(), before);
    }
    expect(
      () => AppThemeDefinition.parse('${'[' * 13}0${']' * 13}'),
      throwsFormatException,
    );
    settings.dispose();
  });
  test('PNG dimensions are bounded before decoding', () {
    final bytes = base64Decode(png);
    bytes[16] = 1;
    expect(
      () => AppThemeDefinition.parse(
        jsonEncode(
          package(assets: [asset('assets/huge.png', 'image/png', bytes)]),
        ),
      ),
      throwsFormatException,
    );
  });
  test('failed save preserves active theme and installed packages', () async {
    final device = TestDevice();
    final settings = createSettingsController(device);
    await settings.load();
    final before = settings.exportTheme();
    device.failSave = true;
    await expectLater(
      settings.importTheme(jsonEncode(package())),
      throwsException,
    );
    expect(settings.exportTheme(), before);
    expect(settings.themes.containsKey('custom-v2'), false);
    settings.dispose();
  });
  test('semantic colors remain readable and reduced motion disables button animations', () async {
    final settings = createSettingsController(TestDevice());
    await settings.load();
    settings.reduceMotion = true;
    await settings.importTheme(
      jsonEncode(
        package(
          tokens: {
            'motionMs': 500,
            'darkColors': {
              'surface': '#111111',
              'content': '#111111',
              'muted': '#111111',
            },
          },
        ),
      ),
    );
    final theme = settings.theme;
    expect(
      AppThemeDefinition.contrast(
        theme.colorScheme.surface,
        theme.colorScheme.onSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(theme.filledButtonTheme.style!.animationDuration, Duration.zero);
    expect(
      theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
      greaterThanOrEqualTo(48),
    );
    settings.dispose();
  });
  testWidgets(
    'component gallery supports narrow layout with large text and RTL',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await settings.importTheme(
        jsonEncode(
          package(
            tokens: {'fontScale': 1.2, 'geometry': 'rounded', 'icons': 'pixel'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: SingleChildScrollView(
                  child: ThemeGallery(data: settings.theme),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
