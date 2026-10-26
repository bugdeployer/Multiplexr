import 'package:app_shell/app_shell.dart' show AppSpacing;

import 'package:flutter/material.dart';

import '../experience/plugins/plugin_artwork_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../features/sources/application/media_imports.dart';
import '../features/metadata/application/metadata_workflow.dart';
import '../features/metadata/application/artwork_service.dart';
import 'audio_models.dart';
import 'audiobook_cover.dart';

Future<String?> chooseSeriesArtwork(
  BuildContext context, {
  required MetadataWorkflow search,
  required MediaImports imports,
  required ArtworkDownload download,
  required String title,
  required List<Audiobook> books,
}) => Navigator.push<String>(
  context,
  MaterialPageRoute(
    builder: (_) => AudiobookSeriesArtworkPicker(
      title: title,
      books: books,
      imports: imports,
      search: search,
      download: download,
    ),
  ),
);

Future<String?> chooseAudiobookCover(
  BuildContext context, {
  required MetadataWorkflow search,
  required MediaImports imports,
  required ArtworkDownload download,
  required String title,
}) => Navigator.push<String>(
  context,
  MaterialPageRoute(
    builder: (_) => AudiobookSeriesArtworkPicker(
      title: title,
      books: const [],
      fromDevice: true,
      imports: imports,
      search: search,
      download: download,
    ),
  ),
);

class AudiobookSeriesArtworkPicker extends StatefulWidget {
  const AudiobookSeriesArtworkPicker({
    super.key,
    required this.imports,
    required this.search,
    required this.download,
    required this.title,
    required this.books,
    this.fromDevice = false,
  });
  final MetadataWorkflow search;
  final MediaImports imports;
  final ArtworkDownload download;
  final String title;
  final List<Audiobook> books;
  final bool fromDevice;
  @override
  State<AudiobookSeriesArtworkPicker> createState() => _ArtworkPickerState();
}

class _ArtworkPickerState extends State<AudiobookSeriesArtworkPicker> {
  bool busy = false;
  String? error;
  Future<void> device() async {
    setState(() => busy = true);
    try {
      final image = await widget.imports.cover();
      if (mounted && image != null) {
        Navigator.pop(context, image);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not open the selected image.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> online() async {
    final first = widget.books.firstOrNull;
    final image = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => first == null
            ? PluginCollectionArtworkFinder(
                kind: ExtensionMedia.audiobook,
                title: widget.title,
              )
            : PluginArtworkPage(
                collection: first.id.collectionId,
                kind: ExtensionMedia.audiobook,
                titleId: first.id.itemId,
                title: widget.title,
              ),
      ),
    );
    if (mounted && image != null) {
      Navigator.pop(context, image);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.fromDevice ? 'Choose artwork' : 'Choose series artwork',
      ),
    ),
    body: ListView(
      padding: AppSpacing.of(context).all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        OutlinedButton(
          onPressed: busy ? null : device,
          child: const Text('Select image from device'),
        ),
        OutlinedButton(
          onPressed: busy ? null : online,
          child: const Text('Find artwork with a plugin'),
        ),
        for (final book in widget.books.where(
          (b) => b.metadata.cover.isNotEmpty,
        ))
          ListTile(
            leading: SizedBox.square(
              dimension: 64,
              child: AudiobookCover(cover: book.metadata.cover),
            ),
            title: Text(book.metadata.title),
            subtitle: const Text('Use artwork from this audiobook'),
            onTap: busy
                ? null
                : () => Navigator.pop(context, book.metadata.cover),
          ),
      ],
    ),
  );
}
