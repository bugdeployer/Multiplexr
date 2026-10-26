import '../reading/domain/reading_location.dart';

import 'dart:async';

import '../features/metadata/application/metadata_batch_journal.dart';

import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../reading/domain/reading_catalog.dart';
import '../reading/domain/reading_codec.dart';
import '../reading/domain/reading_index.dart';
import '../reading/domain/reading_management.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../settings/domain/media_settings.dart';

import '../features/catalog/application/reading_catalog_ports.dart';
import 'reading_document_draft.dart';

class ReadingDocumentTransaction implements ReadingTransaction {
  ReadingDocumentTransaction(this.collection, this.draft);
  final String collection;
  final ReadingDocumentDraft draft;
  bool _closed = false;
  void close() => _closed = true;
  Map<String, dynamic> _collection(CatalogCollection value) => {
    'id': value.id,
    'name': value.name,
    'subtype': value.subtype.name,
    'locked': value.access.locked,
    'includeInGlobal': value.access.includeInGlobal,
    'roots': [
      for (final root in value.roots) {'uri': root.uri, 'name': root.name},
    ],
  };
  @override
  Future<void> artwork(CatalogIdentity id, String reference, String mode) =>
      update(id.collectionId, (d) {
        d.row(id);
        ReadingManagement.cover(reference);
        if (!{'fit', 'crop'}.contains(mode)) {
          throw ArgumentError('Invalid cover mode');
        }
        final record = d.managed(id);
        record['cover'] = reference;
        record['coverMode'] = mode;
        record['manualCover'] = true;
        final evidence = d.evidence(id);
        if (evidence != null) {
          evidence['cover'] = reference;
          evidence['manualCover'] = true;
        }
      });
  @override
  Future<void> journal(
    String collection,
    String provider,
    MetadataBatchJournal Function(MetadataBatchJournal?) change,
  ) => update(collection, (d) {
    final jobs = d.management['jobs'] as List;
    final previous = jobs
        .where((row) => row['collectionId'] == collection)
        .firstOrNull;
    final journal = previous is Map && previous['provider'] == provider
        ? MetadataBatchJournal(
            implementationEpoch:
                previous['implementationEpoch'] as String? ?? '',
            done: previous['done'] as int,
            total: previous['total'] as int,
            remaining: List<String>.from(previous['remaining'] as List),
            entries: {
              for (final row in previous['entries'] as List)
                row['id'] as String: Map<String, dynamic>.from(row as Map),
            },
          )
        : null;
    final next = change(journal);
    jobs.removeWhere((row) => row['collectionId'] == collection);
    jobs.add({
      'collectionId': collection,
      'provider': provider,
      'implementationEpoch': next.implementationEpoch,
      'done': next.done,
      'total': next.total,
      'remaining': next.remaining,
      'entries': next.entries.values.toList(),
    });
  });
  Future<void> update(
    String owner,
    FutureOr<void> Function(ReadingDocumentDraft) change,
  ) async {
    if (_closed) throw StateError('Reading transaction is closed');
    if (owner != collection) {
      throw StateError('Reading transaction owner mismatch');
    }
    await change(draft);
  }

  @override
  Future<void> recordOpened(CatalogIdentity id, int milliseconds) =>
      update(id.collectionId, (d) {
        d.row(id);
        d.managed(id)['lastOpened'] = milliseconds;
      });

  @override
  Future<void> addPageNote(
    ReadingTitle title,
    PageReadingLocation location, {
    required String id,
    required bool bookmark,
    String note = '',
    String? label,
  }) => update(title.catalog.id.collectionId, (d) {
    final row = d.row(title.catalog.id);
    final source = row['source'] as Map;
    if (source['revision'] != title.sourceRevision ||
        source['id'] != title.catalog.sources.single.id ||
        source['available'] != true ||
        location.pageIndex < 0 ||
        location.pageIndex >= title.readingOrder.length ||
        title.readingOrder[location.pageIndex].id != location.pageId) {
      throw StateError('Publication changed while adding a page note');
    }
    (d.management['pageNotes'] as List).add({
      'id': id,
      'collectionId': title.catalog.id.collectionId,
      'titleId': title.catalog.id.entityId,
      'sourceId': title.catalog.sources.single.id,
      'sourceRevision': title.sourceRevision,
      'pageId': location.pageId,
      'pageIndex': location.pageIndex,
      'offset': location.offset,
      'kind': bookmark ? 'bookmark' : 'note',
      'note': note,
      'label': label ?? 'Page ${location.pageIndex + 1}',
    });
  });
  @override
  Future<void> editPageNote(
    String owner,
    String id, {
    required String note,
    required String label,
  }) => update(owner, (d) {
    final current = (d.management['pageNotes'] as List).singleWhere(
      (n) => n['id'] == id && n['collectionId'] == owner,
    );
    current['note'] = note;
    current['label'] = label;
  });
  @override
  Future<void> removePageNote(String owner, String id) => update(owner, (d) {
    (d.management['pageNotes'] as List).removeWhere(
      (n) => n['id'] == id && n['collectionId'] == owner,
    );
  });

