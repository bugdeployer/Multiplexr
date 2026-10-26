import 'library_adapter_host.dart';
import '../features/backup/application/backup_workflow.dart';
import '../features/sources/application/media_imports.dart';
import '../features/metadata/application/video_artwork.dart';
import '../features/jobs/application/activity_queries.dart';
import '../media/music_repository.dart';
import 'library_metadata_jobs.dart';
import '../features/catalog/application/load_library.dart';
import '../core/application/application_failure.dart';
import '../core/application/request_scope.dart';
import '../core/application/clock.dart';
import '../domain/access/collection_session_access.dart';
import '../features/catalog/application/catalog_commands.dart';
import '../features/catalog/application/catalog_queries.dart';
import '../catalog/domain/classification.dart';
import '../features/sources/application/source_ports.dart';
import '../features/sources/application/scan_collections.dart';
import '../media/audio_library.dart';
import '../media/audio_player.dart';
import '../features/playback/application/video_playback_host.dart';
import '../features/catalog/application/collection_spaces.dart';
import '../features/settings/application/player_preferences.dart';
import '../features/catalog/application/series_groups.dart';
import 'library_service.dart';
import 'library_repository.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'library_models.dart';
import 'series.dart' as series_data;

class LibraryController extends ChangeNotifier implements LibraryAdapterHost {
  @override
  bool get metadataRunning => metadataJobs.registry.running;
  MediaImports get imports => service.imports;
  late final videoArtwork = VideoArtwork(
    artworkPort,
    maintenance: service.maintenance,
    authorized: canAccessCollection,
    items: items,
    reload: load,
  );
  LibraryController(
    this.service, {
    required this.repository,
    LoadLibrary? loadLibrary,
    CollectionSessionAccess? access,
    required CollectionSources sources,
    required CollectionSpaceStore spaceStore,
    required this.playerPreferences,
    required AudioLibrary Function(String?, bool Function(String))
    audiobookFactory,
    required this.audio,
    required this.authenticate,
    required this.clock,
    required this.videoPlayback,
    required this.artworkPort,
    required this.backupPort,
    required this.activitySource,
    required this.musicRepositoryFactory,
    required this.metadataJobsFactory,
  }) {
    _loadLibrary = loadLibrary ?? LoadLibrary(repository);
    _access = access ?? CollectionSessionAccess();
    _sources = sources;
    _audiobookFactory = audiobookFactory;
    commands = CatalogCommands(
      repository,
      authorized: (id) => !_disposed && canAccessCollection(id),
      collections: () => collections,
      assets: () => assets,
    );
    spaces = CollectionSpaces(
      spaceStore,
      authorized: (id) => !_disposed && canAccessCollection(id),
    );
    queries = CatalogQueries(
      collections: () => collections,
      assets: () => assets,
      authorized: (id) => !_disposed && canAccessCollection(id),
    );
    scans = ScanCollections(
      _sources,
      clock: clock,
      collection: (id) => collections.where((c) => c.id == id).firstOrNull,
      authorized: (id) => canAccessCollection(id),
      save: commands.save,
      reload: load,
      changed: notifyListeners,
    );
    _detachMaintenance = service.maintenance.register(
      invalidate: () {
        _loadRequests.invalidate();
        _access.relock();
        queue.clear();
        _queueRevision++;
        collections = [];
        assets = [];
        series = [];
        audioCounts = {};
        notifyListeners();
      },
    );
  }
  late final void Function() _detachMaintenance;
  late final Future<bool> Function() authenticate;
  late final CollectionSources _sources;
  late final AudioLibrary Function(String?, bool Function(String))
  _audiobookFactory;
  final _audiobookCatalogs = <String?, AudioLibrary>{};
  final AudioController audio;
  final VideoPlaybackHost videoPlayback;
  final VideoArtworkPort artworkPort;
  final BackupPort Function(Future<bool> Function()) backupPort;
  final ActivitySource Function() activitySource;
  final MusicRepository Function() musicRepositoryFactory;
  final LibraryMetadataJobs Function() metadataJobsFactory;
  @override
  AudioLibrary audiobookCatalog({String? collectionId}) =>
      _audiobookCatalogs.putIfAbsent(
        collectionId,
        () => _audiobookFactory(collectionId, canAccessCollection),
      );
  late final CatalogCommands commands;
  late final CatalogQueries queries;
  late final CollectionSpaces spaces;
  late final PlayerPreferences playerPreferences;
  List<VideoCollection> scopedCollections(
    MediaSubtype subtype, {
    String? collectionId,
  }) => queries.scoped(subtype, collectionId: collectionId);
  late final ScanCollections scans;
  Future<LibraryRoot?> pickRoot() => _sources.pickRoot();
  Future<void> releaseRoots(List<String> uris) => _sources.releaseRoots(uris);
  BackupWorkflow backupWorkflow({
    required Future<bool> Function() authentication,
    required bool Function() active,
  }) =>
      BackupWorkflow(backupPort(authentication), clock: clock, active: active);
  late final activity = ActivityQueries(
    activitySource(),
    collections: () => collections,
    authorized: canAccessCollection,
    scanning: (id) => scanning.contains(id),
    found: (id) => scanProgress[id]?['found'],
    indexed: indexedItems,
  );
  late final musicCatalog = musicRepositoryFactory();
  @override
  bool Function()? otherJobsRunning;
  late final metadataJobs = metadataJobsFactory();
  bool _disposed = false;
  @override
  void dispose() {
    _detachMaintenance();
    _disposed = true;
    _loadRequests.close();
    scans.dispose();
    metadataJobs.registry.dispose();
    audio.dispose();
    super.dispose();
  }

