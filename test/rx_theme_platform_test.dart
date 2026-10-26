import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';
import 'package:multiplexr/src/experience/plugins/plugin_settings_page.dart';
import 'package:multiplexr/src/experience/plugins/package_manager_page.dart';
import 'package:app_shell/app_shell.dart';

import 'rx_plugin_gateway_test.dart' show Harness;
import 'rx_plugin_settings_page_test.dart' show SettingsBackend, configured;
import 'widget_test.dart' show TestDevice;

void main() {
  setUpAll(() async {
    await AppThemeDefinition.loadBundled();
  });
  test('standalone SDK themes install, update, persist and remove to bundled fallback', () async {
    for (final name in ['rounded-modern', 'square-minimal', 'stepped-retro']) {
      final device = TestDevice();
      final settings = createSettingsController(device);
      await settings.load();
      final source = File(
        'packages/multiplexr_plugin_sdk/examples/themes/$name.theme.json',
      ).readAsStringSync();
      final data = jsonDecode(source) as Map<String, dynamic>;
      await settings.importTheme(source);
      expect(settings.selectedTheme!.id, data['id']);
      data['name'] = 'Updated $name';
      await settings.importTheme(jsonEncode(data));
      expect(settings.selectedTheme!.name, 'Updated $name');
      final restored = createSettingsController(device);
      await restored.load();
      expect(restored.selectedTheme!.id, data['id']);
      await restored.removeTheme(data['id'] as String);
      expect(restored.selectedTheme!.id, 'retro');
      expect(restored.themes.containsKey(data['id']), false);
      restored.dispose();
      settings.dispose();
    }
  });
  test('shipping presentation uses explicit semantic icons', () {
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) =>
              RegExp(r'\b(?:Icons\.|IconData\b|InterfaceIcon\(|PixelIcon\()')
                  .hasMatch(f.readAsStringSync()),
        )
        .map((f) => f.path)
        .toList();
    expect(violations, isEmpty);
  });
  for (final theme in ['modern', 'minimal', 'retro']) {
    for (final dark in [false, true]) {
      for (final rtl in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'plugin settings $theme dark=$dark rtl=$rtl scale=$scale',
            (tester) async {
              tester.view.physicalSize = const Size(360, 800);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final settings = createSettingsController(TestDevice());
              await tester.runAsync(() async {
                await settings.load();
                await settings.selectTheme(theme);
              });
              settings.dark = dark;
              final h = Harness();
              final backend = SettingsBackend()..records = [configured()];
              final manager = PluginManager(
                backend: backend,
                gateway: h.gateway,
                scopes: () async => [],
              );
              await manager.refresh();
              await tester.pumpWidget(
                MaterialApp(
                  theme: settings.theme,
                  home: MediaQuery(
                    data: MediaQueryData(
                      size: const Size(360, 800),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Directionality(
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: PluginSettingsPage(
                        manager: manager,
                        plugin: manager.installed.single,
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(find.text('Example flag'), findsWidgets);
              await tester.ensureVisible(find.text('Example flag').first);
              await tester.tap(find.text('Example flag').first);
              await tester.pumpAndSettle();
              expect(backend.value, true);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
              manager.dispose();
              settings.dispose();
            },
          );
        }
      }
    }
  }
  testWidgets(
    'package details stay collapsed and retain copyable publisher identity',
    (tester) async {
      final settings = createSettingsController(TestDevice());
      await tester.runAsync(settings.load);
      final h = Harness();
      final manager = PluginManager(
        backend: SettingsBackend()..records = [configured()],
        gateway: h.gateway,
        scopes: () async => [],
      );
      await manager.refresh();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: settings.theme,
          home: PackageManagerPage(manager: manager, settings: settings),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Publisher fingerprint'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Package details'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Package details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Copy publisher fingerprint'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byTooltip('Copy publisher fingerprint'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy publisher fingerprint'));
      await tester.pumpAndSettle();
      expect(copied, manager.installed.single.publisher);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
      settings.dispose();
    },
  );
  testWidgets('package manager exposes data-only themes beside extensions', (
    tester,
  ) async {
    final settings = createSettingsController(TestDevice());
    await tester.runAsync(settings.load);
    final h = Harness();
    final manager = PluginManager(
      backend: SettingsBackend(),
      gateway: h.gateway,
      scopes: () async => [],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: settings.theme,
        home: PackageManagerPage(manager: manager, settings: settings),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Themes'));
    await tester.pumpAndSettle();
    expect(find.text('Theme packages'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
    settings.dispose();
  });
}
