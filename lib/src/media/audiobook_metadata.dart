import '../features/metadata/application/metadata_workflow.dart';
import '../experience/plugins/plugin_metadata_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../features/metadata/application/metadata_contracts.dart';
import '../features/metadata/application/audiobook_metadata_target.dart';
import '../metadata/metadata_review_page.dart';

import 'package:flutter/material.dart';

import 'audio_models.dart';
import 'audio_library.dart';
import 'audiobook_cover.dart';

class AudiobookCandidateCover extends StatelessWidget {
  const AudiobookCandidateCover({super.key, required this.url});
  final String url;
  @override
  Widget build(BuildContext context) => url.startsWith('https://')
      ? Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => const AudiobookCover(cover: ''),
        )
      : const AudiobookCover(cover: '');
}

Future<bool> findAudiobookMetadata(
  BuildContext context,
  AudioLibrary library,
  Audiobook book, {
  List<Map<String, dynamic>>? candidates,
}) async =>
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AudiobookMetadataSearchPage(
          library: library,
          book: book,
          candidates: candidates,
        ),
      ),
    ) ==
    true;

class AudiobookMetadataSearchPage extends StatefulWidget {
  const AudiobookMetadataSearchPage({
    super.key,
    required this.library,
    required this.book,
    this.candidates,
  });
  final AudioLibrary library;
  final Audiobook book;
  final List<Map<String, dynamic>>? candidates;
  @override
  State<AudiobookMetadataSearchPage> createState() =>
      _AudiobookMetadataSearchPageState();
}

class _AudiobookMetadataSearchPageState
    extends State<AudiobookMetadataSearchPage> {
  @override
  Widget build(BuildContext context) => PluginMetadataPage(
    collection: widget.book.id.collectionId,
    kind: ExtensionMedia.audiobook,
    entity: MetadataEntityType.audiobook,
    query: widget.book.metadata.title,
    target: AudiobookMetadataTarget(widget.library, widget.book.id),
  );
}

class AudiobookMetadataReviewPage extends StatelessWidget {
  const AudiobookMetadataReviewPage({
    super.key,
    required this.library,
    required this.book,
    required this.match,
    this.workflow,
  });
  final AudioLibrary library;
  final Audiobook book;
  final Map<String, dynamic> match;
  final MetadataWorkflow? workflow;
  @override
  Widget build(BuildContext context) => MetadataReviewPage(
    title: 'Review audiobook match',
    workflow: workflow,
    target: AudiobookMetadataTarget(library, book.id),
    candidate: MetadataCandidate(
      provider: match['metadataSource'] ?? 'imported',
      id: '${match['providerId'] ?? ''}',
      entity: MetadataEntityType.audiobook,
      values: match,
      attribution: match['metadataSource'] as String? ?? 'Imported metadata',
    ),
  );
}
