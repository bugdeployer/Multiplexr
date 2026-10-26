import 'plugin_failure.dart';
export 'plugin_failure.dart';
import 'plugin_scheduler.dart';

import 'dart:convert';
import 'dart:math';

import '../../catalog/application/extension_catalog.dart';

abstract interface class PluginBackend {
  Future<Object?> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]);
  void listen(
    Future<String> Function(String token, String request) call,
    void Function() changed,
  );
}

class PluginRecord {
  PluginRecord(Map<String, dynamic> value)
    : contributions = List.unmodifiable(
        (value['contributions'] as List? ?? const []).map(
          (v) => Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(v as Map),
          ),
        ),
      ),
      id = value['id'] as String,
      name = value['name'] as String,
      version = value['version'] as String,
      instance = value['instance'] as String? ?? '',
      publisher = value['publisher'] as String,
      enabled = value['enabled'] == true,
      revision = value['revision'] as int,
      privateBytes = value['privateBytes'] as int? ?? 0,
      requestedPermissions = Set.unmodifiable(
        (value['requestedPermissions'] as List? ?? value['permissions'] as List)
            .cast<String>(),
      ),
      requestedOrigins = Set.unmodifiable(
        (value['requestedOrigins'] as List? ?? value['origins'] as List)
            .cast<String>(),
      ),
      handlers = List.unmodifiable(
        (value['handlers'] as List? ?? []).cast<String>(),
      ),
      error = value['error'] as String? ?? '',
      rollback = value['rollback'] == true,
      permissions = Set.unmodifiable(
        (value['permissions'] as List).cast<String>(),
      ),
      origins = Set.unmodifiable((value['origins'] as List).cast<String>()),
      collections = Set.unmodifiable(
        (value['collections'] as List).cast<String>(),
      );
  final List<Map<String, dynamic>> contributions;
  final String id, name, version, publisher, error, instance;
  final bool enabled, rollback;
  final List<String> handlers;
  final int revision, privateBytes;
  final Set<String> permissions,
      origins,
      collections,
      requestedPermissions,
      requestedOrigins;
}

class PluginScope {
  const PluginScope(this.collection, this.kind, this.label, {this.group});
  final String? group;
  final String collection, label;
  final ExtensionMedia kind;
}

class PluginInvocation {
  PluginInvocation(this.plugin, this.expires, this.generation);
  final PluginRecord plugin;
  final DateTime expires;
  final int generation;
  final scopes = <String, PluginScope>{};
  final titles = <String, ExtensionTitle>{};
  int calls = 0;
}

class PluginProposal {
  PluginProposal(
    this.id,
    this.plugin,
    this.title,
    this.tags,
    this.key,
    this.generation, {
    this.fields,
  });
  final Map<String, dynamic>? fields;
  final String id, key;
  final PluginRecord plugin;
  final ExtensionTitle title;
  final List<String> tags;
  final int generation;
}

abstract interface class PluginMutations {
  Future<void> replaceTags(
    PluginRecord plugin,
    ExtensionTitle expected,
    List<String> tags,
    String idempotencyKey,
    void Function() checkAccess,
  );
}

abstract interface class PluginFieldMutations {
  Future<Map<String, dynamic>> readFields(ExtensionTitle title);
  Future<void> mergeFields(
    PluginRecord plugin,
    ExtensionTitle expected,
    Map<String, dynamic> fields,
    String key,
    void Function() checkAccess,
  );
}

