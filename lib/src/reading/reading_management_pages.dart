import '../library/collection_form.dart';
import '../media/grouping.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';

import 'package:app_shell/app_shell.dart';

import 'domain/reading_annotations.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import 'reading_comic_notes.dart';
import 'comic_reader_page.dart';
import 'reading_library.dart';
import '../features/sources/application/reading_scan_plan.dart';
import 'reading_workflow_widgets.dart';
import 'reader_opening.dart';

class ReadingCollectionSettingsPage extends StatefulWidget {
  const ReadingCollectionSettingsPage({
    super.key,
    required this.library,
    required this.collectionId,
  });
  final ReadingLibrary library;
  final String collectionId;
  @override
  State<ReadingCollectionSettingsPage> createState() =>
      _ReadingCollectionSettingsPageState();
}

class _ReadingCollectionSettingsPageState
    extends State<ReadingCollectionSettingsPage> {
  late final legacy = widget.library.collectionForms();
  ReadingBundle? bundle;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.collectionId);
      await legacy.load();
      final next = await widget.library.readCollection(widget.collectionId);
      if (mounted) setState(() => bundle = next);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load collection settings. Retry.');
      }
    }
  }

  @override
  void dispose() {
    widget.library.releaseCollectionForms();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.library.authorized(widget.collectionId)) {
      return const Scaffold(
        body: Center(child: Text('Collection access is required.')),
      );
    }
    final b = bundle;
    if (b == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collection settings')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : TextButton(onPressed: load, child: Text(error!)),
        ),
      );
    }
    final row = b.catalog.collections
        .where((r) => r.id == widget.collectionId)
        .firstOrNull;
    if (row == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Collection settings')),
        body: const Center(child: Text('This collection no longer exists.')),
      );
    }
    final preferences = b.management.collections
        .where((r) => r.collectionId == widget.collectionId)
        .firstOrNull;
    return CollectionForm(
      library: legacy,
      readingExisting: {
        'id': row.id,
        'name': row.name,
        'subtype': row.subtype.name,
        'locked': row.access.locked,
        'includeInGlobal': row.access.includeInGlobal,
        'roots': [
          for (final root in row.roots) {'uri': root.uri, 'name': root.name},
        ],
      },
      readingPreferences: {
        if (preferences != null) ...{
          'collectionId': preferences.collectionId,
          'layout': preferences.layout,
          'sort': preferences.sort,
          'openAction': preferences.openAction,
          if (preferences.cardSize != null) 'cardSize': preferences.cardSize,
          if (preferences.formats != null) 'formats': preferences.formats,
        },
      },
      readingNames: {
        for (final c in b.catalog.collections)
          if (c.id != widget.collectionId) c.name.toLowerCase(),
      },
      saveReading: (row, prefs) => widget.library.saveCollection(
        widget.library.collectionFromForm(row),
        preferences: prefs,
      ),
      removeReading: () => widget.library.removeCollection(widget.collectionId),
      readerSettings: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReadingScopedSettingsPage(
            library: widget.library,
            collectionId: widget.collectionId,
            subtype: row.subtype,
          ),
        ),
      ),
    );
  }
}

class ReadingTagsPage extends StatefulWidget {
  const ReadingTagsPage({
    super.key,
    required this.library,
    required this.collectionId,
  });
  final ReadingLibrary library;
  final String collectionId;
  @override
  State<ReadingTagsPage> createState() => _ReadingTagsPageState();
}

class _ReadingTagsPageState extends State<ReadingTagsPage> {
  ReadingBundle? bundle;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.collectionId);
      final value = await widget.library.readCollection(widget.collectionId);
      if (mounted) setState(() => bundle = value);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load tags. Retry.');
    }
  }

  Future<void> change(String tag, bool delete) async {
    await readingFields(
      context,
      title: delete ? 'Delete tag?' : 'Rename or merge tag',
      saveLabel: delete ? 'Delete' : 'Save',
      message: delete
          ? 'Remove “$tag” from every item in this collection?'
          : null,
      initial: delete ? {} : {'name': tag},
      labels: {'name': 'Tag name'},
      save: (values) => widget.library.tags(
        widget.collectionId,
        [],
        [tag],
        operation: delete ? 'delete' : 'rename',
        target: values['name'],
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final tags = <String, int>{};
    if (widget.library.authorized(widget.collectionId)) {
      for (final row in bundle?.management.entities ?? []) {
        if (row.collectionId == widget.collectionId) {
          for (final tag in row.tags as List) {
            tags[tag as String] = (tags[tag] ?? 0) + 1;
          }
        }
      }
    }
    final names = tags.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: const Text('Collection tags')),
      body: !widget.library.authorized(widget.collectionId)
          ? const Center(child: Text('Collection access is required.'))
          : ListView(
              padding: AppSpacing.of(context).all(20),
              children: [
                const Text(
                  'Rename a tag to an existing name to merge them. Add tags from a title menu or a selection.',
                ),
                if (error != null)
                  TextButton(onPressed: load, child: Text(error!)),
                if (names.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text('No tags yet.'),
                  ),
                for (final tag in names)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tag),
                    subtitle: Text('${tags[tag]} items'),
                    onTap: () => change(tag, false),
                    trailing: IconButton(
                      tooltip: 'Delete $tag',
                      icon: const AppIcon(AppIconRole.delete),
                      onPressed: () => change(tag, true),
                    ),
                  ),
              ],
            ),
    );
  }
}

