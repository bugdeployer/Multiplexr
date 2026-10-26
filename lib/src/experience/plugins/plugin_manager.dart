import 'dart:math';
import 'dart:async';

import '../../features/metadata/application/metadata_contracts.dart';
import '../../features/metadata/application/metadata_workflow.dart';
import '../../features/plugins/application/contribution_validation.dart';
import '../../features/catalog/application/extension_catalog.dart';
import '../../features/plugins/application/contribution_registry.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/plugins/application/plugin_platform.dart';
export '../../features/plugins/application/plugin_platform.dart';

class PluginEditReview {
  PluginEditReview(
    this.id,
    this.contribution,
    this.title,
    this.changes,
    this.created,
  );
  final String id;
  final PluginContribution contribution;
  final ExtensionTitle title;
  final Map<String, dynamic> changes;
  final DateTime created;
}

class PluginManager extends ChangeNotifier {
  PluginManager({
    required this.backend,
    required this.gateway,
    required this.scopes,
    this.metadataTarget,
    this.restoredInventory,
    this.commitAuthority,
    this.reviewWorkflow,
  }) {
    backend.listen((token, request) async {
      final value = await gateway.dispatch(token, request);
      if (!_disposed) notifyListeners();
      return value;
    }, () => refresh());
  }
  final MetadataWorkflow Function()? reviewWorkflow;
  final Future<void> Function(MetadataCandidate, Future<void> Function())?
  commitAuthority;
  Future<void> commitMetadata(
    MetadataCandidate candidate,
    Future<void> Function() operation,
  ) async {
    final identity = candidate.implementation;
    final entry = identity == null
        ? null
        : registry.all
              .where(
                (c) =>
                    c.id == identity.contribution &&
                    c.plugin.id == identity.plugin &&
                    c.plugin.publisher == identity.publisher &&
                    c.plugin.version == identity.version &&
                    c.plugin.instance == identity.instance &&
                    c.plugin.revision == identity.permissionRevision &&
                    c.plugin.collections.contains(identity.collection),
              )
              .firstOrNull;
    if (entry == null || gateway.blocked() || commitAuthority == null) {
      throw const PluginDenied();
    }
    await withOrigin(
      identity!.plugin,
      () => commitAuthority!(candidate, operation),
    );
  }

  final Future<MetadataTarget> Function(ExtensionTitle)? metadataTarget;
  final _edits = <String, PluginEditReview>{};
  int _editSequence = 0;
  List<PluginEditReview> get edits => List.unmodifiable(_edits.values);
  final Future<List<Map<String, dynamic>>> Function()? restoredInventory;
  List<Map<String, dynamic>> restored = [];
  Timer? _eventTimer;
  final _eventSequences = <String, int>{};
  final _eventSession = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final _ready = <String>{};
  final _autoRuns = <String, ({DateTime start, int runs})>{};
  static final _originKey = Object();
  String? get commandOrigin => Zone.current[_originKey] as String?;
  Future<T> withOrigin<T>(String origin, Future<T> Function() operation) =>
      runZoned(operation, zoneValues: {_originKey: origin});
  final _pendingChanges = <String?, Set<String>>{};

  void signalCatalogChange(Set<String> changedCollections, {String? origin}) {
    if (_disposed ||
        !registry
            .family('event.handler')
            .any(
              (c) => (c.definition['events'] as List? ?? []).contains(
                'org.multiplexr:library.changed',
              ),
            ) ||
        gateway.blocked()) {
      return;
    }
    final sourceOrigin = origin ?? commandOrigin;
    _pendingChanges
        .putIfAbsent(sourceOrigin, () => {})
        .addAll(changedCollections);
    _eventTimer?.cancel();
    _eventTimer = Timer(const Duration(milliseconds: 300), () async {
      final pending = Map<String?, Set<String>>.from(_pendingChanges);
      _pendingChanges.clear();
      for (final batch in pending.entries) {
        try {
          await dispatchEvent(
            'org.multiplexr:library.changed',
            origin: batch.key,
            changedCollections: batch.value,
          );
        } catch (_) {
          // Delivery is best effort; later events request a fresh resync.
        }
      }
    });
  }