  Map<String, Map<String, dynamic>> get scanProgress => scans.progress;
  @override
  final LibraryService service;
  late final LibraryRepository repository;
  final Clock clock;
  late final LoadLibrary _loadLibrary;
  late final CollectionSessionAccess _access;
  String? get activeCollectionId => _access.activeCollectionId;
  @override
  bool canAccessCollection(String id) =>
      !_disposed &&
      _access.canAccess(
        id,
        locked: collections.any((c) => c.id == id && c.locked),
      );
  void beginCollectionSession(String id) {
    _access.begin(id);
    scans.revokeInaccessible();
    notifyListeners();
  }

  void authorizeCollection(String id) {
    _access.authorize(id);
    notifyListeners();
  }

  void relockCollections() {
    _access.relock();
    scans.revokeInaccessible();
    notifyListeners();
  }

  @override
  void endCollectionSession() {
    _access.end();
    scans.revokeInaccessible();
    notifyListeners();
  }

  @override
  List<VideoCollection> collections = [];
  List<VideoAsset> assets = [];
  Map<String, int> audioCounts = {};
  int collectionItemCount(VideoCollection collection) =>
      collection.locked && !canAccessCollection(collection.id)
      ? 0
      : collection.isAudio
      ? audioCounts[collection.id] ?? 0
      : items(collection.id).length;
  List<series_data.SeriesRecord> series = [];
  final List<String> queue = [];
  int _queueRevision = 0;
  String queueKey(VideoAsset a) => jsonEncode([a.collectionId, a.id]);
  Future<void> _editQueue(void Function(List<String>) edit) async {
    _queueRevision++;
    try {
      final next = await repository.editQueue(edit, fallback: List.of(queue));
      if (_disposed) return;
      queue
        ..clear()
        ..addAll(next);
      notifyListeners();
    } finally {
      _queueRevision++;
    }
  }

  Future<void> enqueue(VideoAsset asset, {bool next = false}) =>
      _editQueue((queue) {
        final key = queueKey(asset);
        queue.remove(key);
        if (next) {
          queue.insert(0, key);
        } else {
          queue.add(key);
        }
      });
  Future<void> reorderQueued(List<VideoAsset> ordered) => _editQueue((queue) {
    final keys = ordered.map(queueKey).toList();
    if (keys.toSet().length != keys.length) {
      throw ArgumentError('Duplicate queue entries');
    }
    final existing = keys.where(queue.contains).toList();
    final wanted = existing.toSet();
    var index = 0;
    for (var i = 0; i < queue.length; i++) {
      if (wanted.contains(queue[i])) queue[i] = existing[index++];
    }
  });
  Future<void> removeQueued(VideoAsset asset) =>
      _editQueue((queue) => queue.remove(queueKey(asset)));
  List<VideoAsset> get queuedVideos => queue
      .map(
        (key) => assets
            .where(
              (a) =>
                  queueKey(a) == key &&
                  a.available &&
                  canAccessCollection(a.collectionId) &&
                  collections.any(
                    (c) =>
                        c.id == a.collectionId &&
                        c.extensions.contains(
                          a.filename.split('.').last.toLowerCase(),
                        ),
                  ),
            )
            .firstOrNull,
      )
      .whereType<VideoAsset>()
      .toList();
  bool ready = false;
  String? error;
  @override
  Set<String> get scanning => scans.running;
  Map<String, List<String>> get warnings => scans.warnings;
  @override
  List<VideoAsset> items(String id) => queries.items(id);
  @override
  List<VideoAsset> indexedItems(String id) => queries.indexed(id);