  @override
  Future<void> removeCollection(String collection) => update(collection, (d) {
    final catalog = ReadingCodec.encode(
      ReadingCodec.decode(d.catalog).withoutCollection(collection),
    );
    d.catalog
      ..clear()
      ..addAll(catalog);
    for (final document in [d.index, d.management]) {
      for (final rows in document.values.whereType<List>()) {
        rows.removeWhere((r) => r is Map && r['collectionId'] == collection);
      }
    }
  });
  @override
  Future<void> metadata(
    CatalogIdentity id,
    Map<String, dynamic> patch, {
    bool manual = true,
    String provider = '',
    String candidateId = '',
    Map<String, dynamic>? expected,
  }) => update(id.collectionId, (d) {
    final row = d.row(id), managed = d.managed(id), evidence = d.evidence(id);
    final current = row['metadata'] as Map<String, dynamic>;
    for (final field in patch.keys) {
      if (field != 'cover' && !ReadingIndex.metadataFields.contains(field)) {
        throw ArgumentError('Unsupported reading metadata field');
      }
      final previous = field == 'cover'
          ? (id.kind == CatalogEntityKind.title
                ? (evidence?['cover'] ?? managed['cover'])
                : managed['cover'])
          : current[field];
      if (expected != null && !metadataValueEquals(previous, expected[field])) {
        throw const MetadataFailure(
          MetadataFailureKind.conflict,
          'Metadata changed while reviewing. Reopen the match.',
        );
      }
    }
    final text = {
      ...current,
      ...(Map<String, dynamic>.from(patch)..remove('cover')),
    };
    row['metadata'] = ReadingMetadata.fromJson(text).toJson();
    if (manual) {
      managed['manualFields'] = {
        ...managed['manualFields'] as List,
        ...patch.keys.where((f) => f != 'cover'),
      }.toList();
    }
    if (evidence != null && manual) {
      evidence['manualFields'] = {
        ...evidence['manualFields'] as List,
        ...patch.keys.where((f) => f != 'cover'),
      }.toList();
    }
    if (patch.containsKey('cover')) {
      ReadingManagement.cover(patch['cover']);
      managed['cover'] = patch['cover'];
      managed['manualCover'] = true;
      if (evidence != null) {
        evidence['cover'] = patch['cover'];
        evidence['manualCover'] = true;
      }
    }
    if (provider.isNotEmpty) {
      managed['provider'] = provider;
      managed['candidateId'] = candidateId;
    }
  });
  @override
  Future<void> tags(
    String collection,
    List<CatalogIdentity> ids,
    List<String> tags, {
    String operation = 'replace',
    String? target,
  }) => update(collection, (d) {
    ReadingManagement.strings(tags, maximum: 100, length: 80);
    if (!{'replace', 'add', 'remove', 'rename', 'delete'}.contains(operation)) {
      throw ArgumentError('Invalid tag action');
    }
    final local = operation == 'rename' || operation == 'delete'
        ? [
            ...(d.catalog['titles'] as List)
                .where((r) => r['collectionId'] == collection)
                .map(
                  (r) => CatalogIdentity(
                    collection,
                    r['id'],
                    CatalogEntityKind.title,
                  ),
                ),
            ...(d.catalog['groups'] as List)
                .where((r) => r['collectionId'] == collection)
                .map(
                  (r) => CatalogIdentity(
                    collection,
                    r['id'],
                    CatalogEntityKind.group,
                  ),
                ),
          ]
        : ids;
    for (final id in local) {
      if (id.collectionId != collection) throw StateError('Tag owner mismatch');
      d.row(id);
      final record = d.managed(id);
      final old = List<String>.from(record['tags'] as List);
      final names = tags.map((s) => s.toLowerCase()).toSet();
      final values = switch (operation) {
        'replace' => tags,
        'add' => [...old, ...tags],
        'remove' ||
        'delete' => old.where((s) => !names.contains(s.toLowerCase())).toList(),
        _ =>
          old
              .map((s) => names.contains(s.toLowerCase()) ? target ?? '' : s)
              .toList(),
      };
      final seen = <String>{};
      record['tags'] = values.where((s) => seen.add(s.toLowerCase())).toList();
    }
  });
  @override
  Future<void> browse(String collection, Map<String, dynamic> values) =>
      update(collection, (d) {
        _preferences(collection, values);
        final rows = d.management['collections'] as List;
        final current = rows
            .where((r) => r['collectionId'] == collection)
            .firstOrNull;
        rows.removeWhere((r) => r['collectionId'] == collection);
        rows.add({
          'collectionId': collection,
          'layout': 'grid',
          'sort': 'title',
          'openAction': 'details',
          ...?current as Map?,
          ...values,
        });
      });
  @override
  Future<void> settings(
    String collection,
    MediaSubtype subtype,
    SettingsScope scope,
    String? entityId,
    Map<String, Object> values, {
    bool reset = false,
  }) => update(collection, (d) {
    final rows = d.catalog['settings'] as List;
    final old = rows
        .where(
          (r) =>
              r['scope'] == scope.name &&
              r['collectionId'] == collection &&
              r['entityId'] == entityId,
        )
        .firstOrNull;
    rows.removeWhere((r) => identical(r, old));
    final merged = reset
        ? <String, Object>{}
        : <String, Object>{
            ...?old?['values'] as Map<String, dynamic>?,
            ...values,
          };
    if (merged.isNotEmpty) {
      rows.add(
        ReadingSettingsLayer(
          scope: scope,
          subtype: subtype,
          collectionId: collection,
          entityId: entityId,
          values: merged,
        ).toJson(),
      );
    }
  });
  @override
  Future<void> finished(
    String collection,
    List<CatalogIdentity> ids,
    bool finished,
  ) => update(collection, (d) {
    final progress = d.catalog['progress'] as List;
    for (final id in ids) {
      if (id.collectionId != collection || id.kind != CatalogEntityKind.title) {
        throw StateError('Progress owner mismatch');
      }
      final title = d.row(id);
      final old = progress
          .where(
            (p) => p['collectionId'] == collection && p['id'] == id.entityId,
          )
          .firstOrNull;
      if (old != null) {
        old['finished'] = finished;
        continue;
      }
      final source = title['source'] as Map;
      final resources = title['readingOrder'] as List;
      progress.add({
        'collectionId': collection,
        'id': id.entityId,
        'sourceId': source['id'],
        'sourceRevision': source['revision'],
        'finished': finished,
        'location': title['subtype'] == 'ebook'
            ? {
                'version': 1,
                'kind': 'text',
                'resourceId': resources.first['id'],
                'locatorType': 'textOffset',
                'locator': '0',
                'progression': 0.0,
                'before': '',
                'highlight': '',
                'after': '',
              }
            : {
                'version': 1,
                'kind': 'page',
                'pageId': resources.first['id'],
                'pageIndex': 0,
                'offset': 0.0,
              },
      });
    }
  });
  @override
  Future<void> saveCollection(
    CatalogCollection collection, {
    Map<String, dynamic>? preferences,
  }) => update(collection.id, (d) {
    if (preferences != null) _preferences(collection.id, preferences);
    final id = collection.id;
    final rows = d.catalog['collections'] as List;
    final index = rows.indexWhere((r) => r['id'] == id);
    if (index < 0) {
      if (preferences != null) throw StateError('Collection no longer exists');
      rows.add(_collection(collection));
    } else {
      rows[index] = _collection(collection);
    }
    if (preferences != null) {
      final prefs = d.management['collections'] as List;
      final current = prefs.where((r) => r['collectionId'] == id).firstOrNull;
      prefs.removeWhere((r) => r['collectionId'] == id);
      prefs.add({
        'collectionId': id,
        'layout': 'grid',
        'sort': 'title',
        'openAction': 'details',
        ...?current as Map?,
        ...preferences,
      });
    }
  });
  @override
  Future<void> saveList(
    String owner,
    String id,
    String name,
    List<String> titles,
  ) => update(owner, (d) {
    final rows = d.management.putIfAbsent('lists', () => <dynamic>[]) as List;
    rows.removeWhere((r) => r['collectionId'] == owner && r['id'] == id);
    rows.add({
      'collectionId': owner,
      'id': id,
      'name': name,
      'titles': titles.toSet().toList(),
    });
  });
  @override
  Future<void> deleteList(String owner, String id) => update(owner, (d) {
    (d.management['lists'] as List? ?? []).removeWhere(
      (r) => r['collectionId'] == owner && r['id'] == id,
    );
  });
  @override
  Future<void> createCollection(
    CatalogCollection row, {
    Map<String, dynamic>? preferences,
  }) => update(row.id, (d) {
    if (preferences != null) _preferences(row.id, preferences);
    final id = row.id;
    if ((d.catalog['collections'] as List).any((c) => c['id'] == id)) {
      throw StateError('Collection already exists');
    }
    (d.catalog['collections'] as List).add(_collection(row));
    if (preferences != null) {
      (d.management['collections'] as List).add({
        'collectionId': id,
        ...preferences,
      });
    }
  });
  @override
  Future<void> group(
    String collection,
    String groupId,
    String name,
    List<String> titleIds,
  ) => update(collection, (d) {
    final owner = (d.catalog['collections'] as List).singleWhere(
      (r) => r['id'] == collection,
    );
    final groups = d.catalog['groups'] as List;
    if (!groups.any(
      (g) => g['collectionId'] == collection && g['id'] == groupId,
    )) {
      groups.add({
        'collectionId': collection,
        'id': groupId,
        'subtype': owner['subtype'],
        'metadata': ReadingMetadata(title: name).toJson(),
      });
    }
    final members = d.catalog['memberships'] as List;
    members.removeWhere(
      (m) => m['collectionId'] == collection && titleIds.contains(m['titleId']),
    );
    final remaining =
        members
            .where(
              (m) =>
                  m['collectionId'] == collection && m['parentId'] == groupId,
            )
            .toList()
          ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    for (var i = 0; i < remaining.length; i++) {
      remaining[i]['order'] = i;
    }
    final count = remaining.length;
    for (var i = 0; i < titleIds.length; i++) {
      d.row(CatalogIdentity(collection, titleIds[i], CatalogEntityKind.title));
      members.add({
        'collectionId': collection,
        'parentId': groupId,
        'titleId': titleIds[i],
        'order': count + i,
      });
    }
  });
  @override
  Future<void> restorePageNote(String collection, ReadingPageNote value) =>
      update(collection, (d) {
        final note = {
          'id': value.id,
          'collectionId': value.collectionId,
          'titleId': value.titleId,
          'sourceId': value.sourceId,
          'sourceRevision': value.sourceRevision,
          'pageId': value.pageId,
          'pageIndex': value.pageIndex,
          'offset': value.offset,
          'kind': value.kind,
          'note': value.note,
          'label': value.label,
        };
        if (note['collectionId'] != collection) {
          throw StateError('Page note owner mismatch');
        }
        final rows = d.management['pageNotes'] as List;
        if (!rows.any((n) => n['id'] == note['id'])) {
          rows.add(Map<String, dynamic>.from(note));
        }
      });
  @override
  Future<void> restoreFinished(
    String collection,
    Map<CatalogIdentity, bool> before,
    bool expected,
  ) => update(collection, (d) {
    if (before.keys.any(
      (id) =>
          id.collectionId != collection || id.kind != CatalogEntityKind.title,
    )) {
      throw StateError('Progress owner mismatch');
    }
    for (final row in d.catalog['progress'] as List) {
      final id = CatalogIdentity(
        row['collectionId'] as String,
        row['id'] as String,
        CatalogEntityKind.title,
      );
      if (before.containsKey(id) && row['finished'] == expected) {
        row['finished'] = before[id];
      }
    }
  });
  @override
  Future<void> role(CatalogIdentity id, ReadingRole role) =>
      update(id.collectionId, (d) => d.row(id)['role'] = role.name);
  @override
  Future<void> saveSpace(String collection, Map<String, dynamic> display) =>
      update(collection, (d) {
        ReadingManagement.validateDisplay(display);
        final rows =
            d.management.putIfAbsent('spaces', () => <dynamic>[]) as List;
        rows.removeWhere((r) => r['collectionId'] == collection);
        rows.add({'collectionId': collection, 'display': display});
      });

  void _preferences(String owner, Map<String, dynamic> values) {
    if (values.containsKey('collectionId') && values['collectionId'] != owner) {
      throw StateError('Preference owner mismatch');
    }
  }
}
