import 'package:multiplexr/src/core/application/mutations.dart';

import '../features/plugins/application/contribution_registry.dart';
import '../features/plugins/application/installed_metadata.dart';
import '../features/metadata/application/registry_provider.dart';

import 'package:multiplexr/src/features/metadata/application/metadata_workflow.dart';

import 'plugin_assembly.dart';
import '../experience/plugins/plugin_manager.dart';
import 'audio_assembly.dart';

import 'package:multiplexr/src/bootstrap/metadata_assembly.dart';

import 'settings_assembly.dart';
import 'reading_assembly.dart';
import 'library_assembly.dart';
import '../core/platform/local_artwork_images.dart';
import '../media/artwork_images.dart';
import '../experience/app_session_scope.dart';
import '../core/persistence/job_receipt_store.dart';
import '../domain/access/collection_session_access.dart';
import '../catalog/domain/classification.dart';
import '../core/application/clock.dart';
import '../core/platform/system_clock.dart';
import '../features/catalog/application/load_library.dart';
import '../library/library_controller.dart';
import '../library/library_repository.dart';
import '../library/library_service.dart';
import '../library/legacy_collection_sources.dart';
import '../library/legacy_collection_spaces.dart';
import '../library/legacy_player_preferences.dart';
import '../features/settings/application/player_preferences.dart';
import '../media/music_metadata.dart';
import '../media/music_repository.dart';
import '../platform_service.dart';
import '../reading/reading_app_controller.dart';
import '../settings.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../library/legacy_extension_catalog.dart';

/// Composition root for application ports and supported native persistence/engines.
class AppComposition {
  final LocalArtworkImage localArtwork = localArtworkImage;
  factory AppComposition({
    PlatformService platform = const PlatformService(),
    LibraryService libraryService = const LibraryService(),
    LibraryRepository? repository,
    Clock clock = const SystemClock(),
  }) {
    libraryService.maintenance.jobs.configure(LocalJobReceipts(libraryService));
    appSubtypes.validateBindings(
      collectionRoutes: {
        MediaSubtype.moviesTv,
        MediaSubtype.videos,
        MediaSubtype.audiobooks,
        MediaSubtype.music,
        MediaSubtype.ebook,
        MediaSubtype.comics,
      },
      engines: {
        MediaEngineKind.video,
        MediaEngineKind.audio,
        MediaEngineKind.reader,
      },
    );
    PluginManager? pluginOwner;
    MetadataWorkflow workflow() => MetadataWorkflow.dynamic(
      () => [
        for (final contribution
            in pluginOwner?.registry.family('metadata.provider') ??
                <PluginContribution>[])
          InstalledMetadataProvider(
            contribution,
            pluginOwner!.invokeContribution,
            [],
          ),
      ],
      commitAuthority: (candidate, operation) =>
          pluginOwner!.commitMetadata(candidate, operation),
      mutations: const OwnerApplicationMutations(),
    );
    LibraryController? libraryOwner;
    final port =
        repository ??
        LegacyLibraryRepository(
          libraryService,
          authorized: (id) => libraryOwner?.canAccessCollection(id) ?? false,
        );
    final settings = createSettingsController(platform, clock: clock.now);
    final audio = createAudioController(
      maintenance: libraryService.maintenance,
    );
    final library = createLibraryController(
      libraryService,
      audio: audio,
      repository: port,
      loadLibrary: LoadLibrary(port),
      access: CollectionSessionAccess(),
      sources: LegacyCollectionSources(libraryService),
      spaceStore: LegacyCollectionSpaces(libraryService),
      playerPreferences: PlayerPreferences(
        LegacyPlayerPreferenceStore(libraryService),
      ),
      audiobookFactory: (id, authorized) => createAudioLibrary(
        libraryService,
        collectionId: id,
        authorized: authorized,
        audio: audio,
        metadataWorkflow: workflow,
      ),
      authenticate: platform.authenticate,
      clock: clock,
      metadataWorkflow: workflow,
    );
    libraryOwner = library;
    final composition = AppComposition._(
      platform,
      libraryService,
      settings,
      library,
      workflow,
    );
    pluginOwner = composition.plugins;
    return composition;
  }
  AppComposition._(
    this.platform,
    this.libraryService,
    this.settings,
    this.library,
    this.metadataWorkflow,
  );
  final PlatformService platform;
  final LibraryService libraryService;
  final SettingsController settings;
  final LibraryController library;
  final MetadataWorkflow Function() metadataWorkflow;

  /// Scoped catalog boundary consumed by the installed plugin capability gateway.
  late final extensionCatalog = ExtensionCatalogQueries(
    LegacyExtensionCatalog(library, sessions.reading),
    generation: () => libraryService.maintenance.generation,
  );
  PluginManager? _plugins;
  PluginManager get plugins => _plugins ??= createPluginManager(
    metadataWorkflow: metadataWorkflow,
    library: library,
    reading: sessions.reading,
    settings: settings,
    catalog: extensionCatalog,
  );
  AppSessionScope? _sessions;
  bool _disposed = false;
  AppSessionScope get sessions {
    if (_disposed) throw StateError('Application composition was disposed.');
    return _sessions ??= createSessions(
      settings: settings,
      library: library,
      metadataWorkflow: metadataWorkflow,
    );
  }

  static AppSessionScope createSessions({
    required SettingsController settings,
    required LibraryController library,
    MetadataWorkflow Function()? metadataWorkflow,
  }) {
    final repository = MusicRepository(library);
    final sessions = AppSessionScope(
      music: createMusicPlayback(
        library: library,
        repository: repository,
        audio: library.audio,
        disposeAudio: false,
        metadataProvider: metadataWorkflow == null
            ? null
            : RegistryMusicProvider(metadataWorkflow),
        metadataJobFactory: (id) => createMusicMetadataJob(
          repository,
          id,
          metadataWorkflow == null
              ? NoInstalledMusicProvider()
              : RegistryMusicProvider(metadataWorkflow),
        ),
      ),
      reading: ReadingAppController(
        library.service,
        authenticate: settings.platform.authenticate,
        appBlocked: () => settings.locked || settings.covered,
        libraryFactory: (authorized) => createReadingLibrary(
          library.service,
          authorized: authorized,
          collectionForms: library,
          metadataProvider: metadataWorkflow == null
              ? null
              : RegistryPublicationProvider(metadataWorkflow),
        ),
      ),
    );
    library.otherJobsRunning = () =>
        library.audio.state.playing ||
        sessions.music.metadataRunning ||
        sessions.reading.library.metadataJobs.registry.running ||
        sessions.reading.library.autoScans.running.isNotEmpty;
    return sessions;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _plugins?.dispose();
    _sessions?.dispose();
    settings.dispose();
    library.dispose();
  }
}
