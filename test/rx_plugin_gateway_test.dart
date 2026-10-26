import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/plugins/application/plugin_platform.dart';
import 'package:multiplexr/src/features/catalog/application/extension_catalog.dart';

class Catalog implements ExtensionCatalogSource {
  bool allowed = true;
  Completer<void>? gate;
  @override
  bool authorized(String collection, ExtensionMedia kind) =>
      allowed && collection == 'private-id';
  @override
  Future<List<ExtensionTitle>> titles(
    String collection,
    ExtensionMedia kind,
  ) async {
    await gate?.future;
    return [
      ExtensionTitle(
        id: 'internal-title',
        collection: collection,
        kind: kind,
        title: 'Allowed title',
        revision: 'revision-1',
      ),
    ];
  }
}

class Mutations implements PluginMutations {
  int commits = 0;
  @override
  Future<void> replaceTags(
    PluginRecord plugin,
    ExtensionTitle title,
    List<String> tags,
    String key,
    void Function() access,
  ) async {
    access();
    commits++;
  }
}

class Backend implements PluginBackend {
  late Future<String> Function(String, String) dispatch;
  Future<Object?> Function(Map<String, Object?> args)? execute;
  List<Map<String, dynamic>> records = [];
  Future<Object?> Function(Map<String, Object?>)? effect;
  @override
  void listen(
    Future<String> Function(String, String) call,
    void Function() changed,
  ) {
    dispatch = call;
  }

  @override
  Future<Object?> command(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    if (method == 'run') {
      return jsonEncode({
        'v': 1,
        'id': 'invoke',
        'result': await execute!(args),
      });
    }
    if (method == 'effect') return effect == null ? true : effect!(args);
    if (method == 'list') return records;
    return null;
  }
}

Map<String, dynamic> record({
  List<String> capabilities = const [
    'runtime.ping',
    'catalog.read',
    'catalog.propose',
  ],
  int revision = 1,
}) => {
  'id': 'org.example.tool',
  'name': 'Tool',
  'version': '1.0.0',
  'publisher': 'f' * 64,
  'enabled': true,
  'revision': revision,
  'permissions': capabilities,
  'origins': ['https://example.com'],
  'collections': ['private-id'],
  'handlers': ['tool.inspect'],
};

class Harness {
  final backend = Backend(), source = Catalog(), mutations = Mutations();
  bool blocked = false;
  int generation = 0;
  DateTime now = DateTime(2026);
  late final gateway = PluginGateway(
    backend: backend,
    catalog: ExtensionCatalogQueries(source),
    mutations: mutations,
    authorized: source.authorized,
    blocked: () => blocked,
    generation: () => generation,
    now: () => now,
  );
  Harness() {
    backend.listen(gateway.dispatch, () {});
    backend.records = [record()];
  }
  Future<Map<String, dynamic>> call(
    String token,
    String method,
    Map<String, dynamic> params,
  ) async => jsonDecode(
    await gateway.dispatch(
      token,
      jsonEncode({'v': 1, 'id': 'request', 'method': method, 'params': params}),
    ),
  ) as Map<String, dynamic>;
  Future<Object?> run() => gateway.invoke(
    PluginRecord(record()),
    'tool.inspect',
    const {},
    [const PluginScope('private-id', ExtensionMedia.ebook, 'Books')],
  );
}

