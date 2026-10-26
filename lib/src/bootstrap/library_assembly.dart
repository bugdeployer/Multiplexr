import 'package:multiplexr/src/core/application/mutations.dart';

import '../features/metadata/application/publication_provider.dart';
import 'audio_assembly.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../metadata/metadata_targets.dart';

import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';

import '../media/legacy_audiobook_catalog_store.dart';
import '../media/storage.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import '../media/music_playback.dart';
import '../media/music_metadata.dart';
import '../media/music_metadata_job.dart';
import '../media/legacy_music_session_store.dart';
import '../features/playback/application/music_session_store.dart';
import '../library/library_controller.dart';
import '../library/library_service.dart';
import '../library/library_repository.dart';
import '../library/legacy_collection_sources.dart';
import '../library/legacy_collection_spaces.dart';
import '../library/legacy_player_preferences.dart';
import '../library/legacy_video_playback_host.dart';
import '../library/legacy_video_artwork.dart';
import '../library/legacy_activity_source.dart';
import '../library/legacy_backup_port.dart';
import '../library/library_metadata_jobs.dart';
import '../features/catalog/application/load_library.dart';
import '../features/sources/application/source_ports.dart';
import '../features/catalog/application/collection_spaces.dart';
import '../features/settings/application/player_preferences.dart';
import '../domain/access/collection_session_access.dart';
import '../core/application/clock.dart';
import '../core/platform/system_clock.dart';
import '../media/audio_library.dart';
import '../media/audio_player.dart';
import '../media/music_repository.dart';
import '../platform_service.dart';

LibraryController createLibraryController(
  LibraryService service, {
  LibraryRepository? repository,
  LoadLibrary? loadLibrary,
  CollectionSessionAccess? access,
  CollectionSources? sources,
  CollectionSpaceStore? spaceStore,
  PlayerPreferences? playerPreferences,
  AudioLibrary Function(String?, bool Function(String))? audiobookFactory,
  AudioController? audio,
  Future<bool> Function()? authenticate,
  Clock clock = const SystemClock(),
  MetadataWorkflow Function()? metadataWorkflow,
}) {
  late LibraryController owner;
  final engine =
      audio ?? createAudioController(maintenance: service.maintenance);
  final port =
      repository ??
      LegacyLibraryRepository(
        service,
        authorized: (id) => owner.canAccessCollection(id),
      );
  owner = LibraryController(
    service,
    repository: port,
    loadLibrary: loadLibrary,
    access: access,
    sources: sources ?? LegacyCollectionSources(service),
    spaceStore: spaceStore ?? LegacyCollectionSpaces(service),
    playerPreferences:
        playerPreferences ??
        PlayerPreferences(LegacyPlayerPreferenceStore(service)),
    audiobookFactory:
        audiobookFactory ??
        ((id, authorized) => createAudioLibrary(
          service,
          collectionId: id,
          authorized: authorized,
          audio: engine,
          metadataWorkflow: metadataWorkflow,
        )),
    audio: engine,
    authenticate: authenticate ?? const PlatformService().authenticate,
    clock: clock,
    videoPlayback: LegacyVideoPlaybackHost(service),
    artworkPort: LegacyVideoArtwork(service),
    backupPort: (authentication) =>
        LegacyBackupPort(owner, authentication: authentication),
    activitySource: () => LegacyActivitySource(owner),
    musicRepositoryFactory: () => MusicRepository(owner),
    metadataJobsFactory: () => LibraryMetadataJobs(
      owner,
      search:
          metadataWorkflow?.call() ??
          MetadataWorkflow([], mutations: const OwnerApplicationMutations()),
      createSeriesJob: (series) => createSeriesMetadataJob(
        owner,
        series,
        workflow: metadataWorkflow?.call(),
      ),
      createVideoJob: (collection) => createMetadataJob(
        owner,
        collection,
        workflow: metadataWorkflow?.call(),
      ),
      createAudiobookJob: (id) => createAudiobookMetadataJob(
        owner.audiobookCatalog(collectionId: id),
        collectionId: id,
        workflow: metadataWorkflow?.call(),
      ),
      createTarget: (asset) => VideoMetadataTarget(
        service: service,
        asset: asset,
        access: () => owner.canAccessCollection(asset.collectionId),
        latest: () async {
          await owner.load();
          return owner
                  .indexedItems(asset.collectionId)
                  .where((a) => a.id == asset.id)
                  .firstOrNull ??
              (throw const MetadataFailure(
                MetadataFailureKind.unavailable,
                'This title no longer exists.',
              ));
        },
      ),
    ),
  );
  return owner;
}

MusicPlayback createMusicPlayback({
  required LibraryController library,
  AudioController? audio,
  MusicRepository? repository,
  MusicSessionStore? sessionStore,
  MusicMetadataJob Function(String)? metadataJobFactory,
  bool? disposeAudio,
  MusicProvider? metadataProvider,
}) {
  final catalog = repository ?? MusicRepository(library);
  final provider = metadataProvider ?? NoInstalledMusicProvider();
  return MusicPlayback(
    library: library,
    audio: audio ?? library.audio,
    repository: catalog,
    sessionStore: sessionStore ?? LegacyMusicSessionStore(library.service),
    metadataProvider: provider,
    metadataJobFactory:
        metadataJobFactory ??
        ((id) => createMusicMetadataJob(catalog, id, provider)),
    disposeAudio: disposeAudio ?? audio != null,
  );
}

AudioLibrary createAudioLibrary(
  LibraryService service, {
  Future<String> Function(String, String)? artworkDownload,
  String? collectionId,
  bool Function(String)? authorized,
  AudioController? audio,
  MetadataWorkflow Function()? metadataWorkflow,
}) {
  late AudioLibrary library;
  library = AudioLibrary(
    service,
    collectionId: collectionId,
    authorized: authorized,
    audio: audio ?? createAudioController(maintenance: service.maintenance),
    store: LegacyAudiobookCatalogStore(service),
    progress: MediaStorage(service),
    metadataSearch:
        metadataWorkflow?.call() ??
        MetadataWorkflow([], mutations: const OwnerApplicationMutations()),
    artworkDownload:
        artworkDownload ??
        (url, provider) async => throw const MetadataFailure(
          MetadataFailureKind.unavailable,
          'Choose artwork through an installed artwork provider.',
        ),
    playerPreferences: PlayerPreferences(LegacyPlayerPreferenceStore(service)),
    sources: LegacyCollectionSources(service),
    metadataJobFactory: (id) => createAudiobookMetadataJob(
      library,
      collectionId: id,
      workflow: metadataWorkflow?.call(),
    ),
  );
  return library;
}