  Future<void> dispatchEvent(
    String event, {
    String? origin,
    Set<String>? changedCollections,
  }) async {
    if (_disposed || gateway.blocked()) {
      return;
    }
    final contributions = registry
        .family('event.handler')
        .where(
          (c) =>
              c.plugin.id != origin &&
              (c.definition['events'] as List? ??
                      ['org.multiplexr:application.ready'])
                  .contains(event),
        )
        .take(16)
        .toList();
    if (contributions.isEmpty) {
      return;
    }
    final selected = (await scopes())
        .where(
          (s) =>
              changedCollections == null ||
              changedCollections.contains(s.collection),
        )
        .toList();
    if (changedCollections != null && selected.isEmpty) {
      return;
    }
    for (final entry in contributions) {
      final granted = selected
          .where((s) => entry.plugin.collections.contains(s.collection))
          .take(32)
          .toList();
      if (changedCollections != null && granted.isEmpty) {
        continue;
      }
      final sequence = (_eventSequences[entry.plugin.id] ?? 0) + 1;
      _eventSequences[entry.plugin.id] = sequence;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_disposed || gateway.blocked() || !registry.current(entry)) {
          break;
        }
        final now = gateway.now();
        final window = _autoRuns[entry.plugin.id];
        final state =
            window == null ||
                now.difference(window.start) >= const Duration(minutes: 1)
            ? (start: now, runs: 0)
            : window;
        if (state.runs >= 4) {
          break;
        }
        _autoRuns[entry.plugin.id] = (start: state.start, runs: state.runs + 1);
        try {
          final result = await invokeContribution(
            entry.id,
            {
              'event': event,
              'sequence': sequence,
              'data': {
                'origin': origin ?? 'host',
                'correlation': '$_eventSession-$sequence',
                'resyncRequired': true,
              },
            },
            granted,
            background: true,
          );
          if ((result as Map)['acknowledged'] == true) {
            break;
          }
        } catch (_) {
          if (attempt == 1) {
            break;
          }
        }
      }
    }
  }

  final registry = ContributionRegistry();
  final PluginBackend backend;
  final PluginGateway gateway;
  final Future<List<PluginScope>> Function() scopes;
  List<PluginRecord> installed = [];
  String? error;
  String? invocationResult;
  bool busy = false;
  bool _disposed = false;
  void Function()? onDispose;
  int _refreshEpoch = 0;
  Future<void> refresh() async {
    if (_disposed) return;
    final epoch = ++_refreshEpoch;
    try {
      final next = (await backend.command('list') as List)
          .map((v) => PluginRecord(Map<String, dynamic>.from(v as Map)))
          .toList();
      final status = await backend.command('status') as String?;
      final inventory = await restoredInventory?.call() ?? [];
      if (_disposed || epoch != _refreshEpoch) return;
      for (final previous in installed) {
        final current = next.where((p) => p.id == previous.id).firstOrNull;
        if (current == null ||
            !current.enabled ||
            current.revision != previous.revision ||
            current.instance != previous.instance ||
            current.publisher != previous.publisher) {
          gateway.revoke(previous.id);
          _edits.removeWhere(
            (_, edit) => edit.contribution.plugin.id == previous.id,
          );
        }
      }
      installed = next;
      registry.replace(next);
      _ready.retainAll({
        for (final c in registry.family('event.handler'))
          '${c.id}:${c.plugin.instance}:${c.plugin.revision}',
      });
      _autoRuns.removeWhere((id, _) => !next.any((p) => p.id == id));
      _eventSequences.removeWhere((id, _) => !next.any((p) => p.id == id));
      final newlyReady = registry
          .family('event.handler')
          .where(
            (c) =>
                _ready.add('${c.id}:${c.plugin.instance}:${c.plugin.revision}'),
          )
          .toList()
          .isNotEmpty;
      if (newlyReady) {
        Future<void>.microtask(
          () => dispatchEvent('org.multiplexr:application.ready'),
        );
      }

      error = status;
      restored = inventory;
    } catch (_) {
      if (_disposed || epoch != _refreshEpoch) return;
      revoke();
      installed = [];
      error = 'Plugin manager is unavailable on this device.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<Object?> perform(
    String operation, [
    Map<String, Object?> args = const {},
  ]) async {
    if (busy) throw StateError('Plugin operation in progress');
    busy = true;
    error = null;
    notifyListeners();
    if ({
      'activate',
      'enable',
      'disable',
      'disableAll',
      'rollback',
      'remove',
      'permissions',
      'resetSettings',
      'restoreSettings',
    }.contains(operation)) {
      gateway.revoke(args['id'] as String?);
    }
    try {
      final value = await backend.command(operation, args);
      await refresh();
      return value;
    } catch (_) {
      error =
          'The operation could not complete. Your installed data is retained.';
      rethrow;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<Object?> invokeContribution(
    String id,
    Map<String, Object?> params,
    List<PluginScope> selectedScopes, {
    List<ExtensionTitle> selection = const [],
    bool background = false,
  }) async {
    final contribution = registry.require(id);
    final handler = contribution.handler;
    if (handler == null) {
      throw const PluginDenied('unsupported_capability');
    }
    var handles = <String, ExtensionTitle>{};
    final value = await gateway.invoke(
      contribution.plugin,
      handler,
      params,
      selectedScopes,
      includeScopes: false,
      includeSelection: {
        'library.tool',
        'export.handler',
        'import.handler',
      }.contains(contribution.family),
      selection: selection,
      scopeParameter: contribution.family == 'source.provider' ? 'root' : null,
      titleParameter: contribution.family == 'artwork.provider',
      uiScope: contribution.family.startsWith('ui.'),
      bindSelection: (value) => handles = Map.from(value),
      background: background,
    );
    if (!registry.current(contribution)) {
      throw const PluginDenied();
    }
    final validated = ContributionValidation.result(
      contribution.family,
      value,
      contribution.plugin.id,
    );
    if ({'library.tool', 'import.handler'}.contains(contribution.family)) {
      final pending = <PluginEditReview>[];
      for (final raw in (validated as Map)['proposals'] as List) {
        final proposal = raw as Map;
        final title = handles[proposal['title']];
        if (title == null || proposal['expectedRevision'] != title.revision) {
          throw const PluginDenied('invalid_response');
        }
        final key = 'edit-${++_editSequence}';
        pending.add(
          PluginEditReview(
            key,
            contribution,
            title,
            Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(proposal['changes'] as Map),
            ),
            DateTime.now(),
          ),
        );
      }
      if (_edits.length + pending.length > 64) {
        throw const PluginDenied('resource_limit');
      }
      _edits.addEntries(pending.map((p) => MapEntry(p.id, p)));
      if (!_disposed) {
        notifyListeners();
      }
    }
    return validated;
  }

  Future<String> materializeArtwork(
    String contributionId,
    Map<String, dynamic> item,
    List<PluginScope> scopes,
  ) async {
    final entry = registry.require(contributionId);
    if (entry.family != 'artwork.provider' ||
        gateway.blocked() ||
        scopes.isEmpty ||
        scopes.any(
          (s) =>
              !entry.plugin.collections.contains(s.collection) ||
              !gateway.authorized(s.collection, s.kind),
        )) {
      throw const PluginDenied();
    }
    final result = await backend.command('artworkHost', {
      'id': entry.plugin.id,
      'revision': entry.plugin.revision,
      'collections': scopes.map((s) => s.collection).toSet().toList(),
      if (item['content'] != null) 'content': item['content'],
      if (item['url'] != null) 'url': item['url'],
    });
    if (!registry.current(entry) ||
        gateway.blocked() ||
        scopes.any((s) => !gateway.authorized(s.collection, s.kind)) ||
        result is! String ||
        !result.startsWith('data:image/jpeg;base64,')) {
      throw const PluginDenied();
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> sessionCandidates(
    String contributionId,
  ) async {
    final entry = registry.require(contributionId);
    if (entry.family != 'session.hook' || gateway.blocked()) {
      throw const PluginDenied();
    }
    final values = await backend.command('sessionCandidates', {
      'id': entry.plugin.id,
      'revision': entry.plugin.revision,
    });
    if (!registry.current(entry) || gateway.blocked()) {
      throw const PluginDenied();
    }
    return [
      for (final raw in values as List)
        if (raw is Map &&
            entry.plugin.collections.contains(raw['collection']) &&
            gateway.authorized(
              raw['collection'] as String,
              raw['kind'] == 'music'
                  ? ExtensionMedia.music
                  : raw['kind'] == 'audiobook'
                  ? ExtensionMedia.audiobook
                  : ExtensionMedia.video,
            ))
          Map<String, dynamic>.from(raw),
    ];
  }

  Future<Object?> prepareSession(
    String contributionId,
    Map<String, dynamic> session,
  ) async {
    final collection = session['collection'] as String;
    final kind = session['kind'] == 'music'
        ? ExtensionMedia.music
        : session['kind'] == 'audiobook'
        ? ExtensionMedia.audiobook
        : ExtensionMedia.video;
    return invokeContribution(
      contributionId,
      {'session': session['handle'], 'state': session['state']},
      [PluginScope(collection, kind, 'Current session')],
    );
  }

  Future<void> applySession(
    String contributionId,
    Map<String, dynamic> session,
    Object? result,
  ) async {
    final entry = registry.require(contributionId);
    ContributionValidation.result('session.hook', result, entry.plugin.id);
    final collection = session['collection'] as String;
    final kind = session['kind'] == 'music'
        ? ExtensionMedia.music
        : session['kind'] == 'audiobook'
        ? ExtensionMedia.audiobook
        : ExtensionMedia.video;
    if (gateway.blocked() ||
        !entry.plugin.collections.contains(collection) ||
        !gateway.authorized(collection, kind)) {
      throw const PluginDenied();
    }
    await backend.command('sessionApply', {
      'id': entry.plugin.id,
      'revision': entry.plugin.revision,
      'handle': session['handle'],
      'commands': (result as Map)['commands'],
    });
  }

  Future<Map<String, dynamic>?> openImport(
    String id,
    List<PluginScope> selected,
  ) async {
    final entry = registry.require(id);
    if (entry.family != 'import.handler' ||
        gateway.blocked() ||
        selected.any(
          (s) =>
              !entry.plugin.collections.contains(s.collection) ||
              !gateway.authorized(s.collection, s.kind),
        )) {
      throw const PluginDenied();
    }
    final value = await backend.command('importFile', {
      'id': entry.plugin.id,
      'revision': entry.plugin.revision,
      'collections': selected.map((s) => s.collection).toSet().toList(),
    });
    if (!registry.current(entry) ||
        gateway.blocked() ||
        selected.any((s) => !gateway.authorized(s.collection, s.kind))) {
      throw const PluginDenied();
    }
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<void> exportResult(
    String id,
    Object? value,
    List<PluginScope> selected,
  ) async {
    final entry = registry.require(id);
    ContributionValidation.result('export.handler', value, entry.plugin.id);
    if (entry.family != 'export.handler' ||
        gateway.blocked() ||
        selected.any((s) => !gateway.authorized(s.collection, s.kind))) {
      throw const PluginDenied();
    }
    await backend.command('exportFile', {
      'id': entry.plugin.id,
      'revision': entry.plugin.revision,
      'collections': selected.map((s) => s.collection).toSet().toList(),
      ...Map<String, Object?>.from(value as Map),
    });
  }

  Future<(MetadataTarget, MetadataCandidate)> editReview(
    PluginEditReview edit,
  ) async {
    if (_edits[edit.id] != edit ||
        !registry.current(edit.contribution) ||
        gateway.blocked() ||
        DateTime.now().difference(edit.created) > const Duration(minutes: 5) ||
        !gateway.authorized(edit.title.collection, edit.title.kind) ||
        metadataTarget == null) {
      throw const PluginDenied();
    }
    final current = (await gateway.catalog.source.titles(
      edit.title.collection,
      edit.title.kind,
    )).where((t) => t.id == edit.title.id && t.revision == edit.title.revision);
    if (current.isEmpty) {
      throw const PluginDenied('conflict');
    }
    final target = await metadataTarget!(edit.title);
    final p = edit.contribution.plugin;
    return (
      target,
      MetadataCandidate(
        provider: edit.contribution.id,
        id: '${p.id}:tool-result',
        entity: target.entity,
        attribution: p.name,
        implementation: MetadataImplementation(
          plugin: p.id,
          publisher: p.publisher,
          version: p.version,
          contribution: edit.contribution.id,
          instance: p.instance,
          permissionRevision: p.revision,
          collection: edit.title.collection,
        ),
        values: {
          ...edit.changes,
          if (edit.changes['authors'] != null)
            'author': (edit.changes['authors'] as List).join(', '),
          if (edit.changes['authors'] != null)
            'artist': (edit.changes['authors'] as List).join(', '),
        },
      ),
    );
  }

  void dismissEdit(String id) {
    _edits.remove(id);
    notifyListeners();
  }

  Future<void> invoke(
    PluginRecord plugin,
    String method,
    List<PluginScope> selected,
  ) async {
    busy = true;
    notifyListeners();
    try {
      final value = await gateway.invoke(plugin, method, const {}, selected);
      invocationResult = value is String ? value : jsonEncode(value);
    } catch (_) {
      invocationResult = 'Plugin invocation failed or access was revoked.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<Map<String, dynamic>> hostSettings(
    PluginRecord plugin,
    String method,
    Map<String, Object?> params,
  ) async {
    final addresses =
        (params['lineage'] as List?)?.cast<Map>() ??
        [if (params['address'] is Map) params['address'] as Map];
    void access() {
      if (gateway.blocked()) {
        throw const PluginDenied();
      }
      final current = installed.where((p) => p.id == plugin.id).firstOrNull;
      if (current == null ||
          !current.enabled ||
          current.revision != plugin.revision ||
          current.instance != plugin.instance) {
        throw const PluginDenied();
      }
      for (final address in addresses) {
        final collection = address['collection'];
        if (collection is String && !plugin.collections.contains(collection)) {
          throw const PluginDenied();
        }
      }
    }

    access();
    final available = await scopes();
    for (final address in addresses) {
      if (address['collection'] != null &&
          !available.any((s) => s.collection == address['collection'])) {
        throw const PluginDenied();
      }
    }
    access();
    final result = await backend.command('settingsHost', {
      'id': plugin.id,
      'revision': plugin.revision,
      'method': method,
      'params': params,
    });
    access();
    final after = await scopes();
    for (final address in addresses) {
      if (address['collection'] != null &&
          !after.any((s) => s.collection == address['collection'])) {
        throw const PluginDenied();
      }
    }
    return Map<String, dynamic>.from(result as Map);
  }

  void revoke() {
    _eventTimer?.cancel();
    _pendingChanges.clear();
    _edits.clear();
    registry.clear();
    gateway.revoke();
    backend.command('cancel').catchError((_) => null);
  }

  @override
  void dispose() {
    _eventTimer?.cancel();
    _disposed = true;
    onDispose?.call();
    revoke();
    super.dispose();
  }
}
