import 'dart:convert';

import '../../catalog/domain/catalog_models.dart';
import 'reading_catalog.dart';
import 'reading_index.dart';

/// Tags, provenance, browse choices and resumable metadata work are independent
/// of progress and source evidence. No credentials or renderer caches belong here.
class ReadingManagement {
  ReadingManagement(Map<String, dynamic> value, ReadingCatalog catalog)
    : json = ReadingIndex.copy(value) {
    final root = ReadingWire.object(json, {
      'version',
      'entities',
      'collections',
      'jobs',
      'pageNotes',
      'lists',
      'spaces',
    });
    if (root['version'] is! int ||
        root['version'] != 1 ||
        jsonEncode(root).length > 10000000) {
      throw const FormatException('Unsupported reading management state');
    }
    final owners = {for (final c in catalog.collections) c.id};
    final titles = {
      for (final t in catalog.titles)
        ReadingIndex.identity(t.catalog.id.collectionId, t.catalog.id.entityId),
    };
    final groups = {
      for (final g in catalog.groups)
        ReadingIndex.identity(g.id.collectionId, g.id.entityId),
    };
    final seen = <String>{};
    for (final raw in ReadingWire.list(root['entities'])) {
      final e = ReadingWire.object(raw, {
        'collectionId',
        'id',
        'kind',
        'tags',
        'manualFields',
        'cover',
        'coverMode',
        'manualCover',
        'provider',
        'candidateId',
        'lastOpened',
      });
      final owner = ReadingWire.text(e['collectionId']),
          id = ReadingWire.text(e['id']);
      final kind = e['kind'];
      if (!{'title', 'group'}.contains(kind) ||
          !(kind == 'title' ? titles : groups).contains(
            ReadingIndex.identity(owner, id),
          ) ||
          !seen.add(jsonEncode([owner, id, kind]))) {
        throw const FormatException('Invalid managed reading owner');
      }
      strings(e['tags'], maximum: 100, length: 80);
      strings(e['manualFields'], maximum: 6);
      if ((e['manualFields'] as List).any(
        (v) => !ReadingIndex.metadataFields.contains(v),
      )) {
        throw const FormatException('Invalid protected field');
      }
      cover(e['cover']);
      if (!{'fit', 'crop'}.contains(e['coverMode'])) {
        throw const FormatException('Invalid cover presentation');
      }
      if (e.containsKey('lastOpened') &&
          (e['lastOpened'] is! int || (e['lastOpened'] as int) < 0)) {
        throw const FormatException('Invalid last opened time');
      }
      ReadingWire.flag(e['manualCover']);
      ReadingWire.text(e['provider'], empty: true);
      ReadingWire.text(e['candidateId'], empty: true);
    }
    final listKeys = <String>{};
    for (final raw in ReadingWire.list(root['lists'] ?? <dynamic>[], 10000)) {
      final row = ReadingWire.object(raw, {
        'collectionId',
        'id',
        'name',
        'titles',
      });
      final owner = ReadingWire.text(row['collectionId']);
      final id = ReadingWire.text(row['id']);
      ReadingWire.text(row['name']);
      strings(row['titles'], maximum: 200000);
      if (!owners.contains(owner) ||
          !listKeys.add(jsonEncode([owner, id])) ||
          (row['titles'] as List).any(
            (id) =>
                !titles.contains(ReadingIndex.identity(owner, id as String)),
          )) {
        throw const FormatException('Invalid reading list');
      }
    }
    final spaceOwners = <String>{};
    for (final raw in ReadingWire.list(root['spaces'] ?? <dynamic>[], 10000)) {
      final row = ReadingWire.object(raw, {'collectionId', 'display'});
      final owner = ReadingWire.text(row['collectionId']);
      if (!owners.contains(owner) || !spaceOwners.add(owner)) {
        throw const FormatException('Invalid reading space owner');
      }
      validateDisplay(row['display']);
    }
    final titleRows = {
      for (final t in catalog.titles)
        ReadingIndex.identity(t.catalog.id.collectionId, t.catalog.id.entityId):
            t,
    };
    final noteIds = <String>{};
    for (final raw in ReadingWire.list(root['pageNotes'], 20000)) {
      final n = ReadingWire.object(raw, {
        'id',
        'collectionId',
        'titleId',
        'sourceId',
        'sourceRevision',
        'pageId',
        'pageIndex',
        'offset',
        'kind',
        'note',
        'label',
      });
      final id = ReadingWire.text(n['id']);
      final title =
          titleRows[ReadingIndex.identity(
            n['collectionId'] as String,
            n['titleId'] as String,
          )];
      if (!noteIds.add(id) ||
          title == null ||
          (title.catalog.subtype.name != 'comics' &&
              title.format != ReadingFormat.pdf)) {
        throw const FormatException('Invalid page note owner');
      }
      for (final key in [
        'collectionId',
        'titleId',
        'sourceId',
        'sourceRevision',
        'pageId',
      ]) {
        ReadingWire.text(n[key]);
      }
      ReadingWire.text(n['note'], empty: true);
      ReadingWire.text(n['label'], empty: true);
      final index = n['pageIndex'], offset = n['offset'];
      if (index is! int ||
          index < 0 ||
          index >= 200000 ||
          offset is! num ||
          !offset.isFinite ||
          offset < 0 ||
          offset > 1 ||
          !{'bookmark', 'note'}.contains(n['kind'])) {
        throw const FormatException('Invalid page note location');
      }
      if (title.sourceRevision == n['sourceRevision'] &&
          title.catalog.sources.single.id == n['sourceId'] &&
          (index >= title.readingOrder.length ||
              title.readingOrder[index].id != n['pageId'])) {
        throw const FormatException('Invalid current page note');
      }
    }
    seen.clear();
    for (final raw in ReadingWire.list(root['collections'], 10000)) {
      final c = ReadingWire.object(raw, {
        'collectionId',
        'layout',
        'sort',
        'openAction',
        'cardSize',
        'formats',
      });
      final owner = ReadingWire.text(c['collectionId']);
      if (!owners.contains(owner) ||
          !seen.add(owner) ||
          !{'grid', 'list', 'compact'}.contains(c['layout']) ||
          !{'title', 'author', 'source'}.contains(c['sort']) ||
          !{'details', 'open'}.contains(c['openAction'])) {
        throw const FormatException('Invalid reading browse preferences');
      }
      if (c.containsKey('cardSize')) {
        final size = c['cardSize'];
        if (size is! num || !size.isFinite || size < 120 || size > 280) {
          throw const FormatException('Invalid reading card size');
        }
      }
      if (c.containsKey('formats')) {
        strings(c['formats'], maximum: 3);
        final subtype = catalog.collections
            .singleWhere((c) => c.id == owner)
            .subtype
            .name;
        final allowed = subtype == 'ebook'
            ? {'epub', 'txt', 'pdf'}
            : {'cbz', 'images'};
        if ((c['formats'] as List).isEmpty ||
            (c['formats'] as List).any((f) => !allowed.contains(f))) {
          throw const FormatException('Invalid reading formats');
        }
      }
    }
    seen.clear();
    for (final raw in ReadingWire.list(root['jobs'], 10000)) {
      final j = ReadingWire.object(raw, {
        'collectionId',
        'provider',
        'implementationEpoch',
        'remaining',
        'done',
        'total',
        'entries',
      });
      final owner = ReadingWire.text(j['collectionId']);
      if (!owners.contains(owner) || !seen.add(owner)) {
        throw const FormatException('Invalid reading job owner');
      }
      ReadingWire.text(j['provider']);
      if (j['implementationEpoch'] != null &&
          !RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(j['implementationEpoch'] as String)) {
        throw const FormatException('Invalid job implementation epoch');
      }
      strings(j['remaining'], maximum: 20);
      final done = j['done'], total = j['total'];
      if (done is! int ||
          total is! int ||
          done < 0 ||
          total < done ||
          total > 20 ||
          (j['remaining'] as List).length != total - done) {
        throw const FormatException('Invalid reading job progress');
      }
      final entries = ReadingWire.list(j['entries'], 20);
      final entryIds = <String>{};
      for (final value in entries) {
        final e = ReadingWire.object(value, {
          'id',
          'status',
          'error',
          'candidates',
        });
        final id = ReadingWire.text(e['id']);
        if (!entryIds.add(id) ||
            !titles.contains(ReadingIndex.identity(owner, id)) ||
            !{'review', 'failed', 'noMatch', 'applied'}.contains(e['status'])) {
          throw const FormatException('Invalid reading metadata job entry');
        }
        ReadingWire.text(e['error'], empty: true);
        for (final candidate in ReadingWire.list(e['candidates'], 20)) {
          final c = ReadingWire.object(candidate, {
            'id',
            'values',
            'provider',
            'entity',
            'attribution',
            'implementation',
          });
          if (c['provider'] != null) {
            ReadingWire.text(c['provider']);
            ReadingWire.text(c['attribution'], empty: true);
            if (!{'ebook', 'comic'}.contains(c['entity'])) {
              throw const FormatException('Invalid metadata entity');
            }
            if (c['implementation'] != null) {
              final identity = ReadingWire.object(c['implementation'], {
                'plugin',
                'publisher',
                'version',
                'contribution',
                'instance',
                'permissionRevision',
                'collection',
              });
              if (identity['collection'] != owner ||
                  identity['contribution'] != c['provider'] ||
                  !(identity['contribution'] as String).startsWith(
                    '${identity['plugin']}:',
                  ) ||
                  !RegExp(r'^[a-f0-9]{64}$')
                      .hasMatch(identity['publisher'] as String) ||
                  !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$')
                      .hasMatch(identity['version'] as String) ||
                  !RegExp(r'^[a-f0-9-]{36}$')
                      .hasMatch(identity['instance'] as String) ||
                  identity['permissionRevision'] is! int ||
                  (identity['permissionRevision'] as int) < 1) {
                throw const FormatException('Invalid provider implementation');
              }
            }
          }
          ReadingWire.text(c['id']);
          candidateValues(c['values']);
        }
      }
      if ((j['remaining'] as List).any(
        (id) => !titles.contains(ReadingIndex.identity(owner, id)),
      )) {
        throw const FormatException('Invalid pending reading title');
      }
    }
  }
  static void validateDisplay(Object? value) {
    final row = ReadingWire.object(value, {
      'source',
      'artwork',
      'counts',
      'confirmExit',
      'hideWatched',
      'startTab',
      'pins',
    });
    for (final key in ['artwork', 'counts', 'confirmExit', 'hideWatched']) {
      ReadingWire.flag(row[key]);
    }
    if (!{
          'recent',
          'favorites',
          'progress',
          'pinned',
        }.contains(row['source']) ||
        row['startTab'] is! int ||
        (row['startTab'] as int) < 0 ||
        (row['startTab'] as int) > 2) {
      throw const FormatException('Invalid reading display');
    }
    strings(row['pins'], maximum: 3, length: 4000);
    for (final key in row['pins'] as List) {
      final pair = jsonDecode(key as String);
      if (pair is! List ||
          pair.length != 2 ||
          pair.any((v) => v is! String || v.isEmpty)) {
        throw const FormatException('Invalid reading pin');
      }
    }
  }

