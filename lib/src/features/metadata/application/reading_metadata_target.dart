import 'dart:convert';

import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/classification.dart';
import '../../../reading/domain/reading_index.dart';
import '../../../reading/reading_metadata_host.dart';
import 'artwork_service.dart';
import 'metadata_contracts.dart';
import 'publication_provider.dart';

class ReadingMetadataTarget implements MetadataTarget {
  ReadingMetadataTarget(this.library, this.identity, this.provider);
  final ReadingMetadataHost library;
  final CatalogIdentity identity;
  final PublicationProvider provider;
  final artwork = ArtworkService();
  MetadataEntityType? _entity;
  @override
  MetadataEntityType get entity =>
      _entity ??
      (throw StateError('Read the metadata target before searching'));
  Future<ReadingMetadataTarget> initialize() async {
    await read();
    return this;
  }

  @override
  Object get owner => library.owner;
  @override
  String get key => jsonEncode([
    identity.collectionId,
    identity.entityId,
    identity.kind.name,
  ]);
  @override
  bool get authorized => library.authorized(identity.collectionId);
  @override
  Future<MetadataSnapshot> read() async {
    library.commands.access(identity.collectionId);
    final bundle = await library.commands.read();
    library.commands.access(identity.collectionId);
    final group = identity.kind == CatalogEntityKind.group;
    final metadata = group
        ? bundle.catalog.groups.singleWhere((g) => g.id == identity).metadata
        : bundle.catalog.titles
              .singleWhere((t) => t.catalog.id == identity)
              .catalog
              .metadata;
    final subtype = bundle.catalog.collections
        .singleWhere((c) => c.id == identity.collectionId)
        .subtype;
    _entity = subtype == MediaSubtype.ebook
        ? MetadataEntityType.ebook
        : MetadataEntityType.comic;
    final managed = bundle.management.entity(identity),
        evidence = group ? null : bundle.index.entry(identity);
    return MetadataSnapshot(
      {...metadata.toJson(), 'cover': evidence?.cover ?? managed.cover},
      manualFields: {
        ...managed.manualFields as List,
        ...?evidence?.manualFields as List?,
        if (managed.manualCover == true || evidence?.manualCover == true)
          'cover',
      }.cast<String>(),
      provider: managed.provider,
      candidateId: managed.candidateId,
    );
  }

  @override
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    final values = candidate.implementation != null
        ? candidate.values
        : await provider.details(candidate, cancellation);
    return {
      for (final e in values.entries)
        if (ReadingIndex.metadataFields.contains(e.key) &&
            e.value != '' &&
            e.value != null)
          e.key: e.value,
      if (values['coverUrl'] != null) 'cover': values['coverUrl'],
    };
  }

  @override
  Future<void> commit(
    Map<String, dynamic> selected,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    final before = await read();
    final patch = {...selected};
    if (patch['cover'] != null) {
      patch['cover'] = await artwork.select(
        ArtworkCandidate(
          location: patch['cover'] as String,
          role: ArtworkRole.poster,
          source: ArtworkSource.online,
          ownerId: key,
          provider: candidate.provenance,
        ),
        cancellation,
        download: (url) async =>
            library.storeArtwork(await provider.cover(url)),
      );
    }
    cancellation.check();
    library.commands.access(identity.collectionId);
    await library.commands.metadata(
      identity,
      patch,
      manual: false,
      provider: candidate.provenance,
      candidateId: candidate.id,
      expected: before.fields,
    );
  }
}