class ReadingFolderHealthPage extends StatefulWidget {
  const ReadingFolderHealthPage({
    super.key,
    required this.library,
    required this.collectionId,
  });
  final ReadingLibrary library;
  final String collectionId;
  @override
  State<ReadingFolderHealthPage> createState() =>
      _ReadingFolderHealthPageState();
}

class _ReadingFolderHealthPageState extends State<ReadingFolderHealthPage> {
  late final scan = widget.library.createScan();
  ReadingBundle? bundle;
  ReadingScanPreview? preview;
  final grouping = <String, String>{},
      relinks = <String, String>{},
      replacements = <String, String>{};
  final resourceOrder = <String, List<String>>{};
  List<String> titleOrder = [];
  bool busy = false;
  String? error, progress;
  String encoding = 'utf-8';
  StreamSubscription? subscription;
  @override
  void initState() {
    super.initState();
    load();
    subscription = scan.progress.listen((e) {
      if (mounted) setState(() => progress = 'Checking local publications…');
    });
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.collectionId);
      final b = await widget.library.readCollection(widget.collectionId);
      if (mounted) setState(() => bundle = b);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load Folder health.');
    }
  }

  Future<void> discover() async {
    setState(() {
      busy = true;
      error = null;
      preview = null;
    });
    try {
      final result = await scan.preview(
        widget.collectionId,
        encoding: encoding,
        rootReplacements: replacements,
      );
      if (mounted) {
        setState(() {
          preview = result;
          grouping.clear();
          relinks.clear();
          resourceOrder.clear();
          titleOrder = [];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not complete the scan. Existing publications and progress are retained.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  void revise() {
    try {
      setState(() {
        preview = scan.revise(
          preview!,
          grouping: grouping,
          relinks: relinks,
          resourceOrder: resourceOrder,
          titleOrder: titleOrder,
        );
        error = null;
      });
    } catch (_) {
      setState(
        () => error = 'This correction conflicts with another choice. Check the assignments.',
      );
    }
  }

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      await scan.apply(widget.collectionId, preview!);
      await load();
      if (mounted) {
        setState(() {
          preview = null;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The scan could not be applied. Reload and scan again; existing data was kept.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> order(String sourceKey, List<ReadingResource> resources) async {
    List<String>? sorted;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GroupOrderPage<ReadingResource>(
          title: 'Correct order',
          items: resources,
          identity: (r) => r.id,
          label: (r) => r.label,
          save: (values) async {
            sorted = values.map((r) => r.id).toList();
          },
        ),
      ),
    );
    if (sorted != null && mounted) {
      resourceOrder[sourceKey] = sorted!;
      revise();
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = bundle?.catalog.collections
        .where((c) => c.id == widget.collectionId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Folder health')),
      body: !widget.library.authorized(widget.collectionId)
          ? const Center(child: Text('Collection access is required.'))
          : ListView(
              padding: AppSpacing.of(context).all(20),
              children: [
                if (error != null) Text(error!),
                for (final root in collection?.roots ?? <CatalogRoot>[])
                  ListTile(
                    title: Text(root.name),
                    subtitle: Text(
                      replacements.containsKey(root.uri)
                          ? 'Replacement selected · scan to preview'
                          : (bundle!.index.roots).any(
                              (r) =>
                                  r.collectionId == widget.collectionId &&
                                  r.uri == root.uri &&
                                  r.complete == true,
                            )
                          ? 'Last applied scan complete'
                          : 'Folder verification required',
                    ),
                    trailing: TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final picked = await widget.library.pickRoot();
                              if (picked != null && mounted) {
                                setState(
                                  () => replacements[root.uri] = picked.uri,
                                );
                              }
                            },
                      child: const Text('Repair source'),
                    ),
                  ),
                if (collection?.subtype == MediaSubtype.ebook)
                  DropdownButtonFormField<String>(
                    icon: const AppIcon(AppIconRole.expand),
                    isExpanded: true,
                    initialValue: encoding,
                    decoration: const InputDecoration(
                      labelText: 'TXT encoding',
                    ),
                    items: [
                      for (final e in [
                        'utf-8',
                        'utf-16le',
                        'utf-16be',
                        'windows-1252',
                      ])
                        DropdownMenuItem(value: e, child: Text(e)),
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            if (v != null) setState(() => encoding = v);
                          },
                  ),
                FilledButton(
                  onPressed: busy ? null : discover,
                  child: const Text('Scan and preview'),
                ),
                if (busy) ...[
                  const LinearProgressIndicator(),
                  Text(progress ?? 'Working…'),
                  TextButton(
                    onPressed: scan.cancel,
                    child: const Text('Cancel scan'),
                  ),
                ],
                if (preview != null) ...[
                  Text(
                    '${preview!.added} added · ${preview!.relinked} reconnected · ${preview!.missing} missing',
                  ),
                  for (final message in [
                    ...preview!.warnings,
                    ...preview!.unresolved,
                  ])
                    Text(message),
                  for (final source in preview!.sources)
                    ExpansionTile(
                      title: Text(source.name),
                      subtitle: Text(source.series),
                      children: [
                        TextButton(
                          onPressed: () => readingFields(
                            context,
                            title: 'Series assignment',
                            initial: {
                              'series': grouping[source.key] ?? source.series,
                            },
                            labels: {'series': 'Series (empty for standalone)'},
                            save: (v) async {
                              grouping[source.key] = v['series']!;
                              revise();
                            },
                          ),
                          child: const Text('Correct series / standalone'),
                        ),
                        DropdownButtonFormField<String>(
                          icon: const AppIcon(AppIconRole.expand),
                          initialValue:
                              relinks.entries
                                  .where((e) => e.value == source.key)
                                  .firstOrNull
                                  ?.key ??
                              '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Reconnect missing title',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Use automatic match'),
                            ),
                            for (final t in bundle!.catalog.titles.where(
                              (t) =>
                                  t.catalog.id.collectionId ==
                                  widget.collectionId,
                            ))
                              DropdownMenuItem(
                                value: t.catalog.id.entityId,
                                child: Text(
                                  t.catalog.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            relinks.removeWhere(
                              (_, value) => value == source.key,
                            );
                            if (v != null && v.isNotEmpty) {
                              relinks[v] = source.key;
                            }
                            revise();
                          },
                        ),
                        TextButton(
                          onPressed: () => order(source.key, source.resources),
                          child: const Text('Correct chapter / page order'),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: () async {
                      List<String>? sorted;
                      final resources = preview!.titles
                          .where(
                            (t) =>
                                t.catalog.id.collectionId ==
                                widget.collectionId,
                          )
                          .toList();
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => GroupOrderPage<ReadingTitle>(
                            title: 'Correct title order',
                            items: resources,
                            identity: (r) => r.catalog.id.entityId,
                            label: (r) => r.catalog.title,
                            save: (values) async {
                              sorted = values
                                  .map((r) => r.catalog.id.entityId)
                                  .toList();
                            },
                          ),
                        ),
                      );
                      if (sorted != null && mounted) {
                        titleOrder = sorted!;
                        revise();
                      }
                    },
                    child: const Text('Correct title order'),
                  ),
                  FilledButton(
                    onPressed: !busy && preview!.canApply ? apply : null,
                    child: const Text('Apply reviewed scan'),
                  ),
                ],
                for (final title
                    in bundle?.catalog.titles.where(
                          (t) =>
                              t.catalog.id.collectionId ==
                                  widget.collectionId &&
                              !t.catalog.sources.single.available,
                        ) ??
                        <ReadingTitle>[])
                  ListTile(
                    title: Text(title.catalog.title),
                    subtitle: const Text(
                      'Missing · IDs, metadata, progress and notes are retained',
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    unawaited(scan.cancel().catchError((Object _) {}));
    super.dispose();
  }
}

class ReadingAnnotationsPage extends StatefulWidget {
  const ReadingAnnotationsPage({
    super.key,
    required this.library,
    required this.collectionId,
    this.titleId,
  });
  final ReadingLibrary library;
  final String collectionId;
  final CatalogIdentity? titleId;
  @override
  State<ReadingAnnotationsPage> createState() => _ReadingAnnotationsPageState();
}

class _ReadingAnnotationsPageState extends State<ReadingAnnotationsPage> {
  late final repository = widget.library.annotations;
  List<ReadingAnnotation> annotations = [];
  ReadingBundle? bundle;
  String? error;
  String query = '';
  List<ReadingPageNote> get pageNotes => (bundle?.management.pageNotes ?? [])
      .where(
        (n) =>
            n.collectionId == widget.collectionId &&
            (widget.titleId == null || n.titleId == widget.titleId!.entityId),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.collectionId);
      final b = await widget.library.readCollection(widget.collectionId);
      final values = await repository.read();
      if (mounted) {
        setState(() {
          bundle = b;
          annotations = values
              .where(
                (a) =>
                    a.title.collectionId == widget.collectionId &&
                    (widget.titleId == null || a.title == widget.titleId),
              )
              .toList();
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load bookmarks and notes. Retry.');
      }
    }
  }

  Future<void> remove(ReadingAnnotation note) async {
    try {
      await repository.remove(note);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Saved item removed'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                try {
                  await repository.save(note);
                  await load();
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => error = 'Could not restore this note. Retry.',
                    );
                  }
                }
              },
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not delete this saved item. It is retained.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bookmarks and notes')),
    body: !widget.library.authorized(widget.collectionId)
        ? const Center(child: Text('Collection access is required.'))
        : ListView(
            padding: AppSpacing.of(context).all(20),
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search saved items',
                ),
                onChanged: (v) => setState(() => query = v.toLowerCase()),
              ),
              if (error != null)
                TextButton(onPressed: load, child: Text(error!)),
              if (annotations.isEmpty && pageNotes.isEmpty && error == null)
                const Text('No bookmarks, highlights or notes yet.'),
              for (final note in pageNotes.where(
                (n) => '${n.label} ${n.note}'.toLowerCase().contains(query),
              ))
                Builder(
                  builder: (context) {
                    final title = bundle!.catalog.titles.singleWhere(
                      (t) =>
                          t.catalog.id.collectionId == widget.collectionId &&
                          t.catalog.id.entityId == note.titleId,
                    );
                    final matches = comicNoteMatches(note, title);
                    return ListTile(
                      title: Text(note.label),
                      subtitle: Text(
                        '${title.catalog.title} · ${matches ? note.note : 'Source changed · saved page retained'}',
                      ),
                      onTap: !matches
                          ? null
                          : () async {
                              await openComicReader(
                                context,
                                widget.library.readerHost,
                                title,
                                authorized: widget.library.authorized,
                                initialLocation: PageReadingLocation(
                                  pageId: note.pageId,
                                  pageIndex: note.pageIndex,
                                  offset: (note.offset as num).toDouble(),
                                ),
                              );
                              await load();
                            },
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit page note',
                            icon: const AppIcon(AppIconRole.edit),
                            onPressed: () async {
                              await editComicNote(
                                context,
                                widget.library,
                                note,
                              );
                              await load();
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete saved page',
                            icon: const AppIcon(AppIconRole.delete),
                            onPressed: () async {
                              try {
                                await removeComicNote(widget.library, note);
                                await load();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Saved page removed'),
                                      action: SnackBarAction(
                                        label: 'Undo',
                                        onPressed: () async {
                                          try {
                                            await widget.library
                                                .restorePageNote(
                                                  widget.collectionId,
                                                  note,
                                                );
                                            await load();
                                          } catch (_) {
                                            if (mounted) {
                                              setState(
                                                () => error = 'Could not restore the saved page. Retry.',
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => error = 'Could not delete the saved page. It is retained.',
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              for (final note in annotations.where(
                (a) => '${a.quote} ${a.note} ${a.label}'.toLowerCase().contains(
                  query,
                ),
              ))
                Builder(
                  builder: (context) {
                    final title = bundle!.catalog.titles.singleWhere(
                      (t) => t.catalog.id == note.title,
                    );
                    final matches = note.matches(title);
                    return ListTile(
                      title: Text(
                        note.label.isNotEmpty
                            ? note.label
                            : note.quote.isNotEmpty
                            ? note.quote
                            : 'Bookmark',
                      ),
                      subtitle: Text(
                        '${title.catalog.title}\n${matches ? note.note : 'Source changed · saved item retained'}',
                      ),
                      onTap: !matches
                          ? null
                          : () async {
                              await openEbookReader(
                                context,
                                widget.library.readerHost,
                                title,
                                authorized: widget.library.authorized,
                                initialLocation: TextReadingLocation(
                                  resourceId: note.resourceId,
                                  locatorType: TextLocatorType.textOffset,
                                  locator: '${note.start}',
                                  progression: 0,
                                  before: note.before,
                                  after: note.quote,
                                ),
                              );
                              await load();
                            },
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit saved note',
                            icon: const AppIcon(AppIconRole.edit),
                            onPressed: () => readingFields(
                              context,
                              title: 'Edit saved note',
                              initial: {'note': note.note, 'label': note.label},
                              multiline: {'note'},
                              labels: {'note': 'Note', 'label': 'Label'},
                              save: (v) async {
                                final updated = ReadingAnnotation.fromJson({
                                  ...note.toJson(),
                                  'note': v['note'],
                                  'label': v['label'],
                                });
                                await repository.save(updated);
                                await load();
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete saved item',
                            icon: const AppIcon(AppIconRole.delete),
                            onPressed: () => remove(note),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
  );
}
