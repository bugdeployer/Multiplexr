import '../settings/domain/media_settings.dart' show SettingsScope;
import '../experience/actions/catalog_actions.dart';
import '../experience/actions/media_actions.dart';
import 'media_ui_patterns.dart';
import 'audiobook_artwork_picker.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'audio_models.dart';
import 'audio_library.dart';
import 'audiobook_group_repository.dart';
import '../catalog/domain/catalog_models.dart';
import 'audiobook_cover.dart';
import 'grouping.dart';
import 'contracts.dart';
import 'audiobook_hierarchy.dart';
export 'audiobook_hierarchy.dart';
import 'navigation_settings.dart';
import 'audiobook_details.dart';

Future<String?> bookText(
  BuildContext context,
  String title, {
  String initial = '',
  bool empty = false,
}) async {
  final input = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(controller: input, autofocus: true, maxLength: 200),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (empty || input.text.trim().isNotEmpty) {
              Navigator.pop(dialog, input.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  input.dispose();
  return result;
}

Future<void> updateAudiobookSelection(
  AudioLibrary library,
  List<Audiobook> selected,
  Audiobook Function(Audiobook, int) change,
) async {
  final ids = selected.map((b) => b.id).toSet();
  var i = 0;
  await library.update(
    (current) => [
      for (final book in current)
        ids.contains(book.id) ? change(book, i++) : book,
    ],
  );
}

Future<void> tagSelectedAudiobooks(
  BuildContext context,
  AudioLibrary library,
  List<Audiobook> selected,
) async {
  if (selected.isEmpty) return;
  final text = await bookText(context, 'Add tags (comma separated)');
  if (text == null) return;
  final tags = text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet();
  await updateAudiobookSelection(
    library,
    selected,
    (b, _) => b.withMetadata({
      'tags': {...b.metadata.tags, ...tags}.toList(),
    }),
  );
}

Future<void> manageAudiobookTags(
  BuildContext context,
  AudioLibrary library,
) async {
  final books = await library.books();
  if (!context.mounted) return;
  final tags = books.expand((b) => b.metadata.tags).toSet().toList()..sort();
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheet) => ListView(
      shrinkWrap: true,
      padding: AppSpacing.of(context).all(20),
      children: [
        Text('Manage tags', style: Theme.of(sheet).textTheme.titleLarge),
        if (tags.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Select books to add tags.'),
          ),
        for (final tag in tags)
          ListTile(
            title: Text(tag),
            trailing: PopupMenuButton<String>(
              icon: const AppIcon(AppIconRole.menu),
              onSelected: (action) async {
                String? replacement;
                if (action != 'delete') {
                  replacement = await bookText(
                    sheet,
                    'Rename or merge tag',
                    initial: tag,
                  );
                }
                if (action != 'delete' && replacement == null) return;
                await library.update(
                  (current) => [
                    for (final b in current)
                      b.withMetadata({
                        'tags': {
                          for (final value in b.metadata.tags)
                            if (value != tag)
                              value
                            else if (replacement != null &&
                                replacement.isNotEmpty)
                              replacement,
                        }.toList(),
                      }),
                  ],
                );
                if (sheet.mounted) Navigator.pop(sheet);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename / merge')),
                PopupMenuItem(value: 'delete', child: Text('Delete tag')),
              ],
            ),
          ),
      ],
    ),
  );
}

class AudiobookSeriesPage extends StatefulWidget {
  const AudiobookSeriesPage({
    super.key,
    required this.group,
    required this.library,
    required this.openBook,
    required this.editBook,
    this.playBook,
  });
  final MediaGroup<Audiobook> group;
  final AudioLibrary library;
  final Future<void> Function(Audiobook) openBook, editBook;
  final Future<void> Function(Audiobook)? playBook;
  @override
  State<AudiobookSeriesPage> createState() => _AudiobookSeriesPageState();
}

