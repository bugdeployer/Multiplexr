import 'dart:convert';

import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/classification.dart';
import '../../settings/domain/media_settings.dart';
import 'reading_catalog.dart';
import 'reading_location.dart';

/// Exact v1 wire schema, mirrored by ReadingCatalogCodec.kt.
abstract final class ReadingCodec {
  static const key = 'reading:library:v1';
  static const maxCharacters = 10000000;
  static ReadingCatalog decode(Map<String, dynamic> input) {
    if (jsonEncode(input).length > maxCharacters) {
      throw FormatException('Reading snapshot exceeds storage limit');
    }
    final row = ReadingWire.object(input, {
      'version',
      'collections',
      'groups',
      'titles',
      'memberships',
      'progress',
      'settings',
    });
    if (row['version'] is! int || row['version'] != 1) {
      throw FormatException('Unsupported reading catalog');
    }
    return ReadingCatalog(
      collections: ReadingWire.list(row['collections'], 10000).map((value) {
        final c = ReadingWire.object(value, {
          'id',
          'name',
          'subtype',
          'locked',
          'includeInGlobal',
          'roots',
        });
        return CatalogCollection(
          id: ReadingWire.text(c['id']),
          name: ReadingWire.text(c['name']),
          subtype: ReadingWire.subtype(c['subtype']),
          access: CatalogAccess(
            locked: ReadingWire.flag(c['locked']),
            includeInGlobal: ReadingWire.flag(c['includeInGlobal']),
          ),
          roots: ReadingWire.list(c['roots'], 100).map((value) {
            final r = ReadingWire.object(value, {'uri', 'name'});
            return CatalogRoot(
              uri: ReadingWire.text(r['uri']),
              name: ReadingWire.text(r['name'], empty: true),
            );
          }),
        );
      }),
      groups: ReadingWire.list(row['groups']).map((value) {
        final g = ReadingWire.object(value, {
          'collectionId',
          'id',
          'subtype',
          'metadata',
        });
        return CatalogGroup(
          id: ReadingWire.identity(g, CatalogEntityKind.group),
          subtype: ReadingWire.subtype(g['subtype']),
          kind: CatalogGroupKind.series,
          metadata: ReadingMetadata.fromJson(g['metadata']),
        );
      }),
      titles: ReadingWire.list(row['titles']).map((value) {
        final t = ReadingWire.object(value, {
          'collectionId',
          'id',
          'subtype',
          'role',
          'format',
          'metadata',
          'source',
          'readingOrder',
        });
        final s = ReadingWire.object(t['source'], {
          'id',
          'uri',
          'name',
          'rootUri',
          'revision',
          'available',
        });
        final metadata = ReadingMetadata.fromJson(t['metadata']);
        return ReadingTitle(
          catalog: CatalogTitle(
            id: ReadingWire.identity(t, CatalogEntityKind.title),
            subtype: ReadingWire.subtype(t['subtype']),
            title: metadata.title,
            metadata: metadata,
            sources: [
              CatalogSource(
                id: ReadingWire.text(s['id']),
                uri: ReadingWire.text(s['uri']),
                name: ReadingWire.text(s['name'], empty: true),
                rootUri: ReadingWire.text(s['rootUri']),
                available: ReadingWire.flag(s['available']),
              ),
            ],
          ),
          role: ReadingRole.values.byName(ReadingWire.text(t['role'])),
          format: ReadingFormat.values.byName(ReadingWire.text(t['format'])),
          sourceRevision: ReadingWire.text(s['revision']),
          readingOrder: ReadingWire.list(t['readingOrder'])
              .map(ReadingResource.fromJson),
        );
      }),
      memberships: ReadingWire.list(row['memberships']).map((value) {
        final m = ReadingWire.object(value, {
          'collectionId',
          'parentId',
          'titleId',
          'order',
        });
        if (m['order'] is! int || (m['order'] as int) > 200000) {
          throw FormatException('Invalid membership order');
        }
        final c = ReadingWire.text(m['collectionId']);
        return GroupMembership(
          parent: CatalogIdentity(
            c,
            ReadingWire.text(m['parentId']),
            CatalogEntityKind.group,
          ),
          child: CatalogIdentity(
            c,
            ReadingWire.text(m['titleId']),
            CatalogEntityKind.title,
          ),
          kind: MembershipKind.structural,
          order: m['order'] as int,
        );
      }),
      progress: ReadingWire.list(row['progress']).map((value) {
        final p = ReadingWire.object(value, {
          'collectionId',
          'id',
          'sourceId',
          'sourceRevision',
          'location',
          'finished',
        });
        final location = ReadingWire.object(p['location'], {
          'version',
          'kind',
          'resourceId',
          'locatorType',
          'locator',
          'progression',
          'before',
          'highlight',
          'after',
          'pageId',
          'pageIndex',
          'offset',
        });
        final allowed = location['kind'] == 'text'
            ? {
                'version',
                'kind',
                'resourceId',
                'locatorType',
                'locator',
                'progression',
                'before',
                'highlight',
                'after',
              }
            : {'version', 'kind', 'pageId', 'pageIndex', 'offset'};
        ReadingWire.object(location, allowed);
        if (location['version'] is! int) {
          throw FormatException('Invalid location version');
        }
        return ReadingProgress(
          id: ReadingWire.identity(p, CatalogEntityKind.title),
          sourceId: ReadingWire.text(p['sourceId']),
          sourceRevision: ReadingWire.text(p['sourceRevision']),
          location: ReadingLocation.fromJson(location),
          finished: ReadingWire.flag(p['finished']),
        );
      }),
      settings: ReadingWire.list(row['settings']).map((value) {
        final s = ReadingWire.object(value, {
          'scope',
          'subtype',
          'collectionId',
          'entityId',
          'values',
        });
        if (s['values'] is! Map<String, dynamic>) {
          throw FormatException('Invalid reader settings');
        }
        return ReadingSettingsLayer(
          scope: SettingsScope.values.byName(ReadingWire.text(s['scope'])),
          subtype: ReadingWire.subtype(s['subtype']),
          collectionId: s.containsKey('collectionId')
              ? ReadingWire.text(s['collectionId'])
              : null,
          entityId: s.containsKey('entityId')
              ? ReadingWire.text(s['entityId'])
              : null,
          values: s['values'] as Map<String, dynamic>,
        );
      }),
    );
  }

