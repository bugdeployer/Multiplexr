import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import '../features/catalog/application/reading_catalog_commands.dart';
import 'reading_workflow_widgets.dart';

bool comicNoteMatches(ReadingPageNote note, ReadingTitle title) =>
    note.sourceId == title.catalog.sources.single.id &&
    note.sourceRevision == title.sourceRevision &&
    (note.pageIndex) < title.readingOrder.length &&
    title.readingOrder[note.pageIndex].id == note.pageId;

Future<void> addComicNote(
  BuildContext context,
  ReadingCatalogCommands library,
  ReadingTitle title,
  PageReadingLocation location, {
  required bool bookmark,
}) async {
  final id =
      'page-note-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  Future<void> save(Map<String, String> fields) => library.addPageNote(
    title,
    location,
    id: id,
    bookmark: bookmark,
    note: fields['note'] ?? '',
    label: fields['label'],
  );
  if (bookmark) {
    await save({});
  } else {
    await readingFields(
      context,
      title: 'Add page note',
      initial: {'note': '', 'label': 'Page ${location.pageIndex + 1}'},
      multiline: {'note'},
      labels: {'note': 'Note', 'label': 'Label'},
      save: save,
    );
  }
}

int _sequence = 0;

Future<void> editComicNote(
  BuildContext context,
  ReadingCatalogCommands library,
  ReadingPageNote note,
) => readingFields(
  context,
  title: 'Edit page note',
  initial: {'note': note.note, 'label': note.label},
  multiline: {'note'},
  labels: {'note': 'Note', 'label': 'Label'},
  save: (v) => library.editPageNote(
    note.collectionId,
    note.id,
    note: v['note']!,
    label: v['label']!,
  ),
);

Future<void> removeComicNote(
  ReadingCatalogCommands library,
  ReadingPageNote note,
) => library.removePageNote(note.collectionId, note.id);

Future<PageReadingLocation?> showComicNotes(
  BuildContext context,
  ReadingCatalogCommands library,
  ReadingTitle title,
) async {
  return showDialog<PageReadingLocation>(
    context: context,
    builder: (_) => _ComicNotesDialog(library: library, title: title),
  );
}

class _ComicNotesDialog extends StatefulWidget {
  const _ComicNotesDialog({required this.library, required this.title});
  final ReadingCatalogCommands library;
  final ReadingTitle title;
  @override
  State<_ComicNotesDialog> createState() => _ComicNotesDialogState();
}

class _ComicNotesDialogState extends State<_ComicNotesDialog> {
  List<ReadingPageNote> notes = [];
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.title.catalog.id.collectionId);
      final b = await widget.library.read();
      if (mounted) {
        setState(() {
          notes = b.management.pageNotes
              .where(
                (n) =>
                    n.collectionId == widget.title.catalog.id.collectionId &&
                    n.titleId == widget.title.catalog.id.entityId,
              )
              .toList();
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load saved pages. Retry.');
    }
  }

  Future<void> remove(ReadingPageNote note) async {
    try {
      await removeComicNote(widget.library, note);
      await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not delete the saved page. It is retained.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SimpleDialog(
    title: const Text('Saved pages and notes'),
    children: [
      if (error != null) TextButton(onPressed: load, child: Text(error!)),
      SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .6,
        child: ListView(
          children: [
            if (notes.isEmpty && error == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No saved pages yet.'),
              ),
            for (final note in notes)
              ListTile(
                title: Text(note.label),
                subtitle: Text(
                  comicNoteMatches(note, widget.title)
                      ? note.note
                      : 'Source changed · saved page retained',
                ),
                onTap: !comicNoteMatches(note, widget.title)
                    ? null
                    : () => Navigator.pop(
                        context,
                        PageReadingLocation(
                          pageId: note.pageId,
                          pageIndex: note.pageIndex,
                          offset: (note.offset as num).toDouble(),
                        ),
                      ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Edit page note',
                      icon: const AppIcon(AppIconRole.edit),
                      onPressed: () async {
                        await editComicNote(context, widget.library, note);
                        await load();
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete saved page',
                      icon: const AppIcon(AppIconRole.delete),
                      onPressed: () => remove(note),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
