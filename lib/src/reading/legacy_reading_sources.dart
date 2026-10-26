import '../features/sources/application/reading_scan_plan.dart';
import 'reading_document_scan_plan.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_index.dart';

import 'dart:convert';

import '../features/sources/application/reading_source_ports.dart';
import '../features/sources/application/source_ports.dart';
import '../core/persistence/state_repository.dart';
import '../library/library_models.dart';
import '../library/library_service.dart';
import 'domain/reading_codec.dart';
import 'reading_changes.dart';

class LegacyReadingSources implements ReadingSources {
  LegacyReadingSources(this.service);
  final _generations = Expando<int>();
  final _plans = Expando<ReadingDocumentPlan>();
  final LibraryService service;
  @override
  Stream<ScanProgressEvent> get progress => service.scanEvents;
  Future<Map<String, dynamic>> _snapshot() async => jsonDecode(
    (await service.transport.invokeMethod<String>('readingSnapshot'))!,
  ) as Map<String, dynamic>;
  Future<Map<String, dynamic>> _discover(Map<String, dynamic> request) async =>
      jsonDecode(
        (await service.transport.invokeMethod<String>(
          'discoverReading',
          request,
        ))!,
      ) as Map<String, dynamic>;
  void _access() {
    service.maintenance.checkAdmission();
  }

  ReadingScanPreview _issue(ReadingDocumentPlan plan, String request) {
    _access();
    final result = ReadingScanPreview(
      collectionId: plan.collectionId,
      requestId: request,
      complete: plan.complete,
      added: plan.added,
      relinked: plan.relinked,
      missing: plan.missing,
      warnings: plan.warnings,
      unresolved: plan.unresolved,
      titles: ReadingCodec.decode(plan.catalog).titles
          .where((t) => t.catalog.id.collectionId == plan.collectionId),
      sources: [
        for (final source in plan.discovery['sources'] as List)
          ReadingScanSource(
            key: source['sourceKey'] as String,
            name: source['name'] as String,
            series: source['series'] as String,
            resources: (source['readingOrder'] as List).map(
              ReadingResource.fromJson,
            ),
          ),
      ],
    );
    _plans[result] = plan;
    _generations[result] = service.maintenance.generation;
    return result;
  }

  ReadingDocumentPlan _plan(ReadingScanPreview preview) {
    _access();
    if (_generations[preview] != service.maintenance.generation) {
      throw StateError('Scan generation expired');
    }
    return _plans[preview] ??
        (throw StateError(
          'Scan preview belongs to another source or has expired',
        ));
  }

  @override
  Future<ReadingScanPreview> prepare(
    ReadingScanRequest request, {
    required void Function() checkAccess,
  }) async {
    checkAccess();
    _access();
    final generation = service.maintenance.generation;
    final raw = await _snapshot();
    checkAccess();
    if (generation != service.maintenance.generation) {
      throw StateError('Scan generation expired');
    }
    _access();
    final catalog = raw['catalog'] as Map<String, dynamic>?;
    final model = catalog == null
        ? ReadingCatalog()
        : ReadingCodec.decode(catalog);
    final collection =
        (ReadingCodec.encode(model)['collections'] as List).singleWhere(
          (row) => row['id'] == request.collectionId,
        ) as Map<String, dynamic>;
    for (final root in collection['roots'] as List) {
      root['uri'] =
          request.choices.rootReplacements[root['uri']] ?? root['uri'];
    }
    final discovery = await _discover({
      'id': request.collectionId,
      'requestId': request.requestId,
      'collection': collection,
      'encoding': request.encoding,
      'encodings': request.encodings,
    });
    checkAccess();
    _access();
    if (generation != service.maintenance.generation ||
        discovery['requestId'] != request.requestId) {
      throw StateError('Scan request mismatch');
    }
    final choices = request.choices;
    return _issue(
      ReadingScanPlanner.preview(
        catalog,
        raw['index'] as Map<String, dynamic>?,
        discovery,
        rootReplacements: choices.rootReplacements,
        relinks: choices.relinks,
        grouping: choices.grouping,
        resourceOrder: choices.resourceOrder,
        titleOrder: choices.titleOrder,
      ),
      request.requestId,
    );
  }

  @override
  ReadingScanPreview revise(
    ReadingScanPreview preview,
    ReadingScanChoices choices,
  ) {
    final plan = _plan(preview);
    return _issue(
      ReadingScanPlanner.preview(
        plan.beforeCatalog,
        plan.beforeIndex,
        plan.discovery,
        rootReplacements: plan.rootReplacements,
        relinks: choices.relinks,
        grouping: choices.grouping,
        resourceOrder: choices.resourceOrder,
        titleOrder: choices.titleOrder,
      ),
      preview.requestId,
    );
  }

  @override
  Future<void> cancel(String requestId) =>
      service.transport.invokeMethod<void>('cancelReadingScan', requestId);
  @override
  Future<void> commit(
    ReadingScanPreview preview, {
    required void Function() checkAccess,
  }) =>
      MutationCoordinator.forOwner(service.persistenceOwner)
          .run(ReadingCodec.key, () async {
            checkAccess();
            final plan = _plan(preview);
            if (!plan.canApply) throw StateError('Incomplete scan');
            ReadingIndex(plan.index, ReadingCodec.decode(plan.catalog));
            final proposal = {
              'collectionId': plan.collectionId,
              'expectedCatalog': plan.beforeCatalog,
              'expectedIndex': plan.beforeIndex,
              'catalog': plan.catalog,
              'index': plan.index,
            };
            await service.transport.invokeMethod<void>(
              'commitReadingScan',
              jsonEncode(proposal),
            );
            _plans[preview] = null;
            ReadingChanges.forOwner(service.persistenceOwner).changed();
          });
  @override
  Future<LibraryRoot?> pickRoot() => service.pickRoot();
  @override
  Future<void> releaseRoots(List<String> uris) => service.releaseRoots(uris);
}
