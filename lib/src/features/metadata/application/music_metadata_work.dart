import '../../../core/application/job_notifications.dart';
import '../../catalog/application/collection_presenter.dart';
import '../../../media/music_catalog_models.dart';
import 'metadata_contracts.dart';
import 'metadata_workflow.dart';
import 'metadata_work_runner.dart';
import 'music_metadata_job_port.dart';

/// Edition ambiguity always goes through the shared review/apply flow.
class MusicMetadataWork extends JobNotifications implements CollectionJob {
  MusicMetadataWork(
    this.repository,
    this.collectionId,
    this.provider, {
    required this.workflow,
    required this.runner,
  });
  final MetadataWorkflow workflow;
  String? _executionEpoch;
  MetadataCancellation guardedCancellation() {
    final epoch = workflow.implementationEpoch;
    _executionEpoch = epoch;
    return MetadataCancellation(
      checkAccess: () {
        if (epoch != workflow.implementationEpoch) {
          throw const MetadataFailure(
            MetadataFailureKind.permission,
            'Provider implementation or permissions changed. Start a new batch.',
          );
        }
      },
    );
  }

  final MetadataWorkRunner runner;
  final MusicMetadataJobPort repository;
  final String collectionId;
  final MetadataProvider provider;
  String get key => 'metadata:music:$collectionId';
  final entries = <String, dynamic>{};
  final remaining = <String>[];
  MetadataCancellation cancellation = MetadataCancellation();
  @override
  bool running = false;
  @override
  int done = 0, total = 0;
  bool _disposed = false;
  String? pausedReason;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void cancel() {
    if (cancellation.cancelled) return;
    if (running) pausedReason = 'Paused. Resume to continue remaining titles.';
    cancellation.cancel();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }

  Future<void> recover({bool forStart = false}) async {
    if (_disposed || running && !forStart) return;
    final data = await repository.readJournal(collectionId) ?? {};
    if (_disposed || running && !forStart) return;
    if (data.isNotEmpty &&
        (data['version'] != 2 ||
            data['implementationEpoch'] != workflow.implementationEpoch)) {
      entries.clear();
      remaining.clear();
      done = 0;
      total = 0;
      pausedReason = 'Provider implementation changed. Start a new lookup.';
      changed();
      return;
    }
    entries
      ..clear()
      ..addAll(Map<String, dynamic>.from(data['entries'] ?? {}));
    remaining
      ..clear()
      ..addAll(List<String>.from(data['remaining'] ?? []));
    total = data['total'] ?? 0;
    done = data['done'] ?? 0;
    pausedReason = data['pausedReason'];
    changed();
  }

  Future<void> checkpoint() => repository.updateJournal(collectionId, (
    previous,
  ) async {
    if (!repository.access(collectionId)) {
      throw StateError('Collection access required.');
    }
    final merged = {...?previous?['entries'] as Map?, ...entries};
    for (final e in (previous?['entries'] as Map? ?? {}).entries) {
      if (e.value['status'] == 'applied') merged[e.key] = e.value;
    }
    return {
      'version': 2,
      'implementationEpoch': _executionEpoch ?? workflow.implementationEpoch,
      if (pausedReason != null) 'pausedReason': pausedReason,
      'entries': merged,
      'remaining': remaining,
      'done': done,
      'total': total,
    };
  });
  Future<void> start(
    List<MusicTrack> tracks, {
    bool retry = false,
    bool resume = false,
  }) => repository.maintenance.activity(
    () => repository.maintenance.jobs.run(
      'metadata:music:$collectionId',
      [collectionId],
      () => _startAdmitted(tracks, retry: retry, resume: resume),
      cancelled: () => cancellation.cancelled,
      cancelledResult: () {},
      admitted: () {
        cancellation = guardedCancellation();
      },
    ),
  );

  Future<void> _startAdmitted(
    List<MusicTrack> tracks, {
    bool retry = false,
    bool resume = false,
  }) async {
    if (_disposed || running) return;
    cancellation = guardedCancellation();
    running = true;
    changed();
    try {
      await recover(forStart: true);
      String? status(MusicTrack track) =>
          (entries[track.id.key] as Map?)?['status'] as String?;
      final work = tracks
          .where(
            (t) =>
                t.id.collectionId == collectionId &&
                t.available &&
                (resume
                    ? remaining.contains(t.id.key)
                    : retry
                    ? status(t) == 'failed'
                    : t.metadata.metadataSource.isEmpty &&
                          !{
                            'applied',
                            'review',
                            'failed',
                            'noMatch',
                          }.contains(status(t))),
          )
          .toList();
      if (!resume) {
        done = 0;
        total = work.length;
      }
      final previousPending = retry
          ? remaining
                .where((id) => (entries[id] as Map?)?['status'] != 'applied')
                .toList()
          : <String>[];
      remaining
        ..clear()
        ..addAll({...previousPending, ...work.map((t) => t.id.key)});
      if (retry) total = done + remaining.length;
      pausedReason = null;
      await runner.run(
        owner: repository.owner,
        key: key,
        work: work,
        cancellation: cancellation,
        checkpoint: checkpoint,
        process: (track) async {
          if (!repository.access(collectionId)) {
            throw StateError('Collection access required.');
          }
          try {
            final page = await runner.request(
              () => workflow.search(
                MetadataSearchRequest(
                  collectionId: track.id.collectionId,
                  provider: provider.id,
                  entity: MetadataEntityType.musicTrack,
                  title: track.metadata.title,
                  creator: track.metadata.artist,
                ),
                cancellation,
              ),
              cancellation,
            );
            entries[track.id.key] = {
              'status': page.candidates.isEmpty ? 'noMatch' : 'review',
              'candidates': [
                for (final candidate in page.candidates) candidate.toJson(),
              ],
              if (page.candidates.isEmpty)
                'error': 'No matches. Search manually.',
            };
          } catch (e) {
            cancellation.check();
            final failure = runner.classify(e);
            entries[track.id.key] = {
              'status': 'failed',
              'error': failure.message,
            };
            if (failure.kind != MetadataFailureKind.invalidResponse &&
                failure.kind != MetadataFailureKind.unavailable) {
              pausedReason = failure.message;
              await checkpoint();
              rethrow;
            }
          }
        },
        completed: (track) async {
          remaining.remove(track.id.key);
          done++;
          changed();
        },
      );
    } finally {
      if (cancellation.cancelled &&
          !_disposed &&
          repository.access(collectionId)) {
        try {
          await checkpoint();
        } catch (_) {
          /* The last successful checkpoint still retains pending IDs. */
        }
      }
      running = false;
      changed();
    }
  }

  Future<void> applied(String id) async {
    entries[id] = {'status': 'applied'};
    await checkpoint();
    changed();
  }
}
