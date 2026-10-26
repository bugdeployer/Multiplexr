import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:app_shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/bootstrap/settings_assembly.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager_page.dart';

import 'widget_test.dart' show TestDevice;
import 'rx_plugin_gateway_test.dart' show Harness, record;

void main() {
  setUpAll(() async {
    await AppThemeDefinition.loadBundled();
    final config = File('.dart_tool/package_config.json');
    final packages = jsonDecode(config.readAsStringSync())['packages'] as List;
    final flutter = config.absolute.uri.resolve(
      packages.singleWhere((p) => p['name'] == 'flutter')['rootUri'] as String,
    );
    final roboto = FontLoader('Roboto');
    roboto.addFont(
      File.fromUri(
        Uri.parse('${flutter.toString()}/').resolve(
          '../../bin/cache/artifacts/material_fonts/roboto-regular.ttf',
        ),
      ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
    await roboto.load();
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in fonts) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  for (final retro in [false, true]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('extension manager phone retro=$retro scale=$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final settings = createSettingsController(TestDevice());
        await settings.load();
        await settings.interfaceStyle(retro);
        final h = Harness();
        h.backend.records = [
          {
            ...record(),
            'id': 'com.bugdeployer.tmdb',
            'name': 'TMDB metadata',
            'version': '0.2.0',
            'contributions': [
              {
                'id': 'com.bugdeployer.tmdb:metadata',
                'family': 'metadata.provider',
                'title': 'TMDB',
                'handler': 'metadata.search',
                'kinds': ['movie', 'television'],
              },
            ],
            'permissions': ['metadata.provide'],
            'enabled': true,
          },
          {...record(), 'name': 'Open Library metadata', 'enabled': false},
        ];
        final manager = PluginManager(
          backend: h.backend,
          gateway: h.gateway,
          scopes: () async => [],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: settings.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: PluginManagerPage(manager: manager),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/plugins-installed-$retro-$scale.png'),
        );
        await tester.tap(find.text('Browse'));
        await tester.pumpAndSettle();
        expect(find.text('TMDB'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile('goldens/plugins-browse-$retro-$scale.png'),
        );
        await tester.enterText(find.byType(TextField), 'Open Library');
        await tester.pumpAndSettle();
        expect(find.text('TMDB'), findsNothing);
        expect(
          find.text('Open Library', findRichText: false).hitTestable(),
          findsWidgets,
        );
        await tester.pumpWidget(const SizedBox());
        manager.dispose();
        settings.dispose();
      }, tags: 'golden');
    }
  }
}
