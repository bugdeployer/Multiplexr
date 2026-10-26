import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/features/plugins/application/plugin_platform.dart';
import 'package:multiplexr/src/features/catalog/application/extension_catalog.dart';

import 'rx_plugin_gateway_test.dart' show Harness, Mutations, record;

class Fields extends Mutations implements PluginFieldMutations {
  Map<String, dynamic> values = {
    'org.example.tool:rating': 2,
    'org.other:private': 8,
  };
  @override
  Future<Map<String, dynamic>> readFields(ExtensionTitle title) async => values;
  @override
  Future<void> mergeFields(
    PluginRecord plugin,
    ExtensionTitle title,
    Map<String, dynamic> fields,
    String key,
    void Function() access,
  ) async {
    access();
    values = {...values, ...fields};
    commits++;
  }
}

void main() {
  test('extension fields stay namespaced, require confirmation, and stop on revoke', () async {
    final h = Harness(), fields = Fields();
    final gateway = PluginGateway(
      backend: h.backend,
      catalog: h.gateway.catalog,
      mutations: fields,
      authorized: h.source.authorized,
      blocked: () => h.blocked,
      generation: () => h.generation,
      now: () => h.now,
    );
    final plugin = PluginRecord(
      record(capabilities: ['catalog.read', 'catalog.propose']),
    );
    h.backend.records = [
      record(capabilities: ['catalog.read', 'catalog.propose']),
    ];
    Future<Map> call(String token, String method, Map params) async =>
        jsonDecode(
          await gateway.dispatch(
            token,
            jsonEncode({
              'v': 1,
              'id': 'request',
              'method': method,
              'params': params,
            }),
          ),
        ) as Map;
    h.backend.execute = (args) async {
      final token = args['token'] as String;
      final scope = jsonDecode(
        args['input'] as String,
      )['params']['scopes'][0]['handle'];
      final page = await call(token, 'catalog.titles', {'handle': scope});
      final title = page['result']['items'][0];
      final read = await call(token, 'catalog.fields', {
        'handle': title['handle'],
      });
      expect(read['result'], {
        'org.example.tool:rating': fields.values['org.example.tool:rating'],
      });
      final wrong = await call(token, 'catalog.propose', {
        'operation': 'mergeFields',
        'handle': title['handle'],
        'revision': title['revision'],
        'fields': {'org.other:private': 1},
        'idempotencyKey': 'bad',
      });
      expect(wrong, contains('error'));
      final proposal = await call(token, 'catalog.propose', {
        'operation': 'mergeFields',
        'handle': title['handle'],
        'revision': title['revision'],
        'fields': {'org.example.tool:rating': 5},
        'idempotencyKey': 'rating',
      });
      expect(proposal['result']['status'], 'awaitingConfirmation');
      return null;
    };
    Future<void> run() async {
      await gateway.invoke(plugin, 'tool.inspect', {}, [
        const PluginScope('private-id', ExtensionMedia.ebook, 'Books'),
      ]);
    }

    await run();
    expect(fields.commits, 0);
    await gateway.confirm(gateway.proposals.single.id);
    expect(fields.values, {
      'org.example.tool:rating': 5,
      'org.other:private': 8,
    });
    await run();
    h.source.allowed = false;
    await expectLater(
      gateway.confirm(gateway.proposals.single.id),
      throwsA(isA<PluginDenied>()),
    );
    expect(fields.commits, 1);
    gateway.revoke();
    expect(gateway.proposals, isEmpty);
  });
}
