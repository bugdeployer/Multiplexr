import 'package:multiplexr/src/bootstrap/settings_assembly.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_shell/app_shell.dart';

import 'widget_test.dart' show TestDevice;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppThemeDefinition.loadBundled();
  });
  String custom({String font = 'pixel', String style = 'retro'}) => jsonEncode({
    ...AppThemeDefinition.bundled!['retro']!.toJson(),
    'id': 'my-theme',
    'name': 'My theme',
    'font': font,
    'tokens': {
      ...AppThemeDefinition.bundled!['retro']!.tokens.toJson(),
      'font': font,
    },
    'style': style,
    'dark': {'background': '#050505', 'accent': '#BEF638'},
  });
  test('bundled themes, custom colors and fonts survive recreation', () async {
    final device = TestDevice();
    final settings = createSettingsController(device);
    await settings.load();
    expect(settings.selectedTheme!.id, 'retro');
    await settings.importTheme(custom(font: 'system'));
    expect(settings.base, const Color(0xff050505));
    expect(settings.accent, const Color(0xffbef638));
    expect(
      settings.theme.textTheme.bodyMedium!.fontFamily,
      isNot('Silkscreen'),
    );
    expect(settings.theme.cardTheme.shape, isA<PixelBorder>());
    final restored = createSettingsController(device);
    await restored.load();
    expect(restored.selectedTheme!.id, 'my-theme');
    expect(restored.accent, settings.accent);
    await restored.appearance(baseChoice: 2);
    expect(restored.base, darkBases[2].color);
    expect(restored.accent, settings.accent);
    final exported = AppThemeDefinition.parse(restored.exportTheme());
    expect(exported.darkBackground, darkBases[2].color);
    expect(exported.darkAccent, settings.accent);
    await restored.selectTheme('modern');
    expect(restored.pixel, false);
    expect(restored.theme.cardTheme.shape, isA<RoundedRectangleBorder>());
    await restored.selectTheme('retro');
    expect(
      restored.theme.textTheme.bodyMedium!.fontFamily,
      restored.selectedTheme!.tokens.fontFamily,
    );
    await restored.selectTheme('my-theme');
    await restored.removeTheme('my-theme');
    expect(restored.selectedTheme!.id, 'retro');
    final again = createSettingsController(device);
    await again.load();
    expect(again.themes.containsKey('my-theme'), false);
  });
  test('Retro and Modern switching preserves independent light and dark palette selections', () async {
    final device = TestDevice();
    final settings = createSettingsController(device);
    await settings.load();
    await settings.appearance(isDark: true, baseChoice: 2, accentChoice: 1);
    await settings.appearance(isDark: false, baseChoice: 0, accentChoice: 7);
    final before = AppThemeDefinition.parse(settings.exportTheme());
    await settings.selectTheme('modern');
    final modern = AppThemeDefinition.parse(settings.exportTheme());
    expect(modern.darkBackground, before.darkBackground);
    expect(modern.darkAccent, before.darkAccent);
    expect(modern.lightBackground, before.lightBackground);
    expect(modern.lightAccent, before.lightAccent);
    final restored = createSettingsController(device);
    await restored.load();
    await restored.selectTheme('retro');
    expect(restored.base, settings.base);
    expect(restored.accent, settings.accent);
    expect(restored.themeOverrides, 15);
    await restored.appearance(isDark: true);
    expect(restored.base, before.darkBackground);
    expect(restored.accent, before.darkAccent);
    settings.dispose();
    restored.dispose();
  });
  test('invalid files and failed storage preserve the active theme', () async {
    final device = TestDevice();
    final settings = createSettingsController(device);
    await settings.load();
    final before = settings.exportTheme();
    final badContrast = jsonDecode(custom()) as Map<String, dynamic>;
    badContrast['light'] = {'background': '#FFFFFF', 'accent': '#FFFFFF'};
    for (final text in [
      '{}',
      '{',
      jsonEncode(badContrast),
      ' ' * 17000,
      custom().replaceAll('"version":2', '"version":999'),
      custom().replaceAll('#BEF638', 'https://example.com/image.png'),
      AppThemeDefinition.bundled!['retro']!.encode(),
    ]) {
      await expectLater(settings.importTheme(text), throwsFormatException);
      expect(settings.exportTheme(), before);
    }
    device.failSave = true;
    await expectLater(settings.importTheme(custom()), throwsException);
    expect(settings.themes.containsKey('my-theme'), false);
    await expectLater(settings.selectTheme('modern'), throwsException);
    expect(settings.exportTheme(), before);
  });
  test(
    'corrupt persisted themes fall back without locking out the application',
    () async {
      final device = TestDevice()..values['themeState'] = '{bad';
      final settings = createSettingsController(device);
      await settings.load();
      expect(settings.ready, true);
      expect(settings.locked, false);
      expect(settings.themeWarning, isNotNull);
      expect(settings.selectedTheme!.id, 'retro');
    },
  );
  testWidgets(
    'theme editor requires preview before applying and supports narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = createSettingsController(TestDevice());
      await settings.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: settings.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(child: ThemePicker(settings: settings)),
          ),
        ),
      );
      await tester.tap(find.text('Create / paste'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), custom());
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed,
        isNull,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Preview'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('My theme'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(settings.selectedTheme!.id, 'my-theme');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Retro switch exposes toggled state and disables interaction', (
    tester,
  ) async {
    final settings = createSettingsController(TestDevice());
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: settings.theme,
        home: Scaffold(
          body: InterfaceSwitchListTile(
            title: const Text('Background playback'),
            value: false,
            onChanged: (v) => changed = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Background playback'));
    expect(changed, true);
    expect(find.byType(Switch), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        theme: settings.theme,
        home: const Scaffold(
          body: InterfaceSwitchListTile(
            title: Text('Background playback'),
            value: true,
            onChanged: null,
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(InterfaceSwitchListTile)),
      matchesSemantics(
        label: 'Background playback',
        hasEnabledState: true,
        isEnabled: false,
        hasSelectedState: true,
        isFocusable: true,
        hasFocusAction: true,
        hasToggledState: true,
        isToggled: true,
      ),
    );
  });
}