  @override
  void notifyListeners() {
    if (!_disposed) {
      metadataJobs.registry.refreshAccess();
      super.notifyListeners();
    }
  }

  final _loadRequests = RequestScope();
  @override
  Future<void> load() async {
    if (_disposed) return;
    final request = _loadRequests.begin();
    final queueRevision = _queueRevision;
    try {
      final snapshot = await _loadLibrary(request);
      final nextCollections = snapshot.collections;
      final nextAssets = snapshot.assets;
      if (!request.isCurrent) return;
      final previous = {for (final c in collections) c.id: c};
      collections = List.of(nextCollections);
      for (final c in collections) {
        if (c.locked && previous[c.id]?.locked == false) _access.revoke(c.id);
      }
      scans.revokeInaccessible();
      audioCounts = Map.of(snapshot.audioCounts);
      assets = List.unmodifiable(nextAssets);
      if (queueRevision == _queueRevision && snapshot.queue != null) {
        queue
          ..clear()
          ..addAll(snapshot.queue!);
      }
      series = series_data.buildSeries(
        nextCollections
            .where((c) => c.subtype != VideoSubtype.videos)
            .expand((c) => indexedItems(c.id))
            .toList(),
      );
      try {
        if (snapshot.seriesIndexSupported) {
          await repository.saveSeriesIndex({
            'series': series.map((s) => s.toJson()).toList(),
            'seasons': series
                .expand((s) => s.seasons)
                .map((s) => s.toJson())
                .toList(),
            'episodes': series
                .expand((s) => s.episodes)
                .map((e) => e.toJson())
                .toList(),
          });
        }
      } on MissingPluginException {
        /* Non-Android preview/test adapters may omit materialized indexes. */
      }
      if (!request.isCurrent) return;
      error = null;
    } on ApplicationFailure catch (failure) {
      if (!request.isCurrent) return;
      error = failure.message;
    } catch (_) {
      if (!request.isCurrent) return;
      error = 'Could not load your library. Try again.';
    }
    ready = true;
    notifyListeners();
  }

  Future<void> save(VideoCollection collection) async {
    final previous = collections
        .where((c) => c.id == collection.id)
        .firstOrNull;
    if (scanning.contains(collection.id)) await cancelScan(collection.id);
    await commands.save(collection);
    if (collection.locked && previous?.locked != true) {
      _access.revoke(collection.id);
    }
    if (_disposed) return;
    _loadRequests.invalidate();
    collections = [
      ...collections.where((c) => c.id != collection.id),
      collection,
    ];
    notifyListeners();
    await load();
  }

  Future<void> remove(String id) async {
    if (scanning.contains(id)) await cancelScan(id);
    await commands.remove(id);
    if (_disposed) return;
    _loadRequests.invalidate();
    collections.removeWhere((c) => c.id == id);
    assets = List.unmodifiable(assets.where((a) => a.collectionId != id));
    notifyListeners();
    await load();
  }

  Future<void> cancelScan(String id) => scans.cancel(id);
  @override
  Future<void> scan(String id) => service.maintenance.activity(
    () => service.maintenance.jobs.run('scan:$id', [id], () => scans.scan(id)),
  );
  Future<void> saveBrowsing(String id, Map<String, dynamic> values) async {
    await commands.browsing(id, values);
    await load();
  }

  Future<void> editTags(
    List<VideoAsset> selected, {
    required String operation,
    required List<String> tags,
    String? target,
    String? collectionId,
  }) async {
    await commands.tags(
      selected,
      operation: operation,
      tags: tags,
      target: target,
      collectionId: collectionId,
    );
    await load();
  }

  Future<void> flags(
    List<VideoAsset> selected,
    String action,
    bool value,
  ) async {
    await commands.flags(selected, action, value);
    await load();
  }

  Future<void> watch(VideoAsset asset, String action) async {
    await commands.watch(asset, action);
    await load();
  }

  SeriesGroupRepository seriesGroups(String id) => SeriesGroupRepository(
    read: () async {
      await load();
      return items(id);
    },
    save: correctGrouping,
  );
  Future<void> correctGrouping(List<VideoAsset> changes) async {
    await commands.grouping(changes);
    await load();
  }

  Future<void> update(VideoAsset asset) async {
    await commands.update(asset);
    await load();
  }
}