  final Map<String, dynamic> json;
  static const key = 'reading:management:v1';
  static Map<String, dynamic> empty() => {
    'version': 1,
    'entities': <dynamic>[],
    'collections': <dynamic>[],
    'jobs': <dynamic>[],
    'pageNotes': <dynamic>[],
  };
  static void strings(Object? values, {int maximum = 100, int length = 4096}) {
    final list = ReadingWire.list(values, maximum);
    if (list.toSet().length != list.length) {
      throw const FormatException('Duplicate managed value');
    }
    for (final item in list) {
      final s = ReadingWire.text(item);
      if (s.length > length) {
        throw const FormatException('Managed value exceeds limit');
      }
    }
  }

  static void cover(Object? value) {
    if (value is! String ||
        value.length > 2000000 ||
        !(value.isEmpty ||
            RegExp(r'^reading-cover:[a-f0-9]{64}$').hasMatch(value) ||
            value.startsWith('data:image/jpeg;base64,') &&
                RegExp(r'^[A-Za-z0-9+/]*={0,2}$')
                    .hasMatch(value.substring(23)))) {
      throw const FormatException('Invalid managed cover');
    }
  }

  static void candidateValues(Object? value) {
    final fields = ReadingWire.object(value, {
      ...ReadingIndex.metadataFields,
      'coverUrl',
      'edition',
    });
    for (final e in fields.entries) {
      if (e.key == 'authors') {
        strings(e.value);
      } else {
        ReadingWire.text(e.value, empty: true);
      }
    }
    if (fields['comicStyle'] != null &&
        !ComicStyle.values.map((s) => s.name).contains(fields['comicStyle'])) {
      throw const FormatException('Invalid comic style');
    }
    if (fields['coverUrl'] != null) {
      final url = Uri.tryParse(fields['coverUrl'] as String);
      if (url == null ||
          url.scheme != 'https' ||
          url.host != 'covers.openlibrary.org' ||
          !RegExp(r'^/b/id/[1-9][0-9]*-[SML]\.jpg$').hasMatch(url.path) ||
          url.hasFragment ||
          url.userInfo.isNotEmpty ||
          url.port != 443) {
        throw const FormatException('Invalid provider cover');
      }
    }
  }

  late final Map<String, Map<String, dynamic>> _byEntity = {
    for (final row in (json['entities'] as List).cast<Map<String, dynamic>>())
      jsonEncode([row['collectionId'], row['id'], row['kind']]): row,
  };
  Map<String, dynamic> entity(CatalogIdentity id) =>
      _byEntity[jsonEncode([id.collectionId, id.entityId, id.kind.name])] ??
      {
        'collectionId': id.collectionId,
        'id': id.entityId,
        'kind': id.kind.name,
        'tags': <String>[],
        'manualFields': <String>[],
        'cover': '',
        'coverMode': 'fit',
        'manualCover': false,
        'provider': '',
        'candidateId': '',
      };
}
