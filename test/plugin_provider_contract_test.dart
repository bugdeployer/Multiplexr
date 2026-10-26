import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/experience/plugins/plugin_manager.dart';
import 'package:multiplexr/src/features/plugins/application/installed_metadata.dart';
import 'package:multiplexr/src/features/plugins/application/contribution_registry.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

import 'rx_plugin_gateway_test.dart' show Harness, Backend, record;

class ErrorBackend extends Backend {
  Object? error;
  @override
  Future<Object?> command(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    if (method == 'run') {
      return jsonEncode({'v': 1, 'id': 'invoke', 'error': error});
    }
    return super.command(method, args);
  }
}

void main() {
  test('gateway preserves only validated plugin errors', () async {
    final h = Harness(), backend = ErrorBackend();
    final gateway = PluginGateway(
      backend: backend,
      catalog: h.gateway.catalog,
      mutations: h.mutations,
      authorized: h.source.authorized,
      blocked: () => false,
      generation: () => 0,
      now: () => DateTime(2026),
    );
    for (final code in [
      'permission_denied',
      'resource_limit',
      'deadline_exceeded',
    ]) {
      backend.error = {'code': code};
      await expectLater(
        gateway.invoke(PluginRecord(record()), 'tool.inspect', {}, []),
        throwsA(isA<PluginDenied>().having((e) => e.code, 'code', code)),
      );
    }
    for (final error in [
      {'code': 'secret'},
      {'code': 'permission_denied', 'message': 'secret'},
      'secret',
    ]) {
      backend.error = error;
      await expectLater(
        gateway.invoke(PluginRecord(record()), 'tool.inspect', {}, []),
        throwsA(
          isA<PluginDenied>().having((e) => e.code, 'code', 'invalid_response'),
        ),
      );
    }
  });

  test(
    'JSON POST requires credentials grant, approved origin and bounded body',
    () async {
      final h = Harness();
      final plugin = PluginRecord(
        record(capabilities: ['http.request', 'credentials.use']),
      );
      h.backend.effect = (args) async => {'status': 200, 'body': '[]'};
      h.backend.execute = (args) async {
        final token = args['token'] as String;
        expect(
          (await h.call(token, 'http.post', {
            'url': 'https://example.com/search',
            'credential': 'apiKey',
            'body': '{}',
          }))['result'],
          {'status': 200, 'body': '[]'},
        );
        for (final params in [
          {'url': 'https://other.example/search', 'body': '{}'},
          {
            'url': 'https://example.com/search',
            'credential': 'arbitrary',
            'body': '{}',
          },
          {'url': 'https://example.com/search', 'body': 'x' * 8193},
          {
            'url': 'https://example.com/search',
            'body': '{}',
            'headers': {'X-API-Key': 'secret'},
          },
        ]) {
          expect(await h.call(token, 'http.post', params), contains('error'));
        }
        return null;
      };
      await h.gateway.invoke(plugin, 'tool.inspect', {}, []);
    },
  );

  test(
    'metadata adapter filters kinds and translates authentication failures',
    () async {
      final contribution = PluginContribution(PluginRecord(record()), {
        'id': 'org.example.tool:books',
        'family': 'metadata.provider',
        'title': 'Books',
        'handler': 'metadata.search',
        'kinds': ['ebook'],
      });
      final provider = InstalledMetadataProvider(
        contribution,
        (id, params, scopes, {selection = const []}) async =>
            throw const PluginDenied('permission_denied'),
        [],
      );
      expect(provider.entities, {MetadataEntityType.ebook});
      await expectLater(
        provider.search(
          const MetadataSearchRequest(
            provider: 'org.example.tool:books',
            entity: MetadataEntityType.ebook,
            title: 'Moon',
            collectionId: 'books',
          ),
        ),
        throwsA(
          isA<MetadataFailure>().having(
            (e) => e.kind,
            'kind',
            MetadataFailureKind.authentication,
          ),
        ),
      );
      await expectLater(
        provider.search(
          const MetadataSearchRequest(
            provider: 'org.example.tool:books',
            entity: MetadataEntityType.movie,
            title: 'Moon',
            collectionId: 'movies',
          ),
        ),
        throwsA(
          isA<MetadataFailure>().having(
            (e) => e.kind,
            'kind',
            MetadataFailureKind.unavailable,
          ),
        ),
      );
    },
  );
}
