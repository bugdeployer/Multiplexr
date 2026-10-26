import '../../../core/application/job_notifications.dart';
import '../../../catalog/domain/classification.dart';
import '../../catalog/application/collection_presenter.dart';
import 'metadata_contracts.dart';
import 'metadata_workflow.dart';
import 'metadata_work_runner.dart';
import 'metadata_batch_journal.dart';
import 'reading_metadata_job_port.dart';

/// Human-triggered, small batches. Results always require shared field review.
class ReadingMetadataWork extends JobNotifications implements CollectionJob {
  ReadingMetadataWork(
    this.library,
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
  final ReadingMetadataJobPort library;
  final String collectionId;
  final MetadataProvider provider;
  @override
  bool running = false;
  @override
  int done = 0, total = 0;
  final remaining = <String>[];
  final entries = <String, Map<String, dynamic>>{};
  MetadataCancellation cancellation = MetadataCancellation();
  bool _disposed = false;
  String? error;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> recover({bool forStart = false}) async {
    if (_disposed || running && !forStart) return;
    library.access(collectionId);
    final job = await library.readJournal(collectionId, provider.id);
    if (_disposed || running && !forStart) return;
    library.access(collectionId);
    entries.clear();
    remaining.clear();
    done = 0;
    total = 0;
    if (job != null &&
        job.implementationEpoch == workflow.implementationEpoch) {
      done = job.done;
      total = job.total;
      remaining.addAll(job.remaining);
      entries.addAll(
        job.entries.map(
          (key, row) => MapEntry(key, Map<String, dynamic>.from(row)),
        ),
      );
    }
    changed();
  }

  Future<void> checkpoint() =>
      library.updateJournal(collectionId, provider.id, (old) {
        for (final row in old?.entries.values ?? <Map<String, dynamic>>[]) {
          if (row['status'] == 'applied' && entries.containsKey(row['id'])) {
            entries[row['id'] as String] = Map<String, dynamic>.from(row);
          }
        }
        return MetadataBatchJournal(
          implementationEpoch: _executionEpoch ?? workflow.implementationEpoch,
          done: done,
          total: total,
          remaining: remaining,
          entries: entries,
        );
      });
  Future<void> start(
    List<String> selected, {
    bool resume = false,
    bool retry = false,
    bool replace = false,
  }) => library.maintenance.activity(
    () => library.maintenance.jobs.run(
      'metadata:reading:$collectionId',
      [collectionId],
      () => _startAdmitted(
        selected,
        resume: resume,
        retry: retry,
        replace: replace,
      ),
      cancelled: () => cancellation.cancelled,
      cancelledResult: () {},
      admitted: () {
        cancellation = guardedCancellation();
      },
    ),
  );

  Future<void> _startAdmitted(
    List<String> selected, {
    bool resume = false,
    bool retry = false,
    bool replace = false,
  }) async {
    if (_disposed) throw StateError('Metadata job was disposed');
    if (running) throw const MetadataJobBusy();
    if (selected.length > 20) {
      throw ArgumentError('Select at most 20 publications per lookup batch.');
    }
    running = true;
    error = null;
    cancellation = guardedCancellation();
    changed();
    try {
      await recover(forStart: true);
      final publications = await library.titles(collectionId);
      library.access(collectionId);
      final titles = {for (final t in publications) t.catalog.id.entityId: t};
      if (!resume && !retry) {
        if (!replace &&
            (remaining.isNotEmpty ||
                entries.values.any((e) => e['status'] == 'review'))) {
          throw StateError(
            'Review or replace the previous lookup batch first.',
          );
        }
        if (selected.toSet().length != selected.length ||
            selected.any((id) => !titles.containsKey(id))) {
          throw ArgumentError('Invalid lookup selection');
        }
        entries.clear();
        remaining
          ..clear()
          ..addAll(selected);
        done = 0;
        total = remaining.length;
      } else if (retry) {
        final failed = entries.values
            .where((e) => e['status'] == 'failed')
            .map((e) => e['id'] as String)
            .toSet();
        final completedFailures = failed
            .where((id) => !remaining.contains(id))
            .length;
        remaining.addAll(failed.where((id) => !remaining.contains(id)));
        done -= completedFailures;
        total = done + remaining.length;
      }
      await runner.run<String>(
        owner: library.owner,
        key: 'reading:metadata:$collectionId',
        work: List.of(remaining),
        cancellation: cancellation,
        checkpoint: checkpoint,
        process: (id) async {
          library.access(collectionId);
          final title = titles[id];
          if (title == null) {
            throw StateError(
              'The publication was removed. Reload the lookup batch.',
            );
          }
          try {
            final page = await runner.request(
              () => workflow.search(
                MetadataSearchRequest(
                  collectionId: title.catalog.id.collectionId,
                  provider: provider.id,
                  entity: title.catalog.subtype == MediaSubtype.ebook
                      ? MetadataEntityType.ebook
                      : MetadataEntityType.comic,
                  title: title.catalog.metadata.identifier.startsWith('ISBN:')
                      ? title.catalog.metadata.identifier.substring(5)
                      : title.catalog.title,
                  creator: title.catalog.metadata.authors.join(' '),
                ),
                cancellation,
              ),
              cancellation,
            );
            entries[id] = {
              'id': id,
              'status': page.candidates.isEmpty ? 'noMatch' : 'review',
              'error': page.candidates.isEmpty
                  ? 'No matches. Search manually.'
                  : '',
              'candidates': page.candidates
                  .map(
                    (c) => {
                      ...c.toJson(),
                      'values': {
                        for (final e in c.values.entries)
                          if ({
                            'title',
                            'authors',
                            'description',
                            'language',
                            'identifier',
                            'comicStyle',
                          }.contains(e.key))
                            e.key: e.value,
                      },
                    },
                  )
                  .toList(),
            };
          } catch (e) {
            cancellation.check();
            final failure = runner.classify(e);
            entries[id] = {
              'id': id,
              'status': 'failed',
              'error': failure.message,
              'candidates': <dynamic>[],
            };
            await checkpoint();
            if (failure.kind != MetadataFailureKind.invalidResponse &&
                failure.kind != MetadataFailureKind.unavailable) {
              rethrow;
            }
          }
        },
        completed: (id) async {
          remaining.remove(id);
          done++;
        },
      );
    } catch (e) {
      error = runner.classify(e).message;
      rethrow;
    } finally {
      running = false;
      changed();
    }
  }

  Future<void> applied(String id) async {
    await library.updateJournal(collectionId, provider.id, (old) {
      if (old == null) return MetadataBatchJournal();
      return MetadataBatchJournal(
        implementationEpoch: old.implementationEpoch,
        done: old.done,
        total: old.total,
        remaining: old.remaining,
        entries: {
          for (final entry in old.entries.entries)
            entry.key: entry.key == id
                ? {
                    ...entry.value,
                    'status': 'applied',
                    'candidates': <dynamic>[],
                  }
                : entry.value,
        },
      );
    });
    await recover();
  }

  @override
  void cancel() {
    if (cancellation.cancelled) return;
    cancellation.cancel();
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    cancellation.cancel();
    super.dispose();
  }
}
