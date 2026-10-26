import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager_page.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';
import 'package:multiplexr/src/experience/plugins/plugin_contribution_page.dart';
import 'package:multiplexr/src/features/catalog/application/extension_catalog.dart';

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
  testWidgets(
    'provider test lookup selects a granted collection without mutating it',
    (tester) async {
      final h = Harness();
      h.backend.records = [
        {
          ...record(capabilities: ['metadata.provide']),
          'contributions': [
            {
              'id': 'org.example.tool:books',
              'family': 'metadata.provider',
              'title': 'Books provider',
              'handler': 'metadata.search',
              'kinds': ['ebook'],
            },
          ],
        },
      ];
      h.backend.execute = (_) async => {
        'items': [
          {'id': 'org.example.tool:dune', 'title': 'Dune'},
        ],
        'nextCursor': null,
      };
      final manager = PluginManager(
        backend: h.backend,
        gateway: h.gateway,
        scopes: () async => [
          const PluginScope('private-id', ExtensionMedia.ebook, 'Books'),
        ],
      );
      await tester.pumpWidget(
        PluginPlatformScope(
          manager: manager,
          child: MaterialApp(home: PluginManagerPage(manager: manager)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Test lookup'));
      await tester.tap(find.text('Test lookup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Books'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Dune');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      await tester.tap(find.text('Dune'));
      await tester.pumpAndSettle();
      expect(h.mutations.commits, 0);
      await tester.pumpWidget(const SizedBox());
      manager.dispose();
    },
  );
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
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      expect(find.text('Permissions'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove'));
      await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('Extension options'));
    await tester.pumpAndSettle();
    expect(find.text('Install file'), findsOneWidget);
    expect(find.byTooltip('Disable all plugins'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    manager.dispose();
  });
}
