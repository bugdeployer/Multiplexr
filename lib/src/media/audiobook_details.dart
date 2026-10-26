import '../experience/plugins/plugin_contribution_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import 'source_recovery.dart';
import '../experience/actions/catalog_actions.dart';
import '../experience/navigation/navigation_origin.dart';
import '../experience/actions/media_actions.dart';
import '../experience/navigation/navigation_coordinator.dart';
import '../settings/domain/media_settings.dart';
import '../experience/navigation/opening_policy.dart';
import 'audiobook_artwork_picker.dart';
import 'media_ui_patterns.dart';
import 'contracts.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:app_shell/app_shell.dart';

import '../library/library_models.dart';
import 'audio_library.dart';
import 'audio_models.dart';
import 'audiobook_cover.dart';
import 'audiobook_metadata.dart';
import 'audiobook_hierarchy.dart';
import 'navigation_settings.dart';

Future<void> chooseAudiobookArtwork(
  BuildContext context,
  AudioLibrary library,
  Audiobook book,
) async {
  if (!library.canAccess(book.id.collectionId)) return;
  final image = await chooseAudiobookCover(
    context,
    title: book.metadata.title,
    search: library.metadataSearch,
    imports: library.imports,
    download: library.downloadArtwork,
  );
  if (image == null || !library.canAccess(book.id.collectionId)) return;
  final latest = (await library.books())
      .where((b) => b.id == book.id)
      .firstOrNull;
  if (latest != null) {
    await library.replace(
      latest.withMetadata({'cover': image, 'coverSource': 'manual'}),
    );
  }
}

Future<void> openAudiobookTitle(
  BuildContext context,
  AudioLibrary library,
  VideoCollection? collection,
  Audiobook book,
  Future<void> Function(double rate) play,
  Future<void> Function() edit, {
  bool forcePlay = false,
  NavigationOrigin? origin,
  void Function(NavigationOrigin)? restore,
}) => NavigationCoordinator.forOwner(library.service.persistenceOwner).run(
  'audiobook:${book.id.key}:$forcePlay',
  () => _openAudiobookTitle(
    context,
    library,
    collection,
    book,
    play,
    edit,
    forcePlay: forcePlay,
  ),
  origin: origin,
  restore: restore,
);

Future<void> _openAudiobookTitle(
  BuildContext context,
  AudioLibrary library,
  VideoCollection? collection,
  Audiobook book,
  Future<void> Function(double rate) play,
  Future<void> Function() edit, {
  bool forcePlay = false,
}) async {
  if (!library.canAccess(book.id.collectionId)) return;
  Future<void> selectedPlayer(double rate, EngineSelection engine) async {
    if (engine == EngineSelection.external) {
      try {
        await library.imports.openAudio(book.files.first.uri);
      } on PlatformException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'Could not open external player.'),
            ),
          );
        }
      }
    } else {
      await play(rate);
    }
  }

  final effective = await resolveMediaNavigation(
    library.service,
    collection: collection,
    collectionId: book.id.collectionId,
    ancestorIds: ['series:${audiobookSeriesIdentity(book)}'],
    titleId: book.id.key,
  );
  final rate = effective.rate.value;
  if (!context.mounted || !library.canAccess(book.id.collectionId)) return;
  if (effective.destination(forcePlay: forcePlay) ==
      OpeningDestination.details) {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AudiobookDetailsPage(
          library: library,
          book: book,
          play: () => openAudiobookTitle(
            context,
            library,
            collection,
            book,
            play,
            edit,
            forcePlay: true,
          ),
          edit: edit,
        ),
      ),
    );
  } else {
    await selectedPlayer(rate, effective.engine.value);
  }
}

class AudiobookDetailsPage extends StatefulWidget {
  const AudiobookDetailsPage({
    super.key,
    required this.library,
    required this.book,
    required this.play,
    required this.edit,
  });
  final AudioLibrary library;
  final Audiobook book;
  final Future<void> Function() play, edit;
  @override
  State<AudiobookDetailsPage> createState() => _AudiobookDetailsPageState();
}

