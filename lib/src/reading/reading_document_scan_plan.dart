import 'dart:convert';

import 'domain/reading_catalog.dart';
import 'domain/reading_codec.dart';
import 'domain/reading_index.dart';

class ReadingDocumentPlan {
  ReadingDocumentPlan({
    required this.beforeCatalog,
    required this.beforeIndex,
    required this.catalog,
    required this.index,
    required this.warnings,
    required this.unresolved,
    required this.complete,
    required this.added,
    required this.relinked,
    required this.missing,
    required this.discovery,
    required this.rootReplacements,
  });
  final Map<String, dynamic>? beforeCatalog, beforeIndex;
  final Map<String, dynamic> catalog, index;
  final List<String> warnings, unresolved;
  final bool complete;
  final int added, relinked, missing;
  final Map<String, dynamic> discovery;
  final Map<String, String> rootReplacements;
  String get collectionId => discovery['collectionId'] as String;
  bool get canApply => complete && unresolved.isEmpty;
}

/// Produces reviewable data; R5 supplies the collection/repair presentation.
abstract final class ReadingScanPlanner {
  static ReadingDocumentPlan preview(
    Map<String, dynamic>? beforeCatalog,
    Map<String, dynamic>? beforeIndex,
    Map<String, dynamic> discovery, {
    Map<String, String> rootReplacements = const {},
    Map<String, String> relinks = const {},
    Map<String, String> grouping = const {},
    Map<String, List<String>> resourceOrder = const {},
    List<String> titleOrder = const [],
  }) {
    final current = beforeCatalog == null
        ? ReadingCatalog()
        : ReadingCodec.decode(beforeCatalog);
    final oldIndex = ReadingIndex(beforeIndex ?? ReadingIndex.empty(), current);
    final next = ReadingIndex.copy(
      beforeCatalog ?? ReadingCodec.encode(current),
    );
    final index = ReadingIndex.copy(oldIndex.json);
    if (discovery['version'] is! int ||
        discovery['version'] != 1 ||
        discovery['collectionId'] is! String ||
        discovery['sources'] is! List ||
        discovery['roots'] is! List ||
        discovery['warnings'] is! List) {
      throw FormatException('Invalid reading discovery response');
    }
    final owner = discovery['collectionId'] as String;
    final collections = (next['collections'] as List)
        .cast<Map<String, dynamic>>();
    final collection = collections.where((c) => c['id'] == owner).single;
    final roots = (collection['roots'] as List).cast<Map<String, dynamic>>();
    if (rootReplacements.keys.any(
      (old) => !roots.any((r) => r['uri'] == old),
    )) {
      throw ArgumentError('Unknown replaced root');
    }
    for (final root in roots) {
      root['uri'] = rootReplacements[root['uri']] ?? root['uri'];
    }
    final expectedRoots = roots.map((r) => r['uri']).toSet();
    final scannedRoots = ReadingWire.list(discovery['roots'], 100).map((raw) {
      final r = ReadingWire.object(raw, {'uri', 'complete'});
      ReadingWire.text(r['uri']);
      ReadingWire.flag(r['complete']);
      return r;
    }).toList();
    if (scannedRoots.isEmpty ||
        scannedRoots.length != expectedRoots.length ||
        scannedRoots.map((r) => r['uri']).toSet().length !=
            scannedRoots.length ||
        !expectedRoots.containsAll(scannedRoots.map((r) => r['uri']))) {
      throw FormatException('Scan root snapshot mismatch');
    }
    final titles = (next['titles'] as List).cast<Map<String, dynamic>>();
    final groups = (next['groups'] as List).cast<Map<String, dynamic>>();
    final memberships = (next['memberships'] as List)
        .cast<Map<String, dynamic>>();
    final evidence = (index['entries'] as List).cast<Map<String, dynamic>>();
    final local = titles.where((t) => t['collectionId'] == owner).toList();
    for (final t in local) {
      final s = t['source'] as Map<String, dynamic>;
      s['rootUri'] = rootReplacements[s['rootUri']] ?? s['rootUri'];
    }
    for (final e in evidence.where((e) => e['collectionId'] == owner)) {
      e['rootUri'] = rootReplacements[e['rootUri']] ?? e['rootUri'];
    }
    final byTitle = {
      for (final e in evidence.where((e) => e['collectionId'] == owner))
        e['id']: e,
    };
    final bySource = {
      for (final t in local)
        (byTitle[t['id']]?['sourceKey'] ?? (t['source'] as Map)['id']): t,
    };
    final sources = ReadingWire.list(discovery['sources'])
        .map(
          (raw) => ReadingWire.object(raw, {
            'sourceKey',
            'uri',
            'name',
            'rootUri',
            'relativePath',
            'format',
            'fingerprint',
            'metadata',
            'readingOrder',
            'cover',
            'encoding',
            'series',
            'ambiguous',
          }),
        )
        .toList();
    if (sources.map((s) => s['sourceKey']).toSet().length != sources.length) {
      throw FormatException('Duplicate discovered source');
    }
    final foundKeys = sources.map((s) => s['sourceKey']).toSet();
    final absent = local
        .where(
          (t) => !foundKeys.contains(
            byTitle[t['id']]?['sourceKey'] ?? (t['source'] as Map)['id'],
          ),
        )
        .toList();
    final absentByFingerprint = <String, List<Map<String, dynamic>>>{};
    for (final title in absent.where((t) => !relinks.containsKey(t['id']))) {
      final fingerprint = byTitle[title['id']]?['fingerprint'];
      if (fingerprint != null) {
        (absentByFingerprint['$fingerprint:${title['format']}'] ??= []).add(
          title,
        );
      }
    }
    final sourceCounts = <String, int>{};
    for (final source in sources.where(
      (s) => !bySource.containsKey(s['sourceKey']),
    )) {
      final key = '${source['fingerprint']}:${source['format']}';
      sourceCounts[key] = (sourceCounts[key] ?? 0) + 1;
    }
    final titlePositions = {
      for (var i = 0; i < titles.length; i++)
        ReadingIndex.identity(
          titles[i]['collectionId'] as String,
          titles[i]['id'] as String,
        ): i,
    };
    final evidencePositions = {
      for (var i = 0; i < evidence.length; i++)
        ReadingIndex.identity(
          evidence[i]['collectionId'] as String,
          evidence[i]['id'] as String,
        ): i,
    };
    final groupIds = {
      for (final g in groups)
        ReadingIndex.identity(g['collectionId'] as String, g['id'] as String),
    };
    final used = <String>{};
    final unresolved = <String>[];
    final warnings = (discovery['warnings'] as List)
        .map((v) => ReadingWire.text(v))
        .toList();
    var added = 0, reconnected = 0;
    if (relinks.values.toSet().length != relinks.length ||
        relinks.keys.any((id) => !absent.any((t) => t['id'] == id)) ||
        relinks.values.any(
          (key) => !sources.any(
            (s) => s['sourceKey'] == key && !bySource.containsKey(key),
          ),
        )) {
      throw ArgumentError('Invalid relink decision');
    }
    for (final source in sources) {
      final key = ReadingWire.text(source['sourceKey']);
      ReadingWire.flag(source['ambiguous']);
      final root = ReadingWire.text(source['rootUri']);
      if (!expectedRoots.contains(root)) {
        throw FormatException('Source belongs to an unscanned root');
      }
      final explicitId = relinks.entries
          .where((e) => e.value == key)
          .firstOrNull
          ?.key;
      Map<String, dynamic>? existing = bySource[key];
      if (explicitId != null) {
        existing = absent.singleWhere((t) => t['id'] == explicitId);
      }
      if (existing == null) {
        final fingerprintKey = '${source['fingerprint']}:${source['format']}';
        final candidates =
            absentByFingerprint[fingerprintKey] ??
            const <Map<String, dynamic>>[];
        final competitors = sourceCounts[fingerprintKey] ?? 0;
        if (candidates.length == 1 &&
            competitors == 1 &&
            !used.contains(candidates.single['id'])) {
          existing = candidates.single;
        } else if (candidates.isNotEmpty) {
          unresolved.add('$key: choose which missing title to reconnect');
          continue;
        }
      }
      if (source['ambiguous'] == true &&
          existing == null &&
          !grouping.containsKey(key)) {
        unresolved.add('$key: review series/standalone assignment');
        continue;
      }
      if (existing != null &&
          (existing['format'] != source['format'] ||
              !used.add(existing['id'] as String))) {
        throw ArgumentError('Incompatible or duplicate relink');
      }
      final id =
          existing?['id'] as String? ?? ReadingIndex.stableId(owner, key);
      final oldEvidence = byTitle[id];
      final incoming = ReadingMetadata.fromJson(source['metadata']).toJson();
      final metadata = ReadingIndex.copy(incoming);
      final manual = <String>{
        ...((oldEvidence?['manualFields'] as List?)?.cast<String>() ?? []),
      };
      if (existing != null) {
        final previous = existing['metadata'] as Map<String, dynamic>;
        final baseline = oldEvidence?['metadata'] as Map<String, dynamic>?;
        for (final field in ReadingIndex.metadataFields) {
          if (baseline == null ||
              jsonEncode(previous[field]) != jsonEncode(baseline[field])) {
            manual.add(field);
          }
          if (manual.contains(field)) {
            if (previous.containsKey(field)) {
              metadata[field] = previous[field];
            } else {
              metadata.remove(field);
            }
          }
        }
        if (!bySource.containsKey(key)) reconnected++;
      } else {
        added++;
      }
      var order = ReadingWire.list(source['readingOrder'])
          .map((r) => ReadingResource.fromJson(r).toJson())
          .toList();
      final requestedOrder = resourceOrder[key];
      if (requestedOrder != null) {
        if (requestedOrder.toSet().length != order.length ||
            requestedOrder.length != order.length ||
            !requestedOrder.toSet().containsAll(order.map((r) => r['id']))) {
          throw ArgumentError(
            'Resource order must include every page/chapter once',
          );
        }
        final positions = {
          for (var i = 0; i < requestedOrder.length; i++) requestedOrder[i]: i,
        };
        order.sort(
          (a, b) => positions[a['id']]!.compareTo(positions[b['id']]!),
        );
      } else if (oldEvidence?['manualOrder'] == true && existing != null) {
        final previous = (existing['readingOrder'] as List)
            .map((r) => (r as Map)['id'])
            .toList();
        order.sort((a, b) {
          final x = previous.indexOf(a['id']), y = previous.indexOf(b['id']);
          return (x < 0 ? previous.length : x).compareTo(
            y < 0 ? previous.length : y,
          );
        });
      }
      // A changed order is a source revision change even when bytes are identical.
      final revision = ReadingIndex.stableId(
        source['fingerprint'] as String,
        jsonEncode(order.map((r) => r['id']).toList()),
      );
      final record = <String, dynamic>{
        'collectionId': owner,
        'id': id,
        'subtype': collection['subtype'],
        'role': existing?['role'] ?? 'publication',
        'format': source['format'],
        'metadata': metadata,
        'source': {
          'id': (existing?['source'] as Map?)?['id'] ?? key,
          'uri': source['uri'],
          'name': source['name'],
          'rootUri': root,
          'revision': revision,
          'available': true,
        },
        'readingOrder': order,
      };
      if (existing != null) {
        titles[titlePositions[ReadingIndex.identity(owner, id)]!] = record;
      } else {
        titles.add(record);
      }
      final evidenceRecord = <String, dynamic>{
        'collectionId': owner,
        'id': id,
        'sourceKey': key,
        'rootUri': root,
        'relativePath': source['relativePath'],
        'fingerprint': source['fingerprint'],
        'metadata': incoming,
        'cover': oldEvidence?['manualCover'] == true
            ? oldEvidence!['cover']
            : source['cover'] != ''
            ? source['cover']
            : oldEvidence?['cover'] ?? '',
        'manualCover': oldEvidence?['manualCover'] ?? false,
        'manualFields': manual.toList(),
        'manualOrder':
            requestedOrder != null || oldEvidence?['manualOrder'] == true,
        'encoding': source['encoding'],
      };
      if (oldEvidence != null) {
        evidence[evidencePositions[ReadingIndex.identity(owner, id)]!] =
            evidenceRecord;
      } else {
        evidence.add(evidenceRecord);
      }
      if (existing == null || grouping.containsKey(key)) {
        if (existing != null) {
          memberships.removeWhere(
            (m) => m['collectionId'] == owner && m['titleId'] == id,
          );
        }
        final series = grouping[key] ?? source['series'] as String;
        if (series.isNotEmpty || collection['subtype'] == 'comics') {
          final standalone = series.isEmpty;
          final groupId = ReadingIndex.stableId(
            owner,
            standalone ? 'standalone:$id' : 'series:$root:$series',
          );
          if (groupIds.add(ReadingIndex.identity(owner, groupId))) {
            groups.add({
              'collectionId': owner,
              'id': groupId,
              'subtype': collection['subtype'],
              'metadata': ReadingMetadata(
                title: standalone ? metadata['title'] as String : series,
              ).toJson(),
            });
          }
          memberships.add({
            'collectionId': owner,
            'parentId': groupId,
            'titleId': id,
            'order': 0,
          });
        }
      }
    }
    var missing = 0;
    final complete = scannedRoots.every((r) => r['complete'] == true);
    if (complete) {
      for (final title in absent.where((t) => !used.contains(t['id']))) {
        (title['source'] as Map)['available'] = false;
        missing++;
      }
    }
    if (titleOrder.isNotEmpty &&
        (titleOrder.toSet().length != titleOrder.length ||
            titleOrder.any(
              (id) => !titles.any(
                (t) => t['collectionId'] == owner && t['id'] == id,
              ),
            ))) {
      throw ArgumentError('Invalid title order');
    }
    final storedOrder = (index['orders'] as List)
        .where((o) => o['collectionId'] == owner)
        .firstOrNull;
    final effectiveTitleOrder = titleOrder.isNotEmpty
        ? titleOrder
        : (storedOrder?['ids'] as List?)?.cast<String>() ?? const <String>[];
    if (titleOrder.isNotEmpty) {
      (index['orders'] as List).removeWhere((o) => o['collectionId'] == owner);
      (index['orders'] as List).add({'collectionId': owner, 'ids': titleOrder});
    }
    final titleNames = {
      for (final t in titles.where((t) => t['collectionId'] == owner))
        t['id']: t['source']['name'] as String,
    };
    final childrenByParent = <Object?, List<Map<String, dynamic>>>{};
    for (final m in memberships.where((m) => m['collectionId'] == owner)) {
      (childrenByParent[m['parentId']] ??= []).add(m);
    }
    for (final parent
        in memberships
            .where((m) => m['collectionId'] == owner)
            .map((m) => m['parentId'])
            .toSet()) {
      final children = childrenByParent[parent]!;
      if (effectiveTitleOrder.isNotEmpty) {
        children.sort((a, b) {
          final x = effectiveTitleOrder.indexOf(a['titleId']),
              y = effectiveTitleOrder.indexOf(b['titleId']);
          return (x < 0 ? effectiveTitleOrder.length : x).compareTo(
            y < 0 ? effectiveTitleOrder.length : y,
          );
        });
      } else {
        children.sort(
          (a, b) => readingNaturalCompare(
            titleNames[a['titleId']]!,
            titleNames[b['titleId']]!,
          ),
        );
      }
      for (var i = 0; i < children.length; i++) {
        children[i]['order'] = i;
      }
    }
    next['titles'] = titles;
    next['groups'] = groups;
    next['memberships'] = memberships;
    index['entries'] = evidence;
    index['roots'] = [
      ...(index['roots'] as List).where((r) => r['collectionId'] != owner),
      for (final root in scannedRoots) {'collectionId': owner, ...root},
    ];
    for (final old in rootReplacements.keys) {
      for (final r in index['replacements'] as List) {
        if (r['collectionId'] == owner && r['to'] == old) {
          r['to'] = rootReplacements[old];
        }
      }
      (index['replacements'] as List).removeWhere(
        (r) =>
            r['collectionId'] == owner &&
            (r['from'] == r['to'] || r['from'] == old),
      );
      (index['replacements'] as List).add({
        'collectionId': owner,
        'from': old,
        'to': rootReplacements[old],
      });
    }
    ReadingIndex(index, ReadingCodec.decode(next));
    return ReadingDocumentPlan(
      beforeCatalog: beforeCatalog == null
          ? null
          : ReadingIndex.copy(beforeCatalog),
      beforeIndex: beforeIndex == null ? null : ReadingIndex.copy(beforeIndex),
      catalog: next,
      index: index,
      warnings: warnings,
      unresolved: unresolved,
      complete: complete,
      added: added,
      relinked: reconnected,
      missing: missing,
      discovery: ReadingIndex.copy(discovery),
      rootReplacements: Map.unmodifiable(rootReplacements),
    );
  }
}
