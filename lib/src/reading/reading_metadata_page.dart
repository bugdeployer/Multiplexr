import 'package:app_shell/app_shell.dart' show AppSpacing;

import '../experience/plugins/plugin_artwork_page.dart';
import '../experience/plugins/plugin_metadata_page.dart';
import '../features/catalog/application/extension_catalog.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../features/metadata/application/artwork_service.dart';
import '../features/metadata/application/metadata_contracts.dart';
import 'reading_library.dart';
import '../features/metadata/application/publication_provider.dart';
import '../features/metadata/application/reading_metadata_target.dart';
import 'reading_workflow_widgets.dart';

class ReadingMetadataPage extends StatefulWidget {
  const ReadingMetadataPage({
    super.key,
    required this.target,
    this.artworkOnly = false,
  });
  final ReadingMetadataTarget target;
  final bool artworkOnly;
  @override
  State<ReadingMetadataPage> createState() => _ReadingMetadataPageState();
}

class _ReadingMetadataPageState extends State<ReadingMetadataPage> {
  late final initial = widget.target.initialize().then(
    (_) => widget.target.read(),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<MetadataSnapshot>(
    future: initial,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(child: Text('Collection access is unavailable.')),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final entity = widget.target.entity;
      return PluginMetadataPage(
        collection: widget.target.identity.collectionId,
        kind: entity == MetadataEntityType.ebook
            ? ExtensionMedia.ebook
            : ExtensionMedia.comic,
        entity: entity,
        query: snapshot.data!.fields['title'] as String? ?? '',
        target: widget.target,
      );
    },
  );
}

class ReadingArtworkPage extends StatefulWidget {
  const ReadingArtworkPage({
    super.key,
    required this.library,
    required this.identity,
    required this.provider,
  });
  final ReadingLibrary library;
  final CatalogIdentity identity;
  final PublicationProvider provider;
  @override
  State<ReadingArtworkPage> createState() => _ReadingArtworkPageState();
}

class _ReadingArtworkPageState extends State<ReadingArtworkPage> {
  final service = ArtworkService();
  final cancellation = MetadataCancellation();
  ReadingBundle? bundle;
  String reference = '', mode = 'fit';
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      widget.library.access(widget.identity.collectionId);
      final b = await widget.library.read();
      widget.library.access(widget.identity.collectionId);
      final managed = b.management.entity(widget.identity);
      if (mounted) {
        setState(() {
          bundle = b;
          reference = readingCoverReference(b, widget.identity);
          mode = managed.coverMode;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not load artwork.';
        });
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is MetadataFailure
              ? e.message
              : 'Could not save artwork. Your selection is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> device() => run(() async {
    final encoded = await widget.library.imports.cover();
    if (encoded == null) return;
    if (!encoded.startsWith('data:image/jpeg;base64,') ||
        encoded.length > 2000000) {
      throw const FormatException('Invalid selected cover');
    }
    final local = await service.select(
      ArtworkCandidate(
        location: encoded,
        role: ArtworkRole.poster,
        source: ArtworkSource.device,
        ownerId: widget.identity.entityId,
      ),
      cancellation,
    );
    final saved = await widget.library.storeArtwork(
      Uint8List.fromList(base64Decode(local.substring(23))),
    );
    widget.library.access(widget.identity.collectionId);
    if (mounted) setState(() => reference = saved);
  });
  Future<void> online() => run(() async {
    widget.library.access(widget.identity.collectionId);
    final target = await ReadingMetadataTarget(
      widget.library,
      widget.identity,
      widget.provider,
    ).initialize();
    if (!mounted) {
      return;
    }
    final encoded = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PluginArtworkPage(
          collection: widget.identity.collectionId,
          kind: target.entity == MetadataEntityType.ebook
              ? ExtensionMedia.ebook
              : ExtensionMedia.comic,
          titleId: widget.identity.entityId,
          title:
              (bundle?.catalog.titles
                          .where((t) => t.catalog.id == widget.identity)
                          .firstOrNull
                          ?.catalog
                          .metadata
                          .title ??
                      'Publication')
                  .toString(),
          role: 'poster',
        ),
      ),
    );
    if (encoded == null) {
      return;
    }
    widget.library.access(widget.identity.collectionId);
    final saved = await widget.library.storeArtwork(
      Uint8List.fromList(
        base64Decode(encoded.substring(encoded.indexOf(',') + 1)),
      ),
    );
    if (mounted) {
      setState(() => reference = saved);
    }
  });
  Future<void> apply() => run(() async {
    widget.library.access(widget.identity.collectionId);
    if (reference.isNotEmpty) await widget.library.artworkBytes(reference);
    await widget.library.update(
      widget.identity.collectionId,
      (transaction) => transaction.artwork(widget.identity, reference, mode),
    );
    if (mounted) Navigator.pop(context, true);
  });
  @override
  Widget build(BuildContext context) {
    final members =
        widget.identity.kind == CatalogEntityKind.group && bundle != null
        ? bundle!.catalog.memberships
              .where((m) => m.parent == widget.identity)
              .map((m) => m.child)
              .toList()
        : <CatalogIdentity>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Choose artwork')),
      body: !widget.library.authorized(widget.identity.collectionId)
          ? const Center(child: Text('Collection access is required.'))
          : ListView(
              padding: AppSpacing.of(context).all(20),
              children: [
                Center(
                  child: SizedBox(
                    width: 200,
                    height: 300,
                    child: ReadingCover(
                      library: widget.library,
                      reference: reference,
                      crop: mode == 'crop',
                    ),
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'fit', label: Text('Fit')),
                    ButtonSegment(value: 'crop', label: Text('Crop')),
                  ],
                  selected: {mode},
                  onSelectionChanged: busy
                      ? null
                      : (s) => setState(() => mode = s.single),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error != null) Text(error!),
                OutlinedButton(
                  onPressed: busy ? null : device,
                  child: const Text('From device'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : online,
                  child: const Text('Find artwork online'),
                ),
                for (final member in members)
                  ListTile(
                    title: Text(
                      'From ${bundle!.catalog.titles.singleWhere((t) => t.catalog.id == member).catalog.title}',
                    ),
                    subtitle: readingCoverReference(bundle!, member).isEmpty
                        ? const Text('No artwork')
                        : null,
                    onTap:
                        busy || readingCoverReference(bundle!, member).isEmpty
                        ? null
                        : () => run(() async {
                            final cover = readingCoverReference(
                              bundle!,
                              member,
                            );
                            final selected = await service.select(
                              ArtworkCandidate(
                                location: cover,
                                role: ArtworkRole.poster,
                                source: ArtworkSource.child,
                                ownerId: widget.identity.entityId,
                              ),
                              cancellation,
                            );
                            await widget.library.artworkBytes(selected);
                            if (mounted) setState(() => reference = selected);
                          }),
                  ),
                TextButton(
                  onPressed: busy ? null : () => setState(() => reference = ''),
                  child: const Text('Remove artwork'),
                ),
                FilledButton(
                  onPressed: busy ? null : apply,
                  child: const Text('Apply artwork'),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }
}