class _AudiobookDetailsPageState extends State<AudiobookDetailsPage> {
  late Audiobook book = widget.book;
  String? error;
  AudiobookProgress? progress;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    refresh().catchError((Object _) {
      if (mounted) {
        setState(() => error = 'Could not load audiobook progress. Try again.');
      }
    });
  }

  Future<void> refresh() async {
    final saved = await widget.library.progress.read(book.id);
    if (mounted) {
      setState(() => progress = saved is AudiobookProgress ? saved : null);
    }
    final current = (await widget.library.books())
        .where((b) => b.id == book.id)
        .firstOrNull;
    if (mounted && current != null) setState(() => book = current);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(book.metadata.title),
      actions: [
        AudiobookActionMenu(
          book: book,
          library: widget.library,
          edit: widget.edit,
          refresh: refresh,
        ),
      ],
    ),
    body: MediaDetailsBody(
      artwork: AudiobookCover(cover: book.metadata.cover),
      children: [
        PluginDetailExtensions(
          collection: book.id.collectionId,
          kind: ExtensionMedia.audiobook,
          titleId: book.id.itemId,
        ),
        Text(
          book.metadata.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (book.metadata.author.isNotEmpty) Text(book.metadata.author),
        if (book.metadata.narrator.isNotEmpty)
          Text('Narrated by ${book.metadata.narrator}'),
        const AppGap(12),
        Text(
          '${book.chapterMarkers.length} ${book.chapterMarkers.length == 1 ? 'chapter' : 'chapters'}${book.durationMs > 0 ? ' · ${Duration(milliseconds: book.durationMs).inMinutes} min' : ''}',
        ),
        const AppGap(20),
        FilledButton.icon(
          onPressed: opening
              ? null
              : () async {
                  setState(() {
                    opening = true;
                    error = null;
                  });
                  try {
                    await widget.play();
                    await refresh();
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => error = 'Could not open audiobook. Try again.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => opening = false);
                  }
                },
          icon: const AppIcon(AppIconRole.play),
          label: Text(
            opening
                ? 'Opening…'
                : progress != null &&
                      !progress!.finished &&
                      (progress!.positionMs > 0 ||
                          progress!.chapterId != book.chapterMarkers.first.id)
                ? 'Continue'
                : 'Play',
          ),
        ),
        const AppGap(20),
        if (error != null) Text(error!),
        if (book.metadata.description.isNotEmpty)
          Text(book.metadata.description),
        if (book.metadata.publisher.isNotEmpty) ...[
          const AppGap(20),
          Text('Publisher', style: Theme.of(context).textTheme.titleSmall),
          const AppGap(8),
          Text(book.metadata.publisher),
        ],
        if (book.metadata.publicationDate.isNotEmpty) ...[
          const AppGap(20),
          Text(
            'Publication date',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const AppGap(8),
          Text(book.metadata.publicationDate),
        ],
      ],
    ),
  );
}

/// The same action order is used in collection grids, series grids and details.
class AudiobookActionMenu extends StatelessWidget {
  const AudiobookActionMenu({
    super.key,
    required this.book,
    required this.library,
    required this.edit,
    required this.refresh,
    this.addTags,
    this.remove,
  });
  final Future<void> Function()? addTags, remove;
  final Audiobook book;
  final AudioLibrary library;
  final Future<void> Function() edit, refresh;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Audiobook menu',
    icon: const AppIcon(AppIconRole.menu),
    itemBuilder: (_) => catalogActionMenu(
      [
        ...mediaMetadataActions(
          settings: true,
          authorized: library.canAccess(book.id.collectionId),
        ),
        const PopupMenuItem(value: 'tags', child: Text('Edit tags')),
        const PopupMenuItem(value: 'health', child: Text('Folder health')),
        if (remove != null)
          const PopupMenuItem(value: 'remove', child: Text('Remove audiobook')),
      ],
      scope: CatalogActionScope.title,
      context: MediaActionContext(
        authorized: library.canAccess(book.id.collectionId),
        capabilities: appSubtypes
            .definition(MediaSubtype.audiobooks)
            .capabilities,
      ),
    ),
    onSelected: (value) async {
      if (!CatalogActionRegistry.permitted(
        CatalogActionScope.title,
        value,
        MediaActionContext(
          authorized: library.canAccess(book.id.collectionId),
          capabilities: appSubtypes
              .definition(MediaSubtype.audiobooks)
              .capabilities,
        ),
      )) {
        return;
      }
      try {
        final commonAction = switch (value) {
          'settings' => MediaActionId.settings,
          'edit' => MediaActionId.editMetadata,
          'artwork' => MediaActionId.chooseArtwork,
          'metadata' => MediaActionId.findMetadata,
          _ => null,
        };
        if (commonAction != null &&
            !MediaActionRegistry.permitted(
              commonAction,
              MediaActionContext(
                authorized: library.canAccess(book.id.collectionId),
                capabilities: appSubtypes
                    .definition(MediaSubtype.audiobooks)
                    .capabilities,
                hasSettings: true,
              ),
            )) {
          return;
        }

        switch (value) {
          case 'settings':
            await showMediaNavigationSettings(
              context,
              library.service,
              MediaNavigationSettings.key(book.id.collectionId, book.id.key),
              'Audiobook',
              ancestorIds: ['series:${audiobookSeriesIdentity(book)}'],
            );
          case 'health':
            await recoverCollectionSource(
              context,
              book.id.collectionId,
              authorized: () => library.canAccess(book.id.collectionId),
            );
          case 'tags':
            if (addTags != null) {
              await addTags!();
            } else {
              await editAudiobookTags(context, library, book);
            }
          case 'remove':
            await remove?.call();
          case 'edit':
            await edit();
          case 'artwork':
            await chooseAudiobookArtwork(context, library, book);
          case 'metadata':
            await findAudiobookMetadata(context, library, book);
        }
        await refresh();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save changes. Try again.')),
          );
        }
      }
    },
  );
}

Future<void> editAudiobookTags(
  BuildContext context,
  AudioLibrary library,
  Audiobook book,
) async {
  final text = TextEditingController(text: book.metadata.tags.join(', '));
  final selected = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Edit tags'),
      content: TextField(
        controller: text,
        decoration: const InputDecoration(
          labelText: 'Tags',
          helperText: 'Separate tags with commas.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, text.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  text.dispose();
  if (selected == null) return;
  final tags = selected
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();
  if (tags.any((v) => v.length > 80)) {
    throw ArgumentError('Tags must be 80 characters or fewer.');
  }
  await library.update(
    (current) => [
      for (final value in current)
        value.id == book.id ? value.withMetadata({'tags': tags}) : value,
    ],
  );
}