void main() {
  test('settings resolve opaque scopes and hide internal addresses', () async {
    final h = Harness();
    final plugin = PluginRecord(
      record(capabilities: ['settings.read', 'settings.write']),
    );
    h.backend.execute = (args) async {
      final token = args['token'] as String;
      final input = jsonDecode(args['input'] as String);
      final handle = input['params']['scopes'][0]['handle'];
      h.backend.effect = (effect) async {
        if (effect['method'] == 'authorize') return true;
        final params = effect['params'] as Map;
        expect((params['lineage'] as List)[1], {
          'scope': 'collection',
          'collection': 'private-id',
        });
        return {'value': true, 'sourceIndex': 1, 'revision': 2};
      };
      final result = await h.call(token, 'settings.effective', {
        'id': 'org.example.tool:flag',
        'lineage': [
          {'scope': 'app'},
          {'scope': 'collection', 'handle': handle},
        ],
      });
      expect(result['result']['source'], {
        'scope': 'collection',
        'handle': handle,
      });
      expect(jsonEncode(result), isNot(contains('private-id')));
      final denied = await h.call(token, 'settings.propose', {
        'id': 'org.example.tool:flag',
        'address': {'scope': 'collection', 'collection': 'private-id'},
        'value': true,
        'expectedRevision': 2,
      });
      expect(denied, contains('error'));
      return null;
    };
    await h.gateway.invoke(plugin, 'tool.inspect', {}, [
      const PluginScope('private-id', ExtensionMedia.ebook, 'Books'),
    ]);
  });

  test(
    'host handles reveal allowed titles without internal IDs or raw sources',
    () async {
      final h = Harness();
      h.backend.execute = (args) async {
        final input = jsonDecode(args['input'] as String);
        final scope = input['params']['scopes'][0];
        final result = await h.call(args['token'] as String, 'catalog.titles', {
          'handle': scope['handle'],
        });
        final encoded = jsonEncode(result);
        expect(encoded, contains('Allowed title'));
        expect(encoded, isNot(contains('private-id')));
        expect(encoded, isNot(contains('internal-title')));
        return result;
      };
      await h.run();
    },
  );
  test('unminted, foreign and expired handles are denied', () async {
    final h = Harness();
    expect(
      (await h.call('forged', 'catalog.titles', {
        'handle': 'forged',
      }))['error']['code'],
      'permission_denied',
    );
    h.backend.execute = (args) async {
      final result = await h.call(args['token'] as String, 'catalog.titles', {
        'handle': 'forged',
      });
      expect(result['error']['code'], 'permission_denied');
      h.now = h.now.add(const Duration(minutes: 1));
      final expired = await h.call(args['token'] as String, 'runtime.ping', {});
      expect(expired['error']['code'], 'permission_denied');
      return null;
    };
    await expectLater(h.run(), throwsA(isA<PluginDenied>()));
  });
  test('lock during a query suppresses late titles and revocation drops the invocation', () async {
    final h = Harness();
    h.source.gate = Completer<void>();
    h.backend.execute = (args) async {
      final input = jsonDecode(args['input'] as String);
      final handle = input['params']['scopes'][0]['handle'];
      final future = h.call(args['token'] as String, 'catalog.titles', {
        'handle': handle,
      });
      await Future<void>.delayed(Duration.zero);
      h.source.allowed = false;
      h.gateway.revoke();
      h.source.gate!.complete();
      final response = await future;
      expect(response.containsKey('result'), false);
      return response;
    };
    await expectLater(h.run(), throwsA(isA<PluginDenied>()));
  });
  test('capability denial, credential origin checks and reserved methods fail closed', () async {
    final h = Harness();
    h.backend.execute = (args) async {
      final token = args['token'] as String;
      for (final method in [
        'http.get',
        'storage.write',
        'catalog.confirm',
        'security.unlock',
      ]) {
        final result = await h.call(token, method, {
          'url': 'https://example.com',
        });
        expect(result.containsKey('error'), true);
      }
      return null;
    };
    await h.run();
  });
  test('scripts can propose but only host confirmation commits, and replay cannot commit twice', () async {
    final h = Harness();
    String? proposal;
    h.backend.execute = (args) async {
      final input = jsonDecode(args['input'] as String);
      final token = args['token'] as String;
      final page = await h.call(token, 'catalog.titles', {
        'handle': input['params']['scopes'][0]['handle'],
      });
      final title = page['result']['items'][0];
      final proposed = await h.call(token, 'catalog.propose', {
        'handle': title['handle'],
        'revision': title['revision'],
        'operation': 'replaceTags',
        'tags': ['Reviewed'],
        'idempotencyKey': 'safe',
      });
      proposal = proposed['result']['proposal'] as String;
      expect(h.mutations.commits, 0);
      return null;
    };
    await h.run();
    await h.gateway.confirm(proposal!);
    expect(h.mutations.commits, 1);
    await expectLater(
      h.gateway.confirm(proposal!),
      throwsA(isA<PluginDenied>()),
    );
    expect(h.mutations.commits, 1);
  });
  test(
    'permission revision changes and maintenance invalidate pending proposals',
    () async {
      for (final restore in [false, true]) {
        final h = Harness();
        String? proposal;
        h.backend.execute = (args) async {
          final input = jsonDecode(args['input'] as String),
              token = args['token'] as String;
          final page = await h.call(token, 'catalog.titles', {
            'handle': input['params']['scopes'][0]['handle'],
          });
          final title = page['result']['items'][0];
          proposal =
              (await h.call(token, 'catalog.propose', {
                    'handle': title['handle'],
                    'revision': title['revision'],
                    'operation': 'replaceTags',
                    'tags': ['x'],
                    'idempotencyKey': 'x',
                  }))['result']['proposal']
                  as String;
          return null;
        };
        await h.run();
        if (restore) {
          h.generation++;
        } else {
          h.backend.records = [record(revision: 2)];
        }
        await expectLater(
          h.gateway.confirm(proposal!),
          throwsA(isA<PluginDenied>()),
        );
        expect(h.mutations.commits, 0);
      }
    },
  );
}
