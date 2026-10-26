import '../../../core/application/job_notifications.dart';
import '../../jobs/application/job_registry.dart' show PreparingJob;
import '../../catalog/application/collection_presenter.dart' show CollectionJob;
import 'metadata_contracts.dart';
import 'metadata_workflow.dart';
import 'metadata_work_runner.dart';
import 'audiobook_metadata_job_port.dart';

/// Provider-specific eligibility/journal codec over the shared durable runner.
/// Bulk audio matches always require review (edition/narrator ambiguity).
class AudiobookMetadataWork extends JobNotifications
    implements CollectionJob, PreparingJob {
  AudiobookMetadataWork(
    this.library, {
    this.collectionId,
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
  final AudiobookMetadataJobPort library;
  final String? collectionId;
  String get key => 'metadata:audiobooks:$collectionId';
  MetadataCancellation cancellation = MetadataCancellation();
  @override
  bool running = false;
  bool cancelled = false, _disposed = false;
  bool _starting = false, _startingCancelled = false;
  @override
  bool get preparing => _starting;
  @override
  int done = 0;
  @override
  int total = 0;
  final remaining = <String>[];
  final entries = <String, dynamic>{};
  Map<String, dynamic> get snapshot => {
    'entries': Map<String, dynamic>.from(entries),
    'remaining': List<String>.of(remaining),
    'done': done,
    'total': total,
  };
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void cancel() {
    if (_startingCancelled && cancellation.cancelled) return;
    _startingCancelled = true;
    cancellation.cancel();
    cancelled = true;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }

  Future<void> recover() async {
    if (running) return;
    final value = await library.readJournal(collectionId) ?? {};
    if (running || _disposed) return;
    if (value.isNotEmpty &&
        (value['version'] != 2 ||
            value['implementationEpoch'] != coordinator.implementationEpoch)) {
      remaining.clear();
      entries.clear();
      done = 0;
      total = 0;
      changed();
      return;
    }
    entries
      ..clear()
      ..addAll(Map<String, dynamic>.from(value['entries'] ?? {}));
    remaining
      ..clear()
      ..addAll(List<String>.from(value['remaining'] ?? []));
    done = value['done'] as int? ?? 0;
    total = value['total'] as int? ?? remaining.length;
    changed();
  }

  Future<void> checkpoint() => library.updateJournal(collectionId, (previous) {
    final old = previous ?? {};
    final merged = <String, dynamic>{...?old['entries'] as Map?, ...entries};
    for (final entry in (old['entries'] as Map? ?? {}).entries) {
      if ((entry.value as Map)['status'] == 'applied') {
        merged[entry.key as String] = entry.value;
      }
    }
    return {
      'version': 2,
      'implementationEpoch': _executionEpoch ?? coordinator.implementationEpoch,
      'entries': merged,
      'remaining': remaining,
      'done': done,
      'total': total,
    };
  });
  Future<void> markApplied(String id) async {
    await library.updateJournal(collectionId, (previous) {
      final state = previous ?? {};
      final values = Map<String, dynamic>.from(state['entries'] ?? {});
      values[id] = {...?values[id] as Map?, 'status': 'applied'};
      entries[id] = values[id];
      return {...state, 'entries': values};
    });
  }

  Future<void> run({bool retry = false, bool resume = false}) =>
      library.maintenance.activity(
        () => library.maintenance.jobs.run(
          'metadata:audiobooks:$collectionId',
          collectionId == null ? <String>[] : [collectionId!],
          () => _runAdmitted(retry: retry, resume: resume),
          cancelled: () => cancelled,
          cancelledResult: () {},
          admitted: () {
            cancelled = false;
            cancellation = guardedCancellation();
          },
        ),
      );

  Future<void> _runAdmitted({bool retry = false, bool resume = false}) async {
    if (_disposed || running || _starting) return;
    _starting = true;
    _startingCancelled = false;
    try {
      await _run(retry: retry, resume: resume);
    } finally {
      _starting = false;
    }
  }

  Future<void> _run({bool retry = false, bool resume = false}) async {
    if (running) return;
    await recover();
    final books = await library.books();
    if (_disposed || _startingCancelled) return;
    final pending = books.where((book) {
      if (!library.canAccess(book.id.collectionId)) return false;
      final previous = entries[book.id.key];
      final status = previous is Map ? previous['status'] : null;
      if (resume) return remaining.contains(book.id.key);
      if (retry) return status == 'failed';
      return book.metadata.providerId.isEmpty &&
          !{'review', 'applied', 'noMatch'}.contains(status);
    }).toList();
    if (!resume) {
      done = 0;
      total = pending.length;
      remaining
        ..clear()
        ..addAll(pending.map((b) => b.id.key));
    } else {
      final ids = books.map((b) => b.id.key).toSet();
      remaining.removeWhere(
        (id) =>
            !ids.contains(id) || (entries[id] as Map?)?['status'] == 'applied',
      );
      total = done + remaining.length;
    }
    cancellation = guardedCancellation();
    cancelled = false;
    running = true;
    changed();
    try {
      await runner.run(
        owner: library.owner,
        key: key,
        work: pending,
        cancellation: cancellation,
        checkpoint: checkpoint,
        prepare: () async {
          if (pending.isNotEmpty && coordinator.providers.isEmpty) {
            throw const MetadataFailure(
              MetadataFailureKind.authentication,
              'Add and verify your AudiobookDB key in Settings → Metadata before fetching metadata.',
            );
          }
        },
        process: (book) async {
          if (!library.canAccess(book.id.collectionId)) {
            throw const MetadataFailure(
              MetadataFailureKind.permission,
              'Collection access is required.',
            );
          }
          final current = (await library.books())
              .where((b) => b.id == book.id)
              .firstOrNull;
          if (current == null || current.metadata.providerId.isNotEmpty) return;
          try {
            final page = await runner.request(
              () => coordinator.search(
                MetadataSearchRequest(
                  collectionId: current.id.collectionId,
                  provider: 'host:auto',
                  entity: MetadataEntityType.audiobook,
                  title: current.metadata.title,
                  creator: current.metadata.author,
                ),
                cancellation,
              ),
              cancellation,
            );
            cancellation.check();
            if (!library.canAccess(book.id.collectionId)) {
              throw const MetadataFailure(
                MetadataFailureKind.permission,
                'Collection access is required.',
              );
            }
            entries[book.id.key] = {
              'title': current.metadata.title,
              'status': page.candidates.isEmpty ? 'noMatch' : 'review',
              'candidates': page.candidates.map((c) => c.values).toList(),
            };
          } catch (e) {
            if (cancellation.cancelled) return;
            final failure = runner.classify(e);
            entries[book.id.key] = {
              'title': current.metadata.title,
              'status': 'failed',
              'error': failure.message,
            };
            if (failure.kind != MetadataFailureKind.invalidResponse &&
                failure.kind != MetadataFailureKind.network) {
              await checkpoint();
              rethrow;
            }
          }
        },
        completed: (book) async {
          remaining.remove(book.id.key);
          done++;
          changed();
        },
      );
    } finally {
      running = false;
      changed();
    }
  }
}