/// Every request is checked against a host-minted invocation, not plugin params.
/// Only read handles and proposals cross the script boundary; confirmation is a
/// separate host UI action and cannot be invoked through this dispatcher.
class PluginGateway {
  PluginGateway({
    required this.backend,
    required this.catalog,
    required this.mutations,
    required this.authorized,
    required this.blocked,
    required this.generation,
    required this.now,
  });
  final PluginBackend backend;
  final ExtensionCatalogQueries catalog;
  final PluginMutations mutations;
  final bool Function(String, ExtensionMedia) authorized;
  final bool Function() blocked;
  final int Function() generation;
  final DateTime Function() now;
  late final _scheduler = PluginScheduler(now);
  final _random = Random.secure();
  final _invocations = <String, PluginInvocation>{};
  final _proposals = <String, PluginProposal>{};
  List<PluginProposal> get proposals => List.unmodifiable(_proposals.values);
  String _token() => List.generate(
    32,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void revoke([String? plugin]) {
    _scheduler.revoke(plugin);
    _invocations.removeWhere((_, v) => plugin == null || v.plugin.id == plugin);
    _proposals.removeWhere((_, v) => plugin == null || v.plugin.id == plugin);
  }

  void _access(PluginInvocation invocation, [String? permission]) {
    if (blocked() ||
        generation() != invocation.generation ||
        !now().isBefore(invocation.expires) ||
        permission != null &&
            !invocation.plugin.permissions.contains(permission)) {
      throw const PluginDenied();
    }
  }

  Future<Object?> invoke(
    PluginRecord plugin,
    String method,
    Map<String, Object?> params,
    List<PluginScope> scopes, {
    bool includeScopes = true,
    bool includeSelection = false,
    List<ExtensionTitle> selection = const [],
    String? scopeParameter,
    bool titleParameter = false,
    bool uiScope = false,
    void Function(Map<String, ExtensionTitle>)? bindSelection,
    bool background = false,
  }) {
    final generationAtSubmission = generation();
    final detached = Map<String, Object?>.from(
      jsonDecode(jsonEncode(params)) as Map,
    );
    return _scheduler.run(plugin.id, () {
      if (generation() != generationAtSubmission || blocked()) {
        throw const PluginDenied();
      }
      return _invoke(
        plugin,
        method,
        detached,
        List.unmodifiable(scopes),
        includeScopes: includeScopes,
        includeSelection: includeSelection,
        selection: List.unmodifiable(selection),
        scopeParameter: scopeParameter,
        titleParameter: titleParameter,
        uiScope: uiScope,
        bindSelection: bindSelection,
      );
    }, background: background);
  }

  Future<Object?> _invoke(
    PluginRecord plugin,
    String method,
    Map<String, Object?> params,
    List<PluginScope> scopes, {
    bool includeScopes = true,
    bool includeSelection = false,
    List<ExtensionTitle> selection = const [],
    String? scopeParameter,
    bool titleParameter = false,
    bool uiScope = false,
    void Function(Map<String, ExtensionTitle>)? bindSelection,
  }) async {
    if (!plugin.enabled || !plugin.handlers.contains(method)) {
      throw const PluginDenied();
    }
    final token = _token();
    final invocation = PluginInvocation(
      plugin,
      now().add(const Duration(seconds: 30)),
      generation(),
    );
    _access(invocation);
    for (final scope in scopes) {
      if (!plugin.collections.contains(scope.collection) ||
          !authorized(scope.collection, scope.kind)) {
        throw const PluginDenied();
      }
      invocation.scopes[_token()] = scope;
    }
    final selected = <Map<String, Object>>[];
    for (final title in selection) {
      if (!plugin.collections.contains(title.collection) ||
          !authorized(title.collection, title.kind) ||
          !scopes.any(
            (s) => s.collection == title.collection && s.kind == title.kind,
          )) {
        throw const PluginDenied();
      }
      selected.add(_titleHandle(invocation, title));
    }
    if (selection.length > 100) {
      throw const PluginDenied('resource_limit');
    }
    if (scopeParameter != null && invocation.scopes.length != 1 ||
        titleParameter && selected.length != 1) {
      throw const PluginDenied('invalid_request');
    }
    bindSelection?.call(Map.unmodifiable(invocation.titles));
    _invocations[token] = invocation;
    try {
      final input = jsonEncode({
        'v': 1,
        'id': 'invoke',
        'method': method,
        'params': {
          ...params,
          if (includeSelection)
            'selection': [
              for (final item in selected)
                {'id': item['id'], 'revision': item['revision']},
            ],
          ?scopeParameter: invocation.scopes.keys.single,
          if (titleParameter) 'title': selected.single['id'],
          if (uiScope)
            'scope': selected.isNotEmpty
                ? {
                    'scope': 'title',
                    'collection': selected.single['collection'],
                    'entity': selected.single['id'],
                  }
                : invocation.scopes.isEmpty
                ? {'scope': 'app'}
                : {
                    'scope': 'collection',
                    'collection': invocation.scopes.keys.single,
                  },
          if (includeScopes)
            'scopes': [
              for (final e in invocation.scopes.entries)
                {'handle': e.key, 'kind': e.value.kind.name},
            ],
        },
      });
      if (utf8.encode(input).length > 65536) {
        throw const PluginDenied('message_too_large');
      }
      final result = await backend.command('run', {
        'id': plugin.id,
        'revision': plugin.revision,
        'token': token,
        'input': input,
      });
      _access(invocation);
      if (!_invocations.containsKey(token)) throw const PluginDenied();
      if (result is! String || utf8.encode(result).length > 65536) {
        throw const PluginDenied('invalid_response');
      }
      final response = jsonDecode(result);
      _json(response);
      if (response is! Map ||
          response['v'] != 1 ||
          response['id'] != 'invoke' ||
          response.containsKey('result') == response.containsKey('error') ||
          response.keys.any(
            (k) => !{'v', 'id', 'result', 'error'}.contains(k),
          )) {
        throw const PluginDenied('invalid_response');
      }
      if (response.containsKey('error')) {
        final error = response['error'];
        const allowed = {
          'invalid_request',
          'invalid_response',
          'version_mismatch',
          'unsupported_capability',
          'permission_denied',
          'not_found',
          'conflict',
          'cancelled',
          'deadline_exceeded',
          'resource_limit',
          'message_too_large',
          'busy',
          'plugin_error',
          'runtime_failure',
        };
        if (error is! Map ||
            error.keys.length != 1 ||
            !allowed.contains(error['code'])) {
          throw const PluginDenied('invalid_response');
        }
        throw PluginDenied(error['code'] as String);
      }
      return response['result'];
    } finally {
      _invocations.remove(token);
    }
  }

  Future<String> dispatch(String token, String raw) async {
    String? id;
    try {
      if (utf8.encode(raw).length > 65536) {
        throw const PluginDenied('message_too_large');
      }
      final request = jsonDecode(raw) as Map<String, dynamic>;
      _json(request);
      if (request.length != 4 ||
          request['v'] != 1 ||
          request['id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(request['id'] as String) ||
          request['method'] is! String ||
          request['params'] is! Map) {
        throw const PluginDenied('invalid_request');
      }
      id = request['id'] as String;
      final invocation = _invocations[token];
      if (invocation == null) throw const PluginDenied();
      if (++invocation.calls > 64) throw const PluginDenied('resource_limit');
      _access(invocation);
      await backend.command('effect', {
        'token': token,
        'method': 'authorize',
        'params': <String, Object?>{},
      });
      _access(invocation);
      final method = request['method'] as String,
          params = request['params'] as Map<String, dynamic>;
      Object? value;
      switch (method) {
        case 'runtime.ping':
          _access(invocation, 'runtime.ping');
          value = {'protocol': 1, 'runtime': 'quickjs'};
        case 'catalog.titles':
          _access(invocation, 'catalog.read');
          final scope =
              invocation.scopes[params['handle'] ?? params['collection']];
          if (scope == null || !authorized(scope.collection, scope.kind)) {
            throw const PluginDenied();
          }
          final page = await catalog.titles(
            scope.collection,
            scope.kind,
            limit: params['limit'] as int? ?? 50,
            cursor: params['cursor'] as String?,
          );
          _access(invocation, 'catalog.read');
          if (!authorized(scope.collection, scope.kind)) {
            throw const PluginDenied();
          }
          if (invocation.titles.length + page.items.length > 512) {
            throw const PluginDenied('resource_limit');
          }
          value = {
            'items': [
              for (final title in page.items) _titleHandle(invocation, title),
            ],
            'nextCursor': page.nextCursor,
          };
        case 'catalog.propose':
          _access(invocation, 'catalog.propose');
          if (!{'replaceTags', 'mergeFields'}.contains(params['operation'])) {
            throw const PluginDenied('unsupported_capability');
          }
          final title = invocation.titles[params['handle']];
          if (title == null ||
              params['revision'] != title.revision ||
              !authorized(title.collection, title.kind)) {
            throw const PluginDenied();
          }
          final fieldEdit = params['operation'] == 'mergeFields';
          final fields = fieldEdit
              ? Map<String, dynamic>.from(params['fields'] as Map)
              : null;
          if (fields != null) {
            _json(fields);
            if (fields.length > 64 ||
                utf8.encode(jsonEncode(fields)).length > 16384 ||
                fields.keys.any(
                  (k) =>
                      !k.startsWith('${invocation.plugin.id}:') ||
                      !RegExp(
                        r'^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+:[a-z][a-zA-Z0-9_.-]{0,79}$',
                      ).hasMatch(k),
                )) {
              throw const PluginDenied('invalid_request');
            }
          }
          final tags = fieldEdit
              ? <String>[]
              : (params['tags'] as List).cast<String>();
          final key = params['idempotencyKey'] as String;
          if (tags.length > 100 ||
              tags.any((v) => v.trim().isEmpty || v.length > 80) ||
              !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(key) ||
              _proposals.length >= 64) {
            throw const PluginDenied('invalid_request');
          }
          final previous = _proposals.values
              .where((p) => p.plugin.id == invocation.plugin.id && p.key == key)
              .firstOrNull;
          if (previous != null &&
              (previous.title.id != title.id ||
                  previous.title.collection != title.collection ||
                  previous.title.kind != title.kind ||
                  previous.title.revision != title.revision ||
                  jsonEncode(previous.tags) != jsonEncode(tags) ||
                  jsonEncode(previous.fields) != jsonEncode(fields))) {
            throw const PluginDenied('conflict');
          }
          final proposal =
              previous ??
              PluginProposal(
                _token(),
                invocation.plugin,
                title,
                List.unmodifiable(tags),
                key,
                invocation.generation,
                fields: fields == null
                    ? null
                    : Map.unmodifiable(
                        jsonDecode(jsonEncode(fields)) as Map<String, dynamic>,
                      ),
              );
          _proposals[proposal.id] = proposal;
          value = {'proposal': proposal.id, 'status': 'awaitingConfirmation'};
        case 'http.get':
        case 'http.post':
          _access(invocation, 'http.request');
          final post = method == 'http.post';
          if (params.keys.any(
            (k) =>
                !(post ? {'url', 'credential', 'body'} : {'url', 'credential'})
                    .contains(k),
          )) {
            throw const PluginDenied('invalid_request');
          }
          if (post &&
              (params['body'] is! String ||
                  utf8.encode(params['body'] as String).length > 8192)) {
            throw const PluginDenied('invalid_request');
          }
          final uri = Uri.parse(params['url'] as String);
          if (uri.scheme != 'https' ||
              uri.userInfo.isNotEmpty ||
              uri.hasFragment ||
              !invocation.plugin.origins.contains(uri.origin)) {
            throw const PluginDenied();
          }
          if (params.containsKey('credential') &&
              params['credential'] != true &&
              params['credential'] != false &&
              params['credential'] != 'apiKey') {
            throw const PluginDenied('invalid_request');
          }
          if (params['credential'] == true ||
              params['credential'] == 'apiKey') {
            _access(invocation, 'credentials.use');
          }
          value = await backend.command('effect', {
            'token': token,
            'method': method,
            'params': params,
          });
        case 'settings.register':
        case 'settings.effective':
        case 'settings.changes':
        case 'settings.propose':
        case 'settings.reset':
          final write =
              method == 'settings.propose' || method == 'settings.reset';
          _access(invocation, write ? 'settings.write' : 'settings.read');
          final resolved = <String, Object?>{...params};
          final checked = <String, ExtensionMedia>{};
          Map<String, Object?> address(Object? raw) {
            if (raw is! Map) throw const PluginDenied('invalid_request');
            final scope = raw['scope'];
            if (scope == 'app' && raw.length == 1) return {'scope': 'app'};
            if (raw.keys.any(
              (key) =>
                  !{'scope', 'handle', 'collection', 'entity'}.contains(key),
            )) {
              throw const PluginDenied('invalid_request');
            }
            final handle =
                raw['handle'] ??
                (scope == 'collection' ? raw['collection'] : raw['entity']);
            if (handle is! String) throw const PluginDenied('invalid_request');
            if (scope == 'collection') {
              final item = invocation.scopes[handle];
              if (item == null || !authorized(item.collection, item.kind)) {
                throw const PluginDenied();
              }
              checked[item.collection] = item.kind;
              return {'scope': scope, 'collection': item.collection};
            }
            if (scope == 'group') {
              final item = invocation.scopes[handle];
              if (item == null ||
                  item.group == null ||
                  !authorized(item.collection, item.kind)) {
                throw const PluginDenied();
              }
              if (raw['collection'] != null &&
                  invocation.scopes[raw['collection']]?.collection !=
                      item.collection) {
                throw const PluginDenied();
              }
              checked[item.collection] = item.kind;
              return {
                'scope': scope,
                'collection': item.collection,
                'entity': item.group,
              };
            }
            if (scope == 'title') {
              final item = invocation.titles[handle];
              if (item == null || !authorized(item.collection, item.kind)) {
                throw const PluginDenied();
              }
              if (raw['collection'] != null &&
                  invocation.scopes[raw['collection']]?.collection !=
                      item.collection) {
                throw const PluginDenied();
              }
              checked[item.collection] = item.kind;
              return {
                'scope': scope,
                'collection': item.collection,
                'entity': item.id,
              };
            }
            throw const PluginDenied('unsupported_capability');
          }
          if (method == 'settings.effective') {
            resolved['lineage'] = [
              for (final item in params['lineage'] as List) address(item),
            ];
          } else if (write) {
            resolved['address'] = address(params['address']);
          }
          value = await backend.command('effect', {
            'token': token,
            'method': method,
            'params': resolved,
          });
          if (method == 'settings.effective') {
            final result = Map<String, Object?>.from(value as Map);
            final index = result.remove('sourceIndex') as int?;
            result['source'] = index == null
                ? null
                : (params['lineage'] as List)[index];
            value = result;
          }
          for (final item in checked.entries) {
            if (!authorized(item.key, item.value)) throw const PluginDenied();
          }
        case 'imports.read':
          _access(invocation, 'import.parse');
          if (params.length != 1 || params['handle'] is! String) {
            throw const PluginDenied('invalid_request');
          }
          value = await backend.command('effect', {
            'token': token,
            'method': method,
            'params': params,
          });
        case 'catalog.fields':
          _access(invocation, 'catalog.read');
          final title = invocation.titles[params['handle']];
          final store = mutations;
          if (title == null ||
              !authorized(title.collection, title.kind) ||
              store is! PluginFieldMutations) {
            throw const PluginDenied();
          }
          final fields = await (store as PluginFieldMutations).readFields(
            title,
          );
          if (!authorized(title.collection, title.kind)) {
            throw const PluginDenied();
          }
          value = {
            for (final entry in fields.entries)
              if (entry.key.startsWith('${invocation.plugin.id}:'))
                entry.key: entry.value,
          };
        case 'catalog.title':
          _access(invocation, 'catalog.read');
          final title = invocation.titles[params['handle']];
          if (title == null || !authorized(title.collection, title.kind)) {
            throw const PluginDenied();
          }
          value = {
            'id': params['handle'],
            'handle': params['handle'],
            'collection': invocation.scopes.entries
                .firstWhere((e) => e.value.collection == title.collection)
                .key,
            'title': title.title,
            'kind': title.kind.name,
            'revision': title.revision,
          };
        case 'storage.read':
        case 'storage.write':
          _access(invocation, 'storage.private');
          if (params['schema'] is! int ||
              (params['schema'] as int) < 1 ||
              (params['schema'] as int) > 100000 ||
              params['key'] is! String ||
              !RegExp(r'^[A-Za-z0-9_.-]{1,80}$')
                  .hasMatch(params['key'] as String) ||
              method == 'storage.write' &&
                  params['value'] != null &&
                  params['value'] is! String) {
            throw const PluginDenied('invalid_request');
          }
          if (params.keys.any(
            (k) =>
                !(method == 'storage.read'
                        ? {'schema', 'key'}
                        : {'schema', 'key', 'value'})
                    .contains(k),
          )) {
            throw const PluginDenied('invalid_request');
          }
          value = await backend.command('effect', {
            'token': token,
            'method': method,
            'params': params,
          });
        default:
          throw const PluginDenied('unsupported_capability');
      }
      _access(invocation);
      if (!_invocations.containsKey(token)) throw const PluginDenied();
      final response = jsonEncode({'v': 1, 'id': id, 'result': value});
      if (utf8.encode(response).length > 65536) {
        throw const PluginDenied('message_too_large');
      }
      return response;
    } catch (error) {
      return jsonEncode({
        'v': 1,
        'id': id,
        'error': {
          'code': error is PluginDenied ? error.code : 'invalid_request',
        },
      });
    }
  }

  void _json(Object? value, [int depth = 0]) {
    if (depth > 24) throw const PluginDenied('message_too_large');
    if (value is List) {
      if (value.length > 1024) throw const PluginDenied('message_too_large');
      for (final item in value) {
        _json(item, depth + 1);
      }
    } else if (value is Map) {
      if (value.length > 1024) throw const PluginDenied('message_too_large');
      for (final entry in value.entries) {
        if (entry.key is! String ||
            {'__proto__', 'prototype', 'constructor'}.contains(entry.key)) {
          throw const PluginDenied('invalid_request');
        }
        _json(entry.value, depth + 1);
      }
    } else if (value is String && value.length > 32768) {
      throw const PluginDenied('message_too_large');
    }
  }

  Map<String, Object> _titleHandle(
    PluginInvocation invocation,
    ExtensionTitle title,
  ) {
    final token = _token();
    invocation.titles[token] = title;
    final scope = invocation.scopes.entries
        .firstWhere(
          (e) =>
              e.value.collection == title.collection &&
              e.value.kind == title.kind,
        )
        .key;
    return {
      'id': token,
      'handle': token,
      'collection': scope,
      'title': title.title,
      'kind': title.kind.name,
      'revision': title.revision,
    };
  }

  Future<void> confirm(String proposalId) async {
    final proposal = _proposals[proposalId];
    if (proposal == null) throw const PluginDenied('not_found');
    final records = (await backend.command('list') as List).map(
      (v) => PluginRecord(Map<String, dynamic>.from(v as Map)),
    );
    final current = records
        .where((p) => p.id == proposal.plugin.id)
        .firstOrNull;
    void access() {
      if (!identical(_proposals[proposalId], proposal) ||
          current == null ||
          !current.enabled ||
          current.revision != proposal.plugin.revision ||
          current.instance != proposal.plugin.instance ||
          current.publisher != proposal.plugin.publisher ||
          !current.permissions.contains('catalog.propose') ||
          !current.collections.contains(proposal.title.collection) ||
          blocked() ||
          generation() != proposal.generation ||
          !authorized(proposal.title.collection, proposal.title.kind)) {
        throw const PluginDenied();
      }
    }

    access();
    if (proposal.fields != null) {
      final store = mutations;
      if (store is! PluginFieldMutations) {
        throw const PluginDenied('unsupported_capability');
      }
      await (store as PluginFieldMutations).mergeFields(
        current!,
        proposal.title,
        proposal.fields!,
        '${proposal.plugin.id}:${proposal.plugin.instance}:${proposal.plugin.revision}:${proposal.key}',
        access,
      );
    } else {
      await mutations.replaceTags(
        current!,
        proposal.title,
        proposal.tags,
        '${proposal.plugin.id}:${proposal.plugin.instance}:${proposal.plugin.revision}:${proposal.key}',
        access,
      );
    }
    access();
    _proposals.remove(proposalId);
  }

  void dismiss(String proposalId) => _proposals.remove(proposalId);
}
