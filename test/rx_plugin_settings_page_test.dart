import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';
import 'package:multiplexr/src/experience/plugins/plugin_settings_page.dart';
import 'package:multiplexr/src/features/plugins/application/contribution_registry.dart';
import 'package:multiplexr/src/features/plugins/application/contribution_validation.dart';

import 'rx_plugin_gateway_test.dart' show Harness, Backend, record;

class SettingsBackend extends Backend {
  bool value = false;
  int revision = 0;
  @override
  Future<Object?> command(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    if (method != 'settingsHost') {
      return super.command(method, args);
    }
    final params = args['params'] as Map;
    if (args['method'] == 'settings.effective') {
      return {
        'value': value,
        'sourceIndex': revision == 0 ? null : 0,
        'revision': revision,
      };
    }
    if (params['expectedRevision'] != revision) {
      throw StateError('Conflict');
    }
    value = params['value'] == true;
    revision++;
    return {'revision': revision};
  }
}

Map<String, dynamic> configured() => {
  ...record(capabilities: ['settings.read', 'settings.write', 'ui.present']),
  'contributions': [
    {
      'id': 'org.example.tool:preferences',
      'family': 'settings.section',
      'title': 'Tool preferences',
      'fields': [
        {
          'id': 'org.example.tool:flag',
          'label': 'Example flag',
          'accessibleLabel': 'Example flag',
          'type': 'boolean',
          'default': false,
          'scopes': ['app', 'collection'],
        },
      ],
    },
    {
      'id': 'org.example.tool:destination',
      'family': 'ui.destination',
      'title': 'Tool destination',
      'handler': 'tool.inspect',
    },
  ],
};
void main() {
  test('live registry excludes revoked and ungranted contributions', () {
    final registry = ContributionRegistry();
    final row = configured();
    registry.replace([PluginRecord(row)]);
    expect(registry.family('settings.section'), hasLength(1));
    expect(registry.family('ui.destination'), hasLength(1));
    final old = registry.require('org.example.tool:destination');
    registry.replace([
      PluginRecord({...row, 'revision': 2}),
    ]);
    expect(registry.current(old), false);
    registry.replace([
      PluginRecord({...row, 'enabled': false}),
    ]);
    expect(registry.all, isEmpty);
    registry.replace([
      PluginRecord({...row, 'permissions': <String>[]}),
    ]);
    expect(registry.all, isEmpty);
  });
  test(
    'host rejects malformed UI, exports and foreign provider identities',
    () {
      expect(
        () => ContributionValidation.result('ui.section', {
          'kind': 'action',
          'label': 'Unlock',
          'action': 'host:unlock',
        }, 'org.example.tool'),
        throwsA(isA<PluginDenied>()),
      );
      expect(
        () => ContributionValidation.result('export.handler', {
          'name': '../private',
          'mime': 'text/plain',
          'text': 'x',
        }, 'org.example.tool'),
        throwsA(isA<PluginDenied>()),
      );
      expect(
        () => ContributionValidation.result('metadata.provider', {
          'items': [
            {'id': 'org.foreign:record', 'title': 'Wrong owner'},
          ],
          'nextCursor': null,
        }, 'org.example.tool'),
        throwsA(isA<PluginDenied>()),
      );
    },
  );
  testWidgets(
    'contributed settings remain usable in narrow RTL with large text',
    (tester) async {
      tester.view.physicalSize = const Size(300, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: PluginSettingsPage(
            manager: manager,
            plugin: manager.installed.single,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(backend.value, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
    },
  );
  testWidgets('host settings persist typed edits and unmount on disable', (
    tester,
  ) async {
    final h = Harness();
    final backend = SettingsBackend()..records = [configured()];
    var scopeReads = 0;
    final manager = PluginManager(
      backend: backend,
      gateway: h.gateway,
      scopes: () async {
        scopeReads++;
        return [];
      },
    );
    await manager.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: PluginSettingsPage(
          manager: manager,
          plugin: manager.installed.single,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Example flag'), findsWidgets);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(backend.value, true);
    expect(backend.revision, 1);
    // One scope-options query plus pre/post authority checks for read, write, reread.
    expect(scopeReads, 7);
    backend.records = [
      {...configured(), 'enabled': false, 'revision': 2},
    ];
    await manager.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('Plugin access ended'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
  });
}
