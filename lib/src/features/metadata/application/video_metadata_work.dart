import '../../../core/application/job_notifications.dart';
import '../../catalog/application/collection_presenter.dart' show CollectionJob;
import '../../../library/library_models.dart';
import 'metadata_contracts.dart';
import 'metadata_workflow.dart';
import 'metadata_work_runner.dart';
import 'video_metadata_policy.dart';
import 'video_metadata_job_port.dart';

/// One manually started job. Cancellation finishes the current request/save only.
class VideoMetadataWork extends JobNotifications implements CollectionJob {
  VideoMetadataWork(
    this.library,
    this.collection, {
    required this.coordinator,
    required this.runner,
  });
  final MetadataWorkflow coordinator;
  String? _executionEpoch;
  MetadataCancellation guardedCancellation() {
    final epoch = coordinator.implementationEpoch;
    _executionEpoch = epoch;
    return MetadataCancellation(
      checkAccess: () {
        if (epoch != coordinator.implementationEpoch) {
          throw const MetadataFailure(
            MetadataFailureKind.permission,
            'Provider implementation or permissions changed. Start a new batch.',
          );
        }
      },
    );
  }

  final MetadataWorkRunner runner;
  final VideoMetadataJobPort library;
  VideoCollection collection;
  static const batchSize = 20;
  @override
  bool running = false;
  bool cancelled = false, _disposed = false;
  @override
  int done = 0;
  @override
  int total = 0;
  int matched = 0, review = 0, failed = 0;
  final List<String> remaining = [];
  final Map<String, String> failures = {};
  String? lastError;
  bool checkpointSupported = true;
  bool get resumable => !running && remaining.isNotEmpty;
  String get key => 'metadata:${collection.id}';
  MetadataCancellation cancellation = MetadataCancellation();
  String failureKind(Object error) => runner.classify(error).message;
  Future<void> recover() async {
    {
      final state = await library.readJournal(collection.id);
      checkpointSupported = library.checkpointSupported;
      if (state == null || running) return;
      if (state['version'] != 2 ||
          state['implementationEpoch'] != coordinator.implementationEpoch) {
        remaining.clear();
        failures.clear();
        done = 0;
        total = 0;
        lastError =
            'Provider implementation changed. Start a new metadata batch.';
        changed();
        return;
      }
      remaining
        ..clear()
        ..addAll(List<String>.from(state['remaining'] ?? []));
      failures
        ..clear()
        ..addAll(Map<String, String>.from(state['failures'] ?? {}));
      done = state['done'] ?? 0;
      total = state['total'] ?? remaining.length;
      matched = state['matched'] ?? 0;
      review = state['review'] ?? 0;
      lastError = state['lastError'];
      final previousFailures = failures.length;
      _pruneResolvedFailures();
      if (previousFailures != failures.length) await checkpoint();
      changed();
    }
  }

  void _pruneResolvedFailures() {
    final previousFailures = failures.length;
    final assets = {
      for (final asset in library.indexedItems(collection.id)) asset.id: asset,
    };
    failures.removeWhere(
      (id, _) =>
          assets[id] == null ||
          assets[id]!.metadataSource != 'filename' ||
          assets[id]!.metadataStatus == 'review' ||
          (!remaining.contains(id) && assets[id]!.metadataStatus != 'failed'),
    );
    failed = failures.length;
    if (previousFailures != failures.length) {
      lastError = failures.values.lastOrNull;
    }
  }

  Future<void> checkpoint() async {
    if (!checkpointSupported) return;
    {
      checkpointSupported = await library.writeJournal(collection.id, {
        'version': 2,
        'implementationEpoch':
            _executionEpoch ?? coordinator.implementationEpoch,
        'remaining': remaining,
        'failures': failures,
        'done': done,
        'total': total,
        'matched': matched,
        'review': review,
        'failed': failed,
        'lastError': lastError,
      });
    }
  }