  static Map<String, dynamic> encode(ReadingCatalog catalog) => {
    'version': 1,
    'collections': [
      for (final c in catalog.collections)
        {
          'id': c.id,
          'name': c.name,
          'subtype': c.subtype.name,
          'locked': c.access.locked,
          'includeInGlobal': c.access.includeInGlobal,
          'roots': [
            for (final r in c.roots) {'uri': r.uri, 'name': r.name},
          ],
        },
    ],
    'groups': [
      for (final g in catalog.groups)
        {
          ...ReadingWire.id(g.id),
          'subtype': g.subtype.name,
          'metadata': g.metadata.toJson(),
        },
    ],
    'titles': [
      for (final t in catalog.titles)
        {
          ...ReadingWire.id(t.catalog.id),
          'subtype': t.catalog.subtype.name,
          'role': t.role.name,
          'format': t.format.name,
          'metadata': t.catalog.metadata.toJson(),
          'source': {
            'id': t.catalog.sources.single.id,
            'uri': t.catalog.sources.single.uri,
            'name': t.catalog.sources.single.name,
            'rootUri': t.catalog.sources.single.rootUri,
            'revision': t.sourceRevision,
            'available': t.catalog.sources.single.available,
          },
          'readingOrder': [for (final r in t.readingOrder) r.toJson()],
        },
    ],
    'memberships': [
      for (final m in catalog.memberships)
        {
          'collectionId': m.parent.collectionId,
          'parentId': m.parent.entityId,
          'titleId': m.child.entityId,
          'order': m.order,
        },
    ],
    'progress': [for (final p in catalog.progress) p.toJson()],
    'settings': [for (final s in catalog.settings) s.toJson()],
  };
}
