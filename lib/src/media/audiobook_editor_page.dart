import 'audiobook_cover.dart';
import 'audiobook_artwork_picker.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'audio_library.dart';
import 'audio_models.dart';
import 'audio_time.dart';
import 'cue_chapters.dart';

class AudiobookEditorPage extends StatefulWidget {
  const AudiobookEditorPage({
    super.key,
    required this.library,
    required this.files,
    this.existing,
    this.reconnect = false,
  });
  final AudioLibrary library;
  final List<AudioFile> files;
  final Audiobook? existing;
  final bool reconnect;
  @override
  State<AudiobookEditorPage> createState() => _AudiobookEditorPageState();
}

class _AudiobookEditorPageState extends State<AudiobookEditorPage> {
  final form = GlobalKey<FormState>();
  late final files = [...widget.files];
  late List<AudiobookChapterMarker>? markers = widget.existing?.chapterMarkers;
  late final title = TextEditingController(
    text:
        widget.existing?.metadata.title ??
        (files.first.album.isNotEmpty
            ? files.first.album
            : files.length == 1
            ? files.first.displayTitle
            : ''),
  );
  late final author = TextEditingController(
    text: widget.existing?.metadata.author ?? files.first.author,
  );
  late final narrator = TextEditingController(
    text: widget.existing?.metadata.narrator,
  );
  late final series = TextEditingController(
    text: widget.existing?.metadata.series,
  );
  late final seriesOrder = TextEditingController(
    text: widget.existing?.metadata.seriesOrder == 0
        ? ''
        : '${widget.existing?.metadata.seriesOrder ?? 0}',
  );
  late String cover = widget.existing?.metadata.cover ?? '';
  bool fileOrderChanged = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    series.dispose();
    seriesOrder.dispose();
    title.dispose();
    author.dispose();
    narrator.dispose();
    super.dispose();
  }

  Future<void> importChapters() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final text = await widget.library.imports.chapterDocument();
      if (text != null && mounted) {
        final parsed = parseCueChapters(text, files);
        setState(() => markers = parsed);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is ArgumentError
              ? 'Chapter ranges overlap or exceed an audio file.'
              : 'Could not import CUE chapters.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final metadata = AudiobookMetadata.fromJson({
        ...?widget.existing?.metadata.toJson(),
        'title': title.text.trim(),
        'author': author.text.trim(),
        'narrator': narrator.text.trim(),
        'series': series.text.trim(),
        'seriesId': series.text.trim() == widget.existing?.metadata.series
            ? widget.existing!.metadata.seriesId
            : series.text.trim().toLowerCase(),
        'seriesOrder': double.tryParse(seriesOrder.text) ?? 0,
        'cover': cover,
        'coverSource': 'manual',
        'metadataSource': 'manual',
      });
      if (widget.existing == null) {
        await widget.library.add(metadata, files, chapters: markers);
      } else {
        final ordered = widget.reconnect
            ? [
                for (var i = 0; i < files.length; i++)
                  AudioFile.fromJson({
                    ...files[i].toJson(),
                    'id': widget.existing!.files[i].id,
                  }),
              ]
            : files;
        await widget.library.replace(
          Audiobook(
            id: widget.existing!.id,
            metadata: metadata,
            files: ordered,
            chapters: !widget.reconnect && !fileOrderChanged
                ? markers
                : [
                    for (final file in ordered)
                      ...(markers ?? widget.existing!.chapterMarkers).where(
                        (c) => c.fileId == file.id,
                      ),
                  ],
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is StateError
              ? e.message.toString()
              : 'Could not save this book.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null
            ? 'Import book'
            : widget.reconnect
            ? 'Reconnect book'
            : 'Edit book',
      ),
    ),
    body: Form(
      key: form,
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView(
              padding: AppSpacing.of(context).all(20),
              buildDefaultDragHandles: false,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Book title'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter a book title'
                        : null,
                  ),
                  const AppGap(12),
                  TextFormField(
                    controller: author,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Author'),
                  ),
                  const AppGap(12),
                  TextFormField(
                    controller: narrator,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Narrator'),
                  ),
                  const AppGap(20),
                  if (widget.existing == null && !widget.reconnect) ...[
                    OutlinedButton(
                      onPressed: busy ? null : importChapters,
                      child: const Text('Import CUE chapters'),
                    ),
                    if (markers != null)
                      TextButton(
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => DraggableScrollableSheet(
                            expand: false,
                            builder: (_, scroll) => ListView(
                              controller: scroll,
                              padding: AppSpacing.of(context).all(20),
                              children: [
                                Text('${markers!.length} chapters'),
                                for (final c in markers!)
                                  ListTile(
                                    title: Text(c.title),
                                    subtitle: Text(audioTime(c.startMs)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        child: Text('Review ${markers!.length} chapters'),
                      ),
                    const AppGap(12),
                  ],
                  const AppGap(16),
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: AudiobookCover(cover: cover),
                  ),
                  TextButton.icon(
                    icon: const AppIcon(AppIconRole.artwork),
                    label: const Text('Choose artwork'),
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              final image = await chooseAudiobookCover(
                                context,
                                search: widget.library.metadataSearch,
                                imports: widget.library.imports,
                                download: widget.library.downloadArtwork,
                                title: title.text.trim(),
                              );
                              if (image != null && mounted) {
                                setState(() => cover = image);
                              }
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => error = 'Could not read cover image.',
                                );
                              }
                            }
                          },
                  ),
                  if (cover.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => cover = ''),
                      child: const Text('Remove cover'),
                    ),
                  if (widget.existing == null) const Text('Chapter order'),
                  const AppGap(12),
                ],
              ),
              onReorderItem: busy
                  ? (_, _) {}
                  : (oldIndex, newIndex) => setState(() {
                      fileOrderChanged = true;
                      files.insert(newIndex, files.removeAt(oldIndex));
                    }),
              children: [
                if (widget.existing == null)
                  for (var i = 0; i < files.length; i++)
                    ListTile(
                      key: ValueKey(files[i].uri),
                      title: Text(files[i].displayTitle),
                      subtitle: Text(audioTime(files[i].durationMs)),
                      leading: Text('${i + 1}'),
                      trailing: ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: AppIcon(AppIconRole.drag),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: AppSpacing.of(context).all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) Text(error!),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(
                      busy
                          ? 'Saving…'
                          : widget.existing == null
                          ? 'Add book'
                          : 'Save book',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
