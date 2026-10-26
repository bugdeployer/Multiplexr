import 'package:app_shell/app_shell.dart' show AppSpacing;

import '../experience/plugins/plugin_artwork_page.dart';
import 'media_cover.dart';
import '../experience/plugins/plugin_metadata_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../features/sources/application/media_imports.dart';

import 'package:flutter/material.dart';

import '../features/metadata/application/metadata_contracts.dart';
import '../metadata/metadata_review_page.dart';
import '../features/metadata/application/publication_provider.dart';
import '../features/metadata/application/music_metadata_target.dart';
import '../features/catalog/application/music_catalog_commands.dart';

class MusicMetadataFinder extends StatefulWidget {
  const MusicMetadataFinder({
    super.key,
    required this.provider,
    required this.entity,
    required this.title,
    this.artist = '',
  });
  final MusicProvider provider;
  final MetadataEntityType entity;
  final String title, artist;
  @override
  State<MusicMetadataFinder> createState() => _MusicMetadataFinderState();
}

class _MusicMetadataFinderState extends State<MusicMetadataFinder> {
  @override
  Widget build(BuildContext context) => PluginCollectionMetadataFinder(
    kind: ExtensionMedia.music,
    entity: widget.entity,
    query: widget.title,
  );
}

Future<MetadataCandidate?> findMusicMetadata(
  BuildContext context,
  MusicProvider provider, {
  required MetadataEntityType entity,
  required String title,
  String artist = '',
}) => Navigator.push<MetadataCandidate>(
  context,
  MaterialPageRoute(
    builder: (_) => MusicMetadataFinder(
      provider: provider,
      entity: entity,
      title: title,
      artist: artist,
    ),
  ),
);

Future<bool> reviewMusicMetadata(
  BuildContext context,
  MusicMetadataTarget target,
  MetadataCandidate candidate,
) async =>
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MetadataReviewPage(target: target, candidate: candidate),
      ),
    ) ==
    true;

Future<String?> chooseMusicArtwork(
  BuildContext context,
  MusicProvider provider, {
  required String title,
  required String artist,
  required MediaImports imports,
  MusicAlbum? album,
}) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('Find artwork online'),
            onTap: () => Navigator.pop(sheet, 'online'),
          ),
          ListTile(
            title: const Text('Select image from device'),
            onTap: () => Navigator.pop(sheet, 'device'),
          ),
          if (album != null)
            ListTile(
              title: const Text('Select from tracks in this album'),
              onTap: () => Navigator.pop(sheet, 'tracks'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || source == null) return null;
  String? image;
  if (source == 'device') {
    image = await imports.cover();
  } else {
    List<String> covers;
    if (source == 'tracks') {
      covers = album!.tracks
          .map((t) => t.metadata.cover)
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
    } else {
      final selected = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => PluginCollectionArtworkFinder(
            kind: ExtensionMedia.music,
            title: title,
          ),
        ),
      );
      if (!context.mounted || selected == null) {
        return null;
      }
      image = selected;
      covers = [];
    }
    if (!context.mounted) return null;
    if (image == null && covers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No artwork found. Try another release or select a device image.',
          ),
        ),
      );
      return null;
    }
    image ??= await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (page) => Scaffold(
          appBar: AppBar(title: const Text('Choose artwork')),
          body: GridView.extent(
            maxCrossAxisExtent: 220,
            padding: AppSpacing.of(context).all(20),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              for (final cover in covers)
                InkWell(
                  onTap: () => Navigator.pop(page, cover),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: MediaCover(cover: cover),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  if (!context.mounted || image == null || image.isEmpty) return null;
  final selected = image;
  final use = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Artwork preview'),
      content: SizedBox(
        width: 320,
        child: AspectRatio(aspectRatio: 1, child: MediaCover(cover: selected)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Use image'),
        ),
      ],
    ),
  );
  return use == true ? selected : null;
}
