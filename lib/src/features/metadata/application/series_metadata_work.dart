import '../../../core/application/maintenance.dart';
import '../../../core/application/job_notifications.dart';
import '../../catalog/application/collection_presenter.dart' show CollectionJob;

import 'dart:convert';

import 'metadata_contracts.dart';
import 'metadata_workflow.dart';
import 'metadata_work_runner.dart';
import '../../../library/library_models.dart';
import '../../../library/series.dart';

/// Explicit series match with a durable source-ID work list. The journal uses
/// a stable anchor file instead of provider grouping, which may change on match.
class SeriesMetadataWork extends JobNotifications implements CollectionJob {
  SeriesMetadataWork(
    this.series, {
    required this.owner,
    required this.maintenance,
    required this.checkAccess,
    required this.readState,
    required this.writeState,
    required this.items,
    required this.reload,
    required this.target,
    required this.runner,
    required this.coordinator,
  }) : collectionId = series.assets.first.collectionId,
       anchorId = (series.assets.map((a) => a.id).toList()..sort()).first;
  final Object owner;
  final Maintenance maintenance;
  final void Function() checkAccess;
  final Future<Map<String, dynamic>?> Function(String) readState;
  final Future<void> Function(String, Map<String, dynamic>) writeState;
  final List<VideoAsset> Function(String) items;
  final Future<void> Function() reload;
  final MetadataTarget Function(VideoAsset) target;
  final MetadataWorkRunner runner;
  final MetadataWorkflow coordinator;
  final SeriesRecord series;
  final String collectionId, anchorId;
  String get key => 'metadata:series:${jsonEncode([collectionId, anchorId])}';
  MetadataCancellation cancellation = MetadataCancellation();
  @override
  bool running = false;
  bool cancelled = false, _disposed = false;
  @override
  int done = 0;
  @override
  int total = 0;
  final remaining = <String>[];
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void cancel() {
    cancelled = true;
    cancellation.cancel();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>?> recover() async {
    checkAccess();
    final saved = await readState(key);
    checkAccess();
    if (saved == null ||
        saved['version'] != 2 ||
        saved['implementationEpoch'] != coordinator.implementationEpoch) {
      return null;
    }
    return saved;
  }

  Future<void> run(
    MetadataCandidate candidate,
    Set<String> fields, {
    bool resume = false,
  }) {
    if (running) return Future.value();
    checkAccess();
    return maintenance
        .activity(
          () => maintenance.jobs.run<void>(
            key,
            [collectionId],
            () => _runAdmitted(candidate, fields, resume: resume),
            cancelled: () => cancelled,
            cancelledResult: () {},
            admitted: () {
              running = true;
              cancelled = false;
              final epoch = coordinator.implementationEpoch;
              cancellation = MetadataCancellation(
                checkAccess: () {
                  checkAccess();
                  if (coordinator.implementationEpoch != epoch) {
                    throw const MetadataFailure(
                      MetadataFailureKind.permission,
                      'Provider changed; start a new series match.',
                    );
                  }
                },
              );
              changed();
            },
          ),
        )
        .whenComplete(() {
          running = false;
          changed();
        });
  }

  Future<void> _runAdmitted(
    MetadataCandidate candidate,
    Set<String> fields, {
    required bool resume,
  }) async {
    checkAccess();
    final saved = resume ? await recover() : null;
    checkAccess();
    if (resume &&
        (saved == null ||
            jsonEncode(saved['candidate']) != jsonEncode(candidate.toJson()))) {
      throw const MetadataFailure(
        MetadataFailureKind.conflict,
        'Series match changed. Start a new match.',
      );
    }
    remaining
      ..clear()
      ..addAll(
        resume
            ? List<String>.from(saved?['remaining'] ?? [])
            : series.assets.where(identifiedEpisode).map((a) => a.id),
      );
    // Provider matching may split a local folder group temporarily; recover by
    // durable IDs across the collection, never by its newly changed group ID.
    final current = items(collectionId);
    final ids = current.map((a) => a.id).toSet();
    remaining.removeWhere((id) => !ids.contains(id));
    final work = current
        .where((a) => remaining.contains(a.id) && identifiedEpisode(a))
        .toList();
    done = 0;
    total = work.length;
    running = true;
    changed();
    Future<void> checkpoint() {
      checkAccess();
      return writeState(key, {
        'version': 2,
        'implementationEpoch': coordinator.implementationEpoch,
        'candidate': candidate.toJson(),
        'fields': fields.toList(),
        'remaining': remaining,
      });
    }

    try {
      await runner.run<VideoAsset>(
        owner: owner,
        key: 'metadata:$collectionId',
        work: work,
        cancellation: cancellation,
        checkpoint: checkpoint,
        process: (asset) async {
          checkAccess();
          final port = target(asset);
          final review = await runner.request(
            () => coordinator.review(port, candidate, cancellation),
            cancellation,
          );
          if (cancellation.cancelled) return;
          await coordinator.apply(
            port,
            review,
            review.defaults.intersection(fields),
            cancellation,
          );
        },
        completed: (asset) async {
          remaining.remove(asset.id);
          done++;
          changed();
        },
        yieldBatch: () async {
          if (done % 20 == 0) await reload();
        },
      );
    } on MetadataFailure catch (e) {
      if (e.kind != MetadataFailureKind.cancelled) rethrow;
    } finally {
      running = false;
      await reload();
      changed();
    }
  }
}
