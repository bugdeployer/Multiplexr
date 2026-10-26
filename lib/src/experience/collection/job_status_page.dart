import 'package:flutter/material.dart';

import '../../library/library_models.dart';
import '../../library/library_controller.dart';

import 'package:app_shell/app_shell.dart';

export '../../features/jobs/application/activity_queries.dart'
    show CollectionJobStatus;
import '../../features/jobs/application/activity_queries.dart';

Future<List<CollectionJobStatus>> readCollectionJobs(
  LibraryController library,
) => library.activity.read();

/// Extra media adapters project neutral journals without fabricating legacy collections.
class CollectionActivityEntry {
  const CollectionActivityEntry({
    required this.id,
    required this.title,
    required this.summary,
    required this.authorized,
    required this.open,
  });
  final String id, title, summary;
  final bool Function() authorized;
  final Future<void> Function() open;
}

class JobStatusPage extends StatefulWidget {
  const JobStatusPage({
    super.key,
    required this.library,
    required this.openCollection,
    this.actionsFor,
    this.additionalJobs,
    this.additionalChanges,
  });
  final LibraryController library;
  final Future<List<CollectionActivityEntry>> Function()? additionalJobs;
  final Listenable? additionalChanges;
  final Future<void> Function(VideoCollection, bool metadata) openCollection;
  final Map<String, Future<void> Function()> Function(CollectionJobStatus)?
  actionsFor;
  @override
  State<JobStatusPage> createState() => _JobStatusPageState();
}

class _JobStatusPageState extends State<JobStatusPage> {
  List<CollectionJobStatus> jobs = [];
  List<CollectionActivityEntry> additional = [];
  bool loading = true;
  String? error;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    widget.library.addListener(load);
    widget.additionalChanges?.addListener(load);
    load();
  }

  Future<void> load() async {
    final current = ++revision;
    try {
      final next = await readCollectionJobs(widget.library);
      final extra =
          await widget.additionalJobs?.call() ?? <CollectionActivityEntry>[];
      if (mounted && revision == current) {
        setState(() {
          jobs = next;
          additional = extra;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && revision == current) {
        setState(() {
          loading = false;
          error = 'Could not load job status. Try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    revision++;
    widget.library.removeListener(load);
    widget.additionalChanges?.removeListener(load);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Activity'),
      actions: [
        IconButton(
          tooltip: 'Refresh activity',
          onPressed: load,
          icon: const AppIcon(AppIconRole.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.of(context).all(20),
              children: [
                const Text(
                  'Scans and unfinished metadata work. Open a collection to resume, review or cancel using its existing controls. Locked collections are omitted until unlocked.',
                ),
                const AppGap(20),
                if (error != null) Text(error!),
                if (jobs.isEmpty &&
                    !additional.any((j) => j.authorized()) &&
                    error == null)
                  const Text('No pending jobs.'),
                for (final job in additional.where((j) => j.authorized()))
                  ListTile(
                    key: ValueKey('activity:${job.id}'),
                    title: Text(job.title),
                    subtitle: Text(job.summary),
                    trailing: const AppIcon(AppIconRole.disclosure),
                    onTap: () async {
                      if (!job.authorized()) return;
                      try {
                        await job.open();
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () =>
                                error = 'Could not open this activity. Retry.',
                          );
                        }
                      }
                      if (mounted) await load();
                    },
                  ),
                for (final job in jobs.where(
                  (j) => widget.library.canAccessCollection(j.collection.id),
                ))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        title: Text(job.collection.name),
                        subtitle: Text(job.summary),
                        trailing: const AppIcon(AppIconRole.disclosure),
                        onTap: () async {
                          await widget.openCollection(
                            job.collection,
                            job.metadata,
                          );
                          if (mounted) await load();
                        },
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final action
                              in (widget.actionsFor?.call(job) ??
                                      <String, Future<void> Function()>{})
                                  .entries)
                            TextButton(
                              onPressed: () async {
                                try {
                                  await action.value();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) await load();
                                }
                              },
                              child: Text(action.key),
                            ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
  );
}
