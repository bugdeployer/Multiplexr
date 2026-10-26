import 'package:multiplexr/src/features/plugins/application/contribution_registry.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';
import 'package:multiplexr/src/features/plugins/application/plugin_scheduler.dart';
import 'package:multiplexr/src/features/plugins/application/installed_metadata.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';
import 'package:multiplexr/src/core/application/mutations.dart';
import 'package:multiplexr/src/features/catalog/application/extension_catalog.dart';

import 'rx_plugin_gateway_test.dart' show Harness, record;

Map<String, dynamic> extension(String family, String capability) => {
  ...record(capabilities: [capability]),
  'contributions': [
    {
      'id': 'org.example.tool:extension',
      'title': 'Extension',
      'family': family,
      'handler': 'tool.inspect',
    },
  ],
};
void main() {
  test(
    'concurrent and nested commands keep asynchronous origin ownership',
    () async {
      final h = Harness();
      final manager = PluginManager(
        backend: h.backend,
        gateway: h.gateway,
        scopes: () async => [],
      );
      final a = Completer<void>(), b = Completer<void>();
      final seen = <String?>[];
      final first = manager.withOrigin('org.example.first', () async {
        await a.future;
        seen.add(manager.commandOrigin);
        await manager.withOrigin('org.example.nested', () async {
          await Future<void>.delayed(Duration.zero);
          seen.add(manager.commandOrigin);
        });
        seen.add(manager.commandOrigin);
      });
      final second = manager.withOrigin('org.example.second', () async {
        await b.future;
        seen.add(manager.commandOrigin);
      });
      a.complete();
      await first;
      b.complete();
      await second;
      expect(seen, [
        'org.example.first',
        'org.example.nested',
        'org.example.first',
        'org.example.second',
      ]);
      expect(manager.commandOrigin, isNull);
      manager.dispose();
    },
  );
  test(
    'debounced changes preserve every origin and collection batch',
    () async {
      final h = Harness();
      final row = extension('event.handler', 'events.subscribe');
      row['contributions'] = [
        <String, dynamic>{
          ...(row['contributions'] as List).single as Map<String, dynamic>,
          'events': ['org.multiplexr:library.changed'],
        },
      ];
      h.backend.records = [row];
      final origins = <String>[];
      h.backend.execute = (args) async {
        final input = jsonDecode(args['input'] as String) as Map;
        origins.add(
          ((input['params'] as Map)['data'] as Map)['origin'] as String,
        );
        return {'acknowledged': true};
      };
      final manager = PluginManager(
        backend: h.backend,
        gateway: h.gateway,
        scopes: () async => [
          const PluginScope('private-id', ExtensionMedia.ebook, 'Books'),
        ],
      );
      await manager.refresh();
      manager.signalCatalogChange({'private-id'}, origin: 'org.example.first');
      manager.signalCatalogChange({'ungranted'}, origin: 'org.example.first');
      manager.signalCatalogChange({'private-id'}, origin: 'org.example.second');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(origins, ['org.example.first', 'org.example.second']);
      manager.dispose();
    },
  );
  test('every registration family unmounts on grant loss, replacement, disable and removal', () {
    for (final entry in ContributionRegistry.capabilities.entries) {
      final registry = ContributionRegistry();
      final row = extension(entry.key, entry.value);
      registry.replace([PluginRecord(row)]);
      expect(registry.family(entry.key), hasLength(1));
      final old = registry.all.single;
      registry.replace([
        PluginRecord({...row, 'revision': 2}),
      ]);
      expect(registry.current(old), false);
      registry.replace([
        PluginRecord({...row, 'permissions': <String>[]}),
      ]);
      expect(registry.all, isEmpty);
      registry.replace([
        PluginRecord({...row, 'enabled': false}),
      ]);
      expect(registry.all, isEmpty);
      registry.replace([]);
      expect(registry.all, isEmpty);
    }
  });

  test('scheduler serializes interpreters and prioritizes user work over automation', () async {
    final queue = PluginScheduler(() => DateTime(2026));
    final gate = Completer<void>();
    final order = <String>[];
    final first = queue.run('a', () async {
      order.add('first');
      await gate.future;
      return null;
    });
    final background = queue.run('a', () async {
      order.add('automation');
      return null;
    }, background: true);
    final user = queue.run('b', () async {
      order.add('user');
      return null;
    });
    gate.complete();
    await Future.wait([first, background, user]);
    expect(order, ['first', 'user', 'automation']);
  });
  test(
    'revocation cancels queued work before it can enter the interpreter',
    () async {
      final queue = PluginScheduler(() => DateTime(2026));
      final gate = Completer<void>();
      var runs = 0;
      final first = queue.run('a', () async {
        await gate.future;
        return null;
      });
      final pending = queue.run('b', () async {
        runs++;
        return null;
      });
      final rejected = expectLater(pending, throwsA(isA<PluginDenied>()));
      queue.revoke('b');
      gate.complete();
      await first;
      await rejected;
      expect(runs, 0);
    },
  );
  test('installed metadata carries bibliographic fields and bound implementation identity', () async {
    final h = Harness();
    h.backend.records = [extension('metadata.provider', 'metadata.provide')];
    final manager = PluginManager(
      backend: h.backend,
      gateway: h.gateway,
      scopes: () async => [
        const PluginScope('private-id', ExtensionMedia.ebook, 'Books'),
      ],
    );
    h.backend.execute = (args) async {
      final input = jsonDecode(args['input'] as String);
      expect(input['params'], isNot(contains('scopes')));
      expect(input['params']['kind'], 'ebook');
      return {
        'items': [
          {
            'id': 'org.example.tool:book',
            'title': 'Example',
            'authors': ['Author'],
            'fields': {
              'language': 'en',
              'description': 'A publication',
              'publisher': 'Example Press',
            },
          },
        ],
        'nextCursor': 'next',
      };
    };
    await manager.refresh();
    final provider = InstalledMetadataProvider(
      manager.registry.all.single,
      manager.invokeContribution,
      [const PluginScope('private-id', ExtensionMedia.ebook, 'Books')],
    );
    final result = await provider.search(
      const MetadataSearchRequest(
        provider: 'org.example.tool:extension',
        entity: MetadataEntityType.ebook,
        title: 'Example',
      ),
    );
    expect(result.nextCursor, 'next');
    expect(result.candidates.single.values['description'], 'A publication');
    expect(result.candidates.single.implementation!.collection, 'private-id');
    expect(result.candidates.single.provenance, startsWith('plugin:'));
    expect(
      MetadataCandidate.fromJson(result.candidates.single.toJson()).values,
      result.candidates.single.values,
    );
    final workflow = MetadataWorkflow([
      provider,
    ], mutations: const OwnerApplicationMutations());
    final epoch = workflow.implementationEpoch;
    expect(epoch, hasLength(64));
    manager.dispose();
  });
  test('tool results use minted selections and reject out-of-selection proposals atomically', () async {
    final h = Harness();
    h.backend.records = [extension('library.tool', 'library.tools')];
    final manager = PluginManager(
      backend: h.backend,
      gateway: h.gateway,
      scopes: () async => [],
    );
    await manager.refresh();
    const selected = ExtensionTitle(
      id: 'internal-title',
      collection: 'private-id',
      kind: ExtensionMedia.ebook,
      title: 'Book',
      revision: 'revision-1',
    );
    h.backend.execute = (args) async {
      final input = jsonDecode(args['input'] as String);
      final item = input['params']['selection'][0];
      expect(item['id'], isNot('internal-title'));
      return {
        'proposals': [
          {
            'title': item['id'],
            'expectedRevision': item['revision'],
            'changes': {'description': 'Valid'},
          },
          {
            'title': 'forged',
            'expectedRevision': 'revision-1',
            'changes': {'title': 'Invalid'},
          },
        ],
      };
    };
    await expectLater(
      manager.invokeContribution(
        'org.example.tool:extension',
        {},
        [const PluginScope('private-id', ExtensionMedia.ebook, 'Books')],
        selection: [selected],
      ),
      throwsA(isA<PluginDenied>()),
    );
    expect(manager.edits, isEmpty);
    manager.dispose();
  });
  test('events filter origins, redact scopes and stop at the bounded invocation budget', () async {
    final h = Harness();
    h.backend.records = [extension('event.handler', 'events.subscribe')];
    var calls = 0;
    h.backend.execute = (args) async {
      calls++;
      final input = jsonDecode(args['input'] as String);
      expect(jsonEncode(input), isNot(contains('private-id')));
      return {'acknowledged': true};
    };
    final manager = PluginManager(
      backend: h.backend,
      gateway: h.gateway,
      scopes: () async => [
        const PluginScope('private-id', ExtensionMedia.ebook, 'Books'),
      ],
    );
    await manager.refresh();
    await Future<void>.delayed(Duration.zero);
    final before = calls;
    await manager.dispatchEvent(
      'org.multiplexr:application.ready',
      origin: 'org.example.tool',
    );
    expect(calls, before);
    for (var i = 0; i < 8; i++) {
      await manager.dispatchEvent('org.multiplexr:application.ready');
    }
    expect(calls, lessThanOrEqualTo(4));
    h.backend.records = [
      {...h.backend.records.single, 'enabled': false, 'revision': 2},
    ];
    await manager.refresh();
    await manager.dispatchEvent('org.multiplexr:application.ready');
    expect(calls, lessThanOrEqualTo(4));
    manager.dispose();
  });
}
