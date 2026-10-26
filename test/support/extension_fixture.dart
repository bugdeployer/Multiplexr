import 'dart:convert';
import 'dart:io';

import 'package:multiplexr/src/catalog/domain/catalog_models.dart';
import 'package:multiplexr/src/catalog/domain/classification.dart';
import 'package:multiplexr/src/catalog/domain/group_repository.dart';
import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/reading/domain/reading_catalog.dart';
import 'package:multiplexr/src/reading/domain/reading_codec.dart';

/// R1 uses the real reading codecs while retaining the the current module shared fixtures.
ReadingCatalog readingExtensionFixture() => ReadingCodec.decode(
  (jsonDecode(File('test/fixtures/reading-v1.json').readAsStringSync())
          as Map<String, dynamic>)['base']
      as Map<String, dynamic>,
);

/// Test-only adapter. No fixture registry, provider or engine enters the app.
class ExtensionFixture {
  ExtensionFixture(Map<String, dynamic> json)
    : subtype = MediaSubtype.values.byName(json['subtype']),
      entity = MetadataEntityType.values.byName(json['metadataEntity']),
      raw = json;
  final Map<String, dynamic> raw;
  final MediaSubtype subtype;
  final MetadataEntityType entity;
  String get collectionId => 'fixture:${subtype.name}';
  CatalogIdentity identity(String id, CatalogEntityKind kind) =>
      CatalogIdentity(collectionId, id, kind);
  CatalogCollection collection({bool locked = false, bool global = true}) =>
      CatalogCollection(
        id: collectionId,
        name: '${subtype.label} fixture',
        subtype: subtype,
        access: CatalogAccess(locked: locked, includeInGlobal: global),
        roots: [
          for (final root in raw['roots'])
            CatalogRoot(uri: root['uri'], name: root['name']),
        ],
      );
  List<CatalogTitle<Map<String, dynamic>>> get titles => [
    for (final row in raw['titles'])
      CatalogTitle(
        id: identity(row['id'], CatalogEntityKind.title),
        subtype: subtype,
        title: row['metadata']['title'],
        metadata: Map<String, dynamic>.unmodifiable(row['metadata']),
        sources: [
          for (final source in row['sources'])
            CatalogSource(
              id: source['id'],
              uri: source['uri'],
              name: source['name'],
              available: source['available'],
              rootUri: source['rootUri'],
            ),
        ],
      ),
  ];

  SubtypeRegistry get registry {
    final kinds = [
      for (final row in raw['groups'])
        CatalogGroupKind.values.byName(row['kind']),
    ];
    return SubtypeRegistry([
      SubtypeDefinition(
        id: subtype,
        enabled: false,
        engine: switch (subtype.type) {
          MediaType.audio => MediaEngineKind.audio,
          MediaType.photo => MediaEngineKind.image,
          MediaType.ebook => MediaEngineKind.reader,
          MediaType.video => MediaEngineKind.video,
        },
        capabilities: MediaCapability.values,
        hierarchy: HierarchyDefinition(
          groups: kinds,
          structuralTitleParents: kinds.where(
            (k) => k != CatalogGroupKind.playlist,
          ),
          curatedParents: kinds.where((k) => k == CatalogGroupKind.playlist),
        ),
      ),
    ]);
  }

  GroupSnapshot graph({List<GroupMembership>? memberships}) => GroupSnapshot(
    registry: registry,
    groups: [
      for (final row in raw['groups'])
        CatalogGroup<Object?>(
          id: identity(row['id'], CatalogEntityKind.group),
          subtype: subtype,
          kind: CatalogGroupKind.values.byName(row['kind']),
          metadata: Map<String, dynamic>.from(row['metadata']),
        ),
    ],
    titles: titles.map((t) => t.id),
    memberships:
        memberships ??
        [
          for (final row in raw['memberships'])
            GroupMembership(
              parent: identity(row['parent'], CatalogEntityKind.group),
              child: identity(row['child'], CatalogEntityKind.title),
              kind: MembershipKind.values.byName(row['kind']),
              order: row['order'],
            ),
        ],
  );
}

List<ExtensionFixture> extensionFixtures() {
  final json = jsonDecode(
    File('test/fixtures/extension-proof-v1.json').readAsStringSync(),
  );
  if (json['fixtureVersion'] != 1) {
    throw const FormatException('Unknown fixture');
  }
  return [
    for (final row in json['collections'])
      ExtensionFixture(Map<String, dynamic>.from(row)),
  ];
}

/// Only provider I/O and field persistence are stubbed; review/apply is shared.
class FixtureProvider implements MetadataProvider {
  FixtureProvider(this.entity);
  final MetadataEntityType entity;
  @override
  String get id => 'extension-fixture';
  @override
  Set<MetadataEntityType> get entities => {entity};
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async =>
      MetadataSearchPage(
        request: request,
        nextPage: request.page == 1 ? 2 : null,
        attribution: 'Synthetic fixture',
        candidates: [
          MetadataCandidate(
            provider: id,
            id: 'result:${request.page}',
            entity: entity,
            values: {
              'title': request.title,
              'creator': 'Provider creator',
              'description': 'Provider description',
            },
            attribution: 'Synthetic fixture',
          ),
        ],
      );
}

class FixtureTarget implements MetadataTarget {
  FixtureTarget(this.store, this.entity, this.key);
  final StateStore store;
  @override
  final MetadataEntityType entity;
  @override
  final String key;
  @override
  bool authorized = true;
  @override
  Object get owner => store.persistenceOwner;
  @override
  Future<MetadataSnapshot> read() async {
    final state = await store.readState(key) ?? {};
    return MetadataSnapshot(
      Map<String, dynamic>.from(state['fields'] ?? {}),
      manualFields: {'creator'},
      provider: state['provider'] ?? '',
      candidateId: state['candidateId'] ?? '',
    );
  }

  @override
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async => candidate.values;
  @override
  Future<void> commit(
    Map<String, dynamic> selected,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) => JsonStateRepository(store).update(
    key,
    (current) async => {
      'fields': {...?current?['fields'] as Map?, ...selected},
      'provider': candidate.provider,
      'candidateId': candidate.id,
    },
  );
}
