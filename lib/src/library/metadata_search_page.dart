import 'package:flutter/material.dart';

import '../experience/plugins/plugin_metadata_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../features/metadata/application/metadata_contracts.dart';
import 'library_models.dart';
import 'library_controller.dart';

class VideoMetadataSearchPage extends StatelessWidget {
  const VideoMetadataSearchPage({
    super.key,
    required this.library,
    required this.asset,
    required this.query,
    this.selectOnly = false,
  });
  final LibraryController library;
  final VideoAsset asset;
  final String query;
  final bool selectOnly;
  @override
  Widget build(BuildContext context) => PluginMetadataPage(
    collection: asset.collectionId,
    kind: asset.mediaSubtype == VideoSubtype.tv
        ? ExtensionMedia.television
        : ExtensionMedia.movie,
    entity: asset.mediaSubtype == VideoSubtype.tv
        ? MetadataEntityType.television
        : MetadataEntityType.movie,
    query: query,
    target: library.metadataJobs.target(asset),
    selectOnly: selectOnly,
  );
}
