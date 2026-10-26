import 'audiobook_metadata_job.dart';
import '../features/catalog/application/audiobook_catalog_ports.dart';
import '../features/sources/application/source_ports.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import '../features/metadata/application/audiobook_metadata_host.dart';
import '../features/catalog/application/audiobook_catalog_commands.dart';
import '../features/sources/application/media_imports.dart';
import '../library/library_service.dart';
import '../library/library_models.dart';
import 'contracts.dart';
import 'audio_player.dart';
import '../features/settings/application/player_preferences.dart';
import '../core/application/maintenance.dart';
import '../features/settings/application/user_preferences.dart';
import 'storage.dart';
export '../features/catalog/application/audiobook_catalog_commands.dart';

class AudioLibrary extends AudiobookCatalogCommands
    implements AudiobookMetadataHost {
  @override
  AudiobookCatalogCommands get commands => this;
  final MetadataWorkflow metadataSearch;
  final AudiobookMetadataJob Function(String?) metadataJobFactory;
  MediaImports get imports => service.imports;
  AudioLibrary(
    this.service, {
    super.collectionId,
    super.authorized,
    required this.audio,
    required this.metadataJobFactory,
    required AudiobookCatalogStore store,
    required this.progress,
    required this.metadataSearch,
    required this.artworkDownload,
    required this.playerPreferences,
    required this.sources,
  }) : super(store);
  final Future<String> Function(String, String) artworkDownload;
  final CollectionSources sources;
  final LibraryService service;
  final AudioController audio;
  @override
  Object get owner => service.persistenceOwner;
  Maintenance get maintenance => service.maintenance;
  UserPreferences get userPreferences => service.userPreferences;
  final MediaStorage progress;
  @override
  Future<String> downloadArtwork(String location, String provider) =>
      artworkDownload(location, provider);
  final PlayerPreferences playerPreferences;
  Future<List<String>> scanSources(String id, {required String requestId}) =>
      maintenance.activity(
        () => maintenance.jobs.run(
          'scan:audiobook:$id',
          [id],
          () => sources.scan(
            VideoCollection(
              id: id,
              name: id,
              kind: MediaKind.audiobook,
              subtype: VideoSubtype.videos,
            ),
            requestId: requestId,
            authorized: () => canAccess(id),
            cancelled: () => false,
          ),
        ),
      );
  static const key = 'audio:library';
}
