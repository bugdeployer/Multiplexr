import '../core/application/maintenance.dart';
import '../features/settings/application/reader_preference_commands.dart';
import 'reading_metadata_host.dart';
import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../features/sources/application/reading_scan_jobs.dart';
import '../features/sources/application/media_imports.dart';
import 'reading_changes.dart';
import 'ebook_opening_host.dart';
import 'reading_annotations_repository.dart';
import 'reading_metadata_jobs.dart';

import 'dart:typed_data';
import 'dart:convert';

import '../features/catalog/application/reading_catalog_commands.dart';
import '../features/sources/application/reading_source_ports.dart';
import '../features/sources/application/reading_scan_workflow.dart';
import '../core/application/clock.dart';
import '../library/library_service.dart';
import '../library/library_controller.dart';
import '../library/library_models.dart' show LibraryRoot;
export '../features/catalog/application/reading_catalog_commands.dart';

/// Compatibility adapter for readers/metadata; catalog orchestration is pure.
class ReadingLibrary extends ReadingCatalogCommands
    implements ReadingMetadataHost {
  @override
  ReadingCatalogCommands get commands => this;
  final EbookOpeningHost readerHost;

  /// Adapter for the existing form model; application commands receive entities.
  CatalogCollection collectionFromForm(Map<String, dynamic> row) =>
      CatalogCollection(
        id: row['id'] as String,
        name: row['name'] as String,
        subtype: MediaSubtype.values.byName(row['subtype'] as String),
        access: CatalogAccess(
          locked: row['locked'] as bool,
          includeInGlobal: row['includeInGlobal'] as bool,
        ),
        roots: [
          for (final root in row['roots'] as List)
            CatalogRoot(
              uri: root['uri'] as String,
              name: root['name'] as String,
            ),
        ],
      );
  final ReaderPreferenceCommands readerPreferences;
  MediaImports get imports => service.imports;
  ReadingLibrary(
    this.service, {
    required super.authorized,
    required this.sources,
    required ReadingCatalogStore store,
    required this.collectionForms,
    required this.releaseCollectionForms,
    required this.readerHost,
    required this.readerPreferences,
    required this.annotations,
    required this.metadataJobsFactory,
    required this.clock,
  }) : super(store);
  final LibraryController Function() collectionForms;
  final void Function() releaseCollectionForms;
  final ReadingMetadataJobs Function() metadataJobsFactory;

  late final autoScans = ReadingScanJobs(
    createScan,
    maintenance: service.maintenance,
    authorized: authorized,
    changed: () => ReadingChanges.forOwner(owner).changed(),
  );
  final ReadingAnnotationsRepository annotations;
  late final metadataJobs = metadataJobsFactory();
  final LibraryService service;
  @override
  Maintenance get maintenance => service.maintenance;
  @override
  Object get owner => service.persistenceOwner;
  Future<int> cacheBytes() async {
    final raw = await service.transport.invokeMethod<String>(
      'readingCacheInfo',
    );
    return (jsonDecode(raw!) as Map)['bytes'] as int;
  }

  Future<void> clearIdleCache() =>
      service.transport.invokeMethod<void>('clearReadingIdleCache');
  final ReadingSources sources;
  final Clock clock;
  ReadingScanWorkflow createScan() {
    final generation = service.maintenance.generation;
    return ReadingScanWorkflow(
      sources,
      authorized: (id) =>
          service.maintenance.isCurrent(generation) && authorized(id),
      clock: clock,
    );
  }

  Future<LibraryRoot?> pickRoot() => sources.pickRoot();
  Future<void> releaseRoots(List<String> uris) => sources.releaseRoots(uris);
  Future<Uint8List> artworkBytes(String reference) async => (await service
      .transport
      .invokeMethod<Uint8List>('readReadingArtwork', reference))!;
  @override
  Future<String> storeArtwork(Uint8List bytes) async => (await service.transport
      .invokeMethod<String>('storeReadingArtwork', bytes))!;
}
