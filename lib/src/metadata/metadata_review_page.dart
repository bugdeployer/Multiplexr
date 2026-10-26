import '../experience/plugins/plugin_contribution_page.dart';
import '../media/media_cover.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import '../features/metadata/application/metadata_contracts.dart';
import '../features/metadata/application/metadata_workflow.dart';
import '../features/metadata/application/metadata_failure_message.dart';

/// The shared review/apply surface; grouping and source fields are never offered.
class MetadataReviewPage extends StatefulWidget {
  const MetadataReviewPage({
    super.key,
    required this.target,
    required this.candidate,
    this.title = 'Review metadata match',
    this.selectOnly = false,
    this.workflow,
  });
  final MetadataWorkflow? workflow;
  final MetadataTarget target;
  final MetadataCandidate candidate;
  final String title;
  final bool selectOnly;
  @override
  State<MetadataReviewPage> createState() => _MetadataReviewPageState();
}

class _MetadataReviewPageState extends State<MetadataReviewPage> {
  MetadataWorkflow get coordinator =>
      widget.workflow ??
      PluginPlatformScope.read(context)?.reviewWorkflow?.call() ??
      (throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Metadata services are unavailable. Reopen this screen.',
      ));
  late final cancellation = MetadataCancellation(
    checkAccess: () {
      final identity = widget.candidate.implementation;
      if (identity == null) {
        return;
      }
      final host = PluginPlatformScope.read(context);
      if (host == null || host.gateway.blocked()) {
        throw const MetadataFailure(
          MetadataFailureKind.permission,
          'Provider access ended.',
        );
      }
      final matches = host.registry.all.where(
        (c) =>
            c.id == identity.contribution &&
            c.plugin.publisher == identity.publisher &&
            c.plugin.version == identity.version &&
            c.plugin.instance == identity.instance &&
            c.plugin.revision == identity.permissionRevision &&
            c.plugin.collections.contains(identity.collection),
      );
      if (matches.isEmpty) {
        throw const MetadataFailure(
          MetadataFailureKind.permission,
          'Provider access ended. Reopen the match.',
        );
      }
    },
  );
  MetadataReview? review;
  Set<String> selected = {};
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await coordinator.review(
        widget.target,
        widget.candidate,
        cancellation,
      );
      if (mounted) {
        setState(() {
          review = value;
          selected = value.defaults;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = metadataFailureMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    if (widget.selectOnly) {
      Navigator.pop(context, selected);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final host = PluginPlatformScope.read(context);
      final origin = widget.candidate.implementation?.plugin;
      if (host != null && origin != null) {
        await host.withOrigin(
          origin,
          () =>
              coordinator.apply(widget.target, review!, selected, cancellation),
        );
      } else {
        await coordinator.apply(widget.target, review!, selected, cancellation);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = metadataFailureMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    PluginPlatformScope.maybeOf(context);
    try {
      cancellation.check();
    } catch (_) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(
          child: Text('Provider access ended. Reopen the match.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          Text('Metadata: ${widget.candidate.attribution}'),
          const AppGap(12),
          Text(
            [
              widget.candidate.values['title'] ??
                  widget.candidate.values['name'],
              widget.candidate.values['edition'],
              widget.candidate.values['language'],
              widget.candidate.values['publicationDate'] ??
                  widget.candidate.values['release_date'] ??
                  widget.candidate.values['first_air_date'],
              if ((widget.candidate.values['runtimeMinutes'] as num? ?? 0) > 0)
                '${widget.candidate.values['runtimeMinutes']} min',
            ].where((v) => v != null && v.toString().isNotEmpty).join(' · '),
          ),
          const AppGap(16),
          if (review != null)
            Text(
              review!.exactTitle
                  ? 'Exact title match · check the edition and selected fields.'
                  : 'Check the title, edition and selected fields before applying.',
            ),
          if (busy) const LinearProgressIndicator(),
          for (final e
              in review?.proposed.entries ?? <MapEntry<String, dynamic>>[])
            CheckboxListTile(
              value: selected.contains(e.key),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        selected.add(e.key);
                      } else {
                        selected.remove(e.key);
                      }
                    }),
              secondary:
                  {
                    'cover',
                    'poster',
                    'backdrop',
                    'seriesBackdrop',
                  }.contains(e.key)
                  ? SizedBox(
                      width: 64,
                      height: 64,
                      child: MetadataArtworkPreview(
                        location: e.value.toString(),
                      ),
                    )
                  : null,
              title: Text(labels[e.key] ?? e.key),
              subtitle: Text(
                {
                      'cover',
                      'poster',
                      'backdrop',
                      'seriesBackdrop',
                    }.contains(e.key)
                    ? (review!.before.manualFields.contains(e.key)
                          ? 'Your chosen artwork stays unless selected.'
                          : 'Use the artwork shown.')
                    : '${review!.before.manualFields.contains(e.key) ? 'Manually chosen · ' : ''}Current: ${review!.before.fields[e.key] ?? ''}\nNew: ${e.value}',
                maxLines: e.key == 'description' ? 6 : 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(error!),
            ),
          if (!busy && review == null && error != null)
            TextButton(onPressed: load, child: const Text('Retry')),
          const AppGap(16),
          FilledButton(
            onPressed: busy || selected.isEmpty || review == null
                ? null
                : apply,
            child: Text(busy ? 'Applying…' : 'Apply selected metadata'),
          ),
        ],
      ),
    );
  }

  static const labels = {
    'title': 'Title',
    'author': 'Author',
    'authors': 'Authors',
    'identifier': 'Identifier',
    'comicStyle': 'Comic style',
    'narrator': 'Narrator',
    'description': 'Description',
    'language': 'Language',
    'publisher': 'Publisher',
    'publicationDate': 'Release date',
    'cover': 'Cover',
    'poster': 'Poster',
    'backdrop': 'Backdrop',
    'seriesBackdrop': 'Series backdrop',
    'year': 'Year',
    'seriesOverview': 'Series description',
    'airDate': 'Air date',
    'seasonEpisodeCount': 'Episodes in season',
    'genres': 'Genres',
    'director': 'Director',
    'cast': 'Cast',
    'series': 'Series title',
    'tagline': 'Tagline',
    'runtimeMinutes': 'Runtime (minutes)',
  };
}

class MetadataArtworkPreview extends StatelessWidget {
  const MetadataArtworkPreview({super.key, required this.location});
  final String location;
  @override
  Widget build(BuildContext context) => MediaCover(
    cover: location,
    placeholder: (_) => const AppIcon(AppIconRole.artwork),
  );
}