class _AudiobookSeriesPageState extends State<AudiobookSeriesPage> {
  late List<Audiobook> books = widget.group.children;
  String? error;
  AudiobookSeriesMetadata? metadata;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> editMetadata() async {
    final title = TextEditingController(
      text: metadata?.title ?? widget.group.title,
    );
    final author = TextEditingController(
      text: metadata?.author ?? books.firstOrNull?.metadata.author ?? '',
    );
    final description = TextEditingController(
      text: metadata?.description ?? '',
    );
    var cover = metadata?.cover ?? '';
    final save = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('Series metadata'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const AppGap(16),
                  TextField(
                    controller: author,
                    decoration: const InputDecoration(labelText: 'Author'),
                  ),
                  const AppGap(16),
                  TextField(
                    controller: description,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const AppGap(16),
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: AudiobookCover(cover: cover),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        final chosen = await chooseSeriesArtwork(
                          dialog,
                          search: widget.library.metadataSearch,
                          imports: widget.library.imports,
                          download: widget.library.downloadArtwork,
                          title: title.text.trim(),
                          books: books,
                        );
                        if (chosen != null && dialog.mounted) {
                          update(() => cover = chosen);
                        }
                      } catch (_) {
                        if (dialog.mounted) {
                          ScaffoldMessenger.of(dialog).showSnackBar(
                            const SnackBar(
                              content: Text('Could not read cover image.'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Choose cover'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isNotEmpty) Navigator.pop(dialog, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await widget.library.saveSeriesMetadata(
        AudiobookSeriesMetadata(
          id: widget.group.id,
          collectionId: books.first.id.collectionId,
          title: title.text.trim(),
          author: author.text.trim(),
          description: description.text.trim(),
          cover: cover,
        ),
      );
    }
    title.dispose();
    author.dispose();
    description.dispose();
  }

  Future<void> refresh() async {
    final all = await widget.library.books();
    final saved = await widget.library.seriesMetadata(widget.group.id);
    if (mounted) {
      metadata = saved;
      setState(
        () => books =
            audiobookSeries(all)
                .where((g) => g.id == widget.group.id)
                .firstOrNull
                ?.children ??
            [],
      );
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (books.any((b) => !widget.library.canAccess(b.id.collectionId))) return;
    try {
      await action();
      await refresh();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save series changes. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(metadata?.title ?? widget.group.title),
      actions: [
        PopupMenuButton<String>(
          icon: const AppIcon(AppIconRole.menu),
          onSelected: (action) => perform(() async {
            if (!CatalogActionRegistry.permitted(
              CatalogActionScope.group,
              action,
              MediaActionContext(
                authorized: books.every(
                  (b) => widget.library.canAccess(b.id.collectionId),
                ),
                capabilities: appSubtypes
                    .definition(MediaSubtype.audiobooks)
                    .capabilities,
              ),
            )) {
              return;
            }
            if (action == 'metadata') {
              await editMetadata();
            } else if (action == 'order') {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupOrderPage<Audiobook>(
                    title: 'Book order',
                    items: books,
                    identity: (b) => b.id.key,
                    label: (b) => b.metadata.title,
                    save: (ordered) =>
                        AudiobookGroupRepository(widget.library).reorder(
                          CatalogIdentity(
                            books.first.id.collectionId,
                            widget.group.id,
                            CatalogEntityKind.group,
                          ),
                          ordered.map(audiobookTitleIdentity).toList(),
                        ),
                  ),
                ),
              );
            } else if (action == 'settings') {
              await showMediaNavigationSettings(
                context,
                widget.library.service,
                MediaNavigationSettings.key(
                  books.first.id.collectionId,
                  'series:${widget.group.id}',
                ),
                'Series',
                targetScope: SettingsScope.group,
              );
            } else if (action == 'artwork') {
              final image = await chooseSeriesArtwork(
                context,
                search: widget.library.metadataSearch,
                imports: widget.library.imports,
                download: widget.library.downloadArtwork,
                title: metadata?.title ?? widget.group.title,
                books: books,
              );
              if (image != null) {
                await widget.library.saveSeriesMetadata(
                  AudiobookSeriesMetadata(
                    id: widget.group.id,
                    collectionId: books.first.id.collectionId,
                    title: metadata?.title ?? widget.group.title,
                    author: metadata?.author ?? '',
                    description: metadata?.description ?? '',
                    cover: image,
                  ),
                );
              }
            }
          }),
          tooltip: 'Series menu',
          itemBuilder: (_) => catalogActionMenu(
            [
              ...mediaMetadataActions(
                settings: true,
                authorized: books.every(
                  (b) => widget.library.canAccess(b.id.collectionId),
                ),
                edit: 'metadata',
                includeFind: false,
              ),
              const PopupMenuItem(value: 'order', child: Text('Reorder books')),
            ],
            scope: CatalogActionScope.group,
            context: MediaActionContext(
              authorized: books.every(
                (b) => widget.library.canAccess(b.id.collectionId),
              ),
              capabilities: appSubtypes
                  .definition(MediaSubtype.audiobooks)
                  .capabilities,
            ),
          ),
        ),
      ],
    ),
    body: ListView(
      children: [
        if (error != null) Text(error!),
        if (books.isEmpty) const Text('No books in this series.'),
        if (books.isNotEmpty) ...[
          AspectRatio(
            aspectRatio: 1,
            child: AudiobookCover(
              cover: metadata?.cover.isNotEmpty == true
                  ? metadata!.cover
                  : books.first.metadata.cover,
            ),
          ),
          Padding(
            padding: AppSpacing.of(context).all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppGap(20),
                Text(
                  metadata?.title ?? widget.group.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if ((metadata?.author ?? books.first.metadata.author)
                    .isNotEmpty)
                  Text(metadata?.author ?? books.first.metadata.author),
                if (metadata?.description.isNotEmpty == true) ...[
                  const AppGap(16),
                  Text(metadata!.description),
                ],
                const AppGap(24),
                if (books.isNotEmpty)
                  FilledButton.icon(
                    icon: const AppIcon(AppIconRole.play),
                    label: const Text('Continue series'),
                    onPressed: () async {
                      final saved = <MediaId, AudiobookProgress>{};
                      for (final book in books) {
                        final progress = await widget.library.progress.read(
                          book.id,
                        );
                        if (progress is AudiobookProgress) {
                          saved[book.id] = progress;
                        }
                      }
                      final target = audiobookResumeTarget(books, saved);
                      if (context.mounted && target != null) {
                        await (widget.playBook ?? widget.openBook)(target);
                        await refresh();
                      }
                    },
                  ),
                const AppGap(24),
                Text(
                  '${books.length} ${books.length == 1 ? 'audiobook' : 'audiobooks'}',
                ),
                const AppGap(12),
                MediaArtworkGrid(
                  children: [
                    for (final book in books)
                      AudiobookArtworkTile(
                        title: book.metadata.title,
                        menu: AudiobookActionMenu(
                          book: book,
                          library: widget.library,
                          edit: () => widget.editBook(book),
                          refresh: refresh,
                        ),
                        cover: book.metadata.cover,
                        onTap: () => widget.openBook(book),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
