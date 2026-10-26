import '../catalog/domain/classification.dart';
import '../catalog/domain/catalog_models.dart';
import '../features/metadata/application/metadata_batch_journal.dart';

import 'dart:async';

import 'reading_document_draft.dart';
import 'reading_document_transaction.dart';

import 'dart:convert';

import '../features/catalog/application/reading_catalog_ports.dart';
import '../core/persistence/state_repository.dart';
import '../library/library_service.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_codec.dart';
import 'domain/reading_index.dart';
import 'domain/reading_management.dart';
import 'reading_changes.dart';

class LegacyReadingCatalogStore implements ReadingCatalogStore {
  LegacyReadingCatalogStore(this.service);
  final LibraryService service;
  Object get owner => service.persistenceOwner;
  Future<Map<String, dynamic>> _snapshot() async => jsonDecode(
    (await service.transport.invokeMethod<String>('readingSnapshot'))!,
  ) as Map<String, dynamic>;
  @override
  Future<ReadingBundle> read() async {
    final raw = await _snapshot();
    final catalog = raw['catalog'] == null
        ? ReadingCatalog()
        : ReadingCodec.decode(raw['catalog'] as Map<String, dynamic>);
    final index = ReadingIndex(
      raw['index'] as Map<String, dynamic>? ?? ReadingIndex.empty(),
      catalog,
    );
    final management = ReadingManagement(
      raw['management'] as Map<String, dynamic>? ?? ReadingManagement.empty(),
      catalog,
    );
    final doc = management.json;
    Iterable<Map<String, dynamic>> rows(String key) =>
        (doc[key] as List? ?? []).cast<Map<String, dynamic>>();
    return ReadingBundle(
      catalog,
      ReadingIndexView(
        [
          for (final e
              in (index.json['entries'] as List).cast<Map<String, dynamic>>())
            ReadingEvidence(
              id: CatalogIdentity(
                e['collectionId'],
                e['id'],
                CatalogEntityKind.title,
              ),
              rootUri: e['rootUri'],
              cover: e['cover'],
              encoding: e['encoding'],
              manualCover: e['manualCover'],
              manualFields: (e['manualFields'] as List).cast<String>(),
            ),
        ],
        [
          for (final r in index.json['roots'] as List)
            ReadingRootHealth(r['collectionId'], r['uri'], r['complete']),
        ],
      ),
      ReadingManagementView(
        entities: [
          for (final e in rows('entities'))
            ReadingEntityView(
              id: CatalogIdentity(
                e['collectionId'],
                e['id'],
                CatalogEntityKind.values.byName(e['kind']),
              ),
              tags: (e['tags'] as List).cast<String>(),
              manualFields: (e['manualFields'] as List).cast<String>(),
              cover: e['cover'],
              coverMode: e['coverMode'],
              manualCover: e['manualCover'],
              provider: e['provider'],
              candidateId: e['candidateId'],
              lastOpened: e['lastOpened'] ?? 0,
            ),
        ],
        collections: [
          for (final c in rows('collections'))
            ReadingBrowseView(
              collectionId: c['collectionId'],
              layout: c['layout'],
              sort: c['sort'],
              openAction: c['openAction'],
              cardSize: (c['cardSize'] as num?)?.toDouble(),
              formats: (c['formats'] as List?)?.cast<String>(),
            ),
        ],
        lists: [
          for (final r in rows('lists'))
            ReadingListView(
              r['collectionId'],
              r['id'],
              r['name'],
              (r['titles'] as List).cast<String>(),
            ),
        ],
        spaces: [
          for (final r in rows('spaces'))
            ReadingSpaceView(
              r['collectionId'],
              source: r['display']['source'],
              artwork: r['display']['artwork'],
              counts: r['display']['counts'],
              confirmExit: r['display']['confirmExit'],
              hideWatched: r['display']['hideWatched'],
              startTab: r['display']['startTab'],
              pins: (r['display']['pins'] as List).cast<String>(),
            ),
        ],
        pageNotes: [
          for (final n in rows('pageNotes'))
            ReadingPageNote(
              id: n['id'],
              collectionId: n['collectionId'],
              titleId: n['titleId'],
              sourceId: n['sourceId'],
              sourceRevision: n['sourceRevision'],
              pageId: n['pageId'],
              pageIndex: n['pageIndex'],
              offset: (n['offset'] as num).toDouble(),
              kind: n['kind'],
              note: n['note'],
              label: n['label'],
            ),
        ],
        jobs: [
          for (final j in rows('jobs'))
            ReadingJobView(
              j['collectionId'],
              j['provider'],
              j['done'],
              j['total'],
              (j['remaining'] as List).cast<String>(),
              [
                for (final e in j['entries'])
                  ReadingJobEntryView(e['id'], e['status']),
              ],
              MetadataBatchJournal(
                implementationEpoch: j['implementationEpoch'] as String? ?? '',
                done: j['done'],
                total: j['total'],
                remaining: (j['remaining'] as List).cast<String>(),
                entries: {
                  for (final e in j['entries'])
                    e['id'] as String: Map<String, dynamic>.from(e),
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Future<void> update(
    String collection,
    FutureOr<void> Function(ReadingTransaction transaction) change, {
    required void Function() checkAccess,
  }) => MutationCoordinator.forOwner(owner).run(ReadingCodec.key, () async {
    checkAccess();
    final raw = await _snapshot();
    final draft = ReadingDocumentDraft(
      ReadingIndex.copy(
        raw['catalog'] as Map<String, dynamic>? ??
            ReadingCodec.encode(ReadingCatalog()),
      ),
      ReadingIndex.copy(
        raw['index'] as Map<String, dynamic>? ?? ReadingIndex.empty(),
      ),
      ReadingIndex.copy(
        raw['management'] as Map<String, dynamic>? ?? ReadingManagement.empty(),
      ),
    );
    final transaction = ReadingDocumentTransaction(collection, draft);
    try {
      await change(transaction);
    } finally {
      transaction.close();
    }
    checkAccess();
    final catalog = ReadingCodec.decode(draft.catalog);
    ReadingIndex(draft.index, catalog);
    ReadingManagement(draft.management, catalog);
    await service.transport.invokeMethod<void>(
      'commitReadingManagement',
      jsonEncode({
        'collectionId': collection,
        'expectedCatalog': raw['catalog'],
        'expectedIndex': raw['index'],
        'expectedManagement': raw['management'],
        'catalog': draft.catalog,
        'index': draft.index,
        'management': draft.management,
      }),
    );
    ReadingChanges.forOwner(service.persistenceOwner).changed();
  });
}