  int get batch => total == 0
      ? 0
      : (done ~/ batchSize + 1).clamp(1, (total / batchSize).ceil());
  int get batches => (total / batchSize).ceil();
  String get summary =>
      '${cancelled ? "Cancelled · " : ""}$matched matched · $review need review · $failed failed · ${remaining.length} remaining';
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancellation.cancel();
    super.dispose();
  }

  @override
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    cancellation.cancel();
    changed();
  }

  Future<void> run({
    bool failedOnly = false,
    Set<String>? assetIds,
    bool resume = false,
  }) => library.maintenance.activity(
    () => library.maintenance.jobs.run(
      'metadata:video:${collection.id}',
      [collection.id],
      () => _runAdmitted(
        failedOnly: failedOnly,
        assetIds: assetIds,
        resume: resume,
      ),
      cancelled: () => cancelled,
      cancelledResult: () {},
      admitted: () {
        cancelled = false;
        cancellation = guardedCancellation();
      },
    ),
  );

  Future<void> _runAdmitted({
    bool failedOnly = false,
    Set<String>? assetIds,
    bool resume = false,
  }) async {
    if (_disposed || running) return;
    running = true;
    cancelled = false;
    cancellation = guardedCancellation();
    if (!resume) {
      done = 0;
      matched = 0;
      review = 0;
      failed = 0;
      failures.clear();
      remaining.clear();
    }
    lastError = null;
    final pending = library
        .items(collection.id)
        .where(
          (a) =>
              (!resume || remaining.contains(a.id)) &&
              (assetIds == null || assetIds.contains(a.id)) &&
              a.metadataSource == 'filename' &&
              a.available &&
              (failedOnly
                  ? a.metadataStatus == 'failed'
                  : a.metadataStatus != 'review'),
        )
        .toList();
    if (!resume) {
      total = pending.length;
      remaining
        ..clear()
        ..addAll(pending.map((a) => a.id));
    } else {
      final latest = {
        for (final asset in library.items(collection.id)) asset.id: asset,
      };
      // Preserve unavailable entries for reconnection; do not overwrite matches applied since the checkpoint.
      remaining.removeWhere(
        (id) =>
            latest[id] == null ||
            latest[id]!.metadataSource != 'filename' ||
            latest[id]!.metadataStatus == 'review',
      );
      total = done + remaining.length;
      _pruneResolvedFailures();
    }
    changed();
    try {
      await runner.run<VideoAsset>(
        owner: library.owner,
        key: key,
        work: pending,
        cancellation: cancellation,
        checkpoint: checkpoint,
        prepare: () async {
          if (coordinator.providers.isEmpty) {
            throw const MetadataFailure(
              MetadataFailureKind.unavailable,
              'Install and enable a metadata provider with collection access.',
            );
          }
        },
        process: (asset) async {
          if (cancelled) return;
          if (!library.canAccessCollection(collection.id)) {
            throw const MetadataFailure(
              MetadataFailureKind.permission,
              'Collection access is required.',
            );
          }
          VideoAsset? updated;
          var outcome = 'matched';
          try {
            final lookup = collection.subtype == VideoSubtype.videos
                ? VideoAsset.fromJson({
                    ...asset.toJson(),
                    'metadata': inferMetadata(
                      asset.filename,
                      VideoSubtype.movies,
                    ),
                  }, VideoSubtype.movies)
                : asset;
            final type = asset.mediaSubtype;
            final response = await runner.request(
              () => coordinator.search(
                MetadataSearchRequest(
                  collectionId: collection.id,
                  provider: 'host:auto',
                  entity: type == VideoSubtype.tv
                      ? MetadataEntityType.television
                      : MetadataEntityType.movie,
                  title: metadataQuery(lookup, type),
                ),
                cancellation,
              ),
              cancellation,
            );
            final results = response.candidates
                .map((c) => <String, dynamic>{...c.values, 'id': c.id})
                .toList();
            if (cancelled) return;
            final match = confidentMatch(lookup, type, results);
            if (match == null) {
              updated = VideoAsset.fromJson({
                ...asset.toJson(),
                'metadataStatus': 'review',
              }, type);
              outcome = 'review';
            } else {
              final candidate = response.candidates.firstWhere(
                (c) => c.id == '${match['id']}',
              );
              final target = library.target(lookup, asset, collection.id);
              final review = await runner.request(
                () => coordinator.review(target, candidate, cancellation),
                cancellation,
              );
              if (cancelled) return;
              // Automatic jobs preserve every manual field/artwork; ambiguous
              // candidates use this same review/apply surface when selected.
              await coordinator.apply(
                target,
                review,
                review.defaults,
                cancellation,
              );
            }
          } catch (error) {
            if (cancelled) return;
            if (runner.classify(error).kind == MetadataFailureKind.storage) {
              rethrow;
            }
            lastError = failureKind(error);
            failures[asset.id] = lastError!;
            failed = failures.length;
            if ([
              MetadataFailureKind.authentication,
              MetadataFailureKind.rateLimit,
              MetadataFailureKind.storage,
              MetadataFailureKind.permission,
              MetadataFailureKind.conflict,
            ].contains(runner.classify(error).kind)) {
              await checkpoint();
              rethrow;
            }
            updated = VideoAsset.fromJson({
              ...asset.toJson(),
              'metadataStatus': 'failed',
            }, asset.mediaSubtype);
            outcome = 'failed';
          }
          if (cancelled) return;
          // A failed database write must abort, never turn into a second write of stale metadata.
          if (!library.canAccessCollection(collection.id)) {
            throw const MetadataFailure(
              MetadataFailureKind.permission,
              'Collection access is required.',
            );
          }
          if (updated != null) {
            await library.applyStatus(asset, updated);
          }
          if (outcome != 'failed') {
            failures.remove(asset.id);
            lastError = failures.values.lastOrNull;
          }
          failed = failures.length;
          if (outcome == 'matched') {
            matched++;
          } else if (outcome == 'review') {
            review++;
          }
        },
        completed: (asset) async {
          remaining.remove(asset.id);
          done++;
          changed();
        },
        yieldBatch: () async {
          if (done % batchSize == 0) await library.load();
          await Future<void>.delayed(Duration.zero);
        },
      );
    } catch (error) {
      if (error is MetadataJobBusy) rethrow;
      lastError ??= error is StateError
          ? error.message.toString()
          : failureKind(error);
      // The original failure remains actionable even if storage cannot save its checkpoint.
      try {
        await checkpoint();
      } catch (_) {}
      rethrow;
    } finally {
      running = false;
      await library.load();
      changed();
    }
  }
}
