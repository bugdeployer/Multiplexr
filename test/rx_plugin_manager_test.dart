import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager_page.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';

import 'rx_plugin_gateway_test.dart' show Harness, Backend, record;

class RefreshBackend extends Backend {
  final reads = <Completer<Object?>>[];
  @override
  Future<Object?> command(
    String method, [
    Map<String, Object?> args = const {},
  ]) {
    if (method != 'list') return super.command(method, args);
    final result = Completer<Object?>();
    reads.add(result);
    return result.future;
  }
}

void main() {
  test('out-of-order inventory cannot re-enable stale contributions; read failure unmounts', () async {
    final h = Harness(), backend = RefreshBackend();
    final manager = PluginManager(
      backend: backend,
      gateway: h.gateway,
      scopes: () async => [],
    );
    final first = manager.refresh(), second = manager.refresh();
    backend.reads[1].complete([
      {...record(), 'revision': 2, 'enabled': false},
    ]);
    await second;
    backend.reads[0].complete([record()]);
    await first;
    expect(manager.installed.single.enabled, false);
    expect(manager.installed.single.revision, 2);
    final third = manager.refresh();
    backend.reads[2].completeError(StateError('unavailable'));
    await third;
    expect(manager.installed, isEmpty);
    expect(manager.registry.all, isEmpty);
    expect(manager.error, isNotNull);
    manager.dispose();
  });
  testWidgets(
    'manager disables installed code and confirms destructive cleanup',
    (tester) async {
      final h = Harness();
      final manager = PluginManager(
        backend: h.backend,
        gateway: h.gateway,
        scopes: () async => [],
      );
      await tester.pumpWidget(
        MaterialApp(home: PluginManagerPage(manager: manager)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tool'), findsOneWidget);
      expect(find.text('Permissions'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove plugin?'), findsOneWidget);
      expect(
        find.textContaining('Delete settings and private data'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(manager.installed.single.id, record()['id']);
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
    },
  );
  testWidgets('empty plugin inventory retains install and recovery controls', (
    tester,
  ) async {
    final h = Harness();
    h.backend.records = [];
    final manager = PluginManager(
      backend: h.backend,
      gateway: h.gateway,
      scopes: () async => [],
    );
    await tester.pumpWidget(
      MaterialApp(home: PluginManagerPage(manager: manager)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No plugins installed'), findsOneWidget);
    expect(find.text('Install file'), findsOneWidget);
    expect(find.byTooltip('Disable all plugins'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
  });
}
