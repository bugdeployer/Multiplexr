import 'reading_format.dart';
export 'reading_format.dart';

import 'dart:convert';

import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/classification.dart';
import '../../catalog/domain/group_repository.dart';
import '../../settings/domain/media_settings.dart';
import 'reader_settings.dart';
import 'reading_location.dart';

enum ReadingRole { publication, volume, issue, chapter }

enum ComicStyle { comic, manga, manhua, manhwa }

/// Strict, bounded primitives shared by the reading codecs.
abstract final class ReadingWire {
  static Map<String, dynamic> object(Object? value, Set<String> fields) {
    if (value is! Map<String, dynamic> ||
        value.keys.any((k) => !fields.contains(k))) {
      throw FormatException('Invalid reading object');
    }
    return value;
  }

  static List<dynamic> list(Object? value, [int max = 200000]) {
    if (value is! List || value.length > max) {
      throw FormatException('Invalid reading list');
    }
    return value;
  }

  static String text(Object? value, {bool empty = false}) {
    if (value is! String) throw FormatException('Expected reading text');
    readingText(value, empty: empty);
    return value;
  }

  static bool flag(Object? value) {
    if (value is! bool) throw FormatException('Expected reading flag');
    return value;
  }

  static MediaSubtype subtype(Object? value) => switch (value) {
    'ebook' => MediaSubtype.ebook,
    'comics' => MediaSubtype.comics,
    _ => throw FormatException('Invalid reading subtype'),
  };
  static CatalogIdentity identity(
    Map<String, dynamic> row,
    CatalogEntityKind kind,
  ) => CatalogIdentity(text(row['collectionId']), text(row['id']), kind);
  static Map<String, dynamic> id(CatalogIdentity id) => {
    'collectionId': id.collectionId,
    'id': id.entityId,
  };

  static Uri uri(String value) {
    readingText(value);
    if (RegExp(r'[\x00-\x20<>"{}|\\^`\[\]]').hasMatch(value) ||
        RegExp(r'%(?![a-fA-F0-9]{2})').hasMatch(value)) {
      throw FormatException('Invalid reading URI');
    }
    return Uri.parse(value);
  }
}

class ReadingMetadata {
  ReadingMetadata({
    required this.title,
    Iterable<String> authors = const [],
    this.description = '',
    this.language = '',
    this.identifier = '',
    this.comicStyle,
  }) : authors = List.unmodifiable(authors) {
    readingText(title);
    if (this.authors.length > 100) throw FormatException('Too many authors');
    for (final author in this.authors) {
      readingText(author);
    }
    for (final text in [description, language, identifier]) {
      readingText(text, empty: true);
    }
  }
  final String title, description, language, identifier;
  final List<String> authors;
  final ComicStyle? comicStyle;
  factory ReadingMetadata.fromJson(Object? value) {
    final row = ReadingWire.object(value, {
      'title',
      'authors',
      'description',
      'language',
      'identifier',
      'comicStyle',
    });
    return ReadingMetadata(
      title: ReadingWire.text(row['title']),
      authors: ReadingWire.list(
        row['authors'],
        100,
      ).map((v) => ReadingWire.text(v)),
      description: ReadingWire.text(row['description'], empty: true),
      language: ReadingWire.text(row['language'], empty: true),
      identifier: ReadingWire.text(row['identifier'], empty: true),
      comicStyle: row.containsKey('comicStyle')
          ? ComicStyle.values.byName(ReadingWire.text(row['comicStyle']))
          : null,
    );
  }
  Map<String, dynamic> toJson() => {
    'title': title,
    'authors': authors,
    'description': description,
    'language': language,
    'identifier': identifier,
    if (comicStyle != null) 'comicStyle': comicStyle!.name,
  };
}

class ReadingResource {
  ReadingResource({required this.id, required this.href, required this.label}) {
    readingText(id);
    readingText(href);
    readingText(label, empty: true);
    final uri = ReadingWire.uri(href);
    // Inspect the original spelling: Uri may normalize dot segments on parse.
    final decoded = Uri.decodeComponent(href);
    if (uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        decoded.startsWith('/') ||
        decoded.contains('\\') ||
        decoded.contains('\u0000') ||
        decoded.split('/').any((s) => s == '..')) {
      throw FormatException(
        'Publication resource must be a safe relative reference',
      );
    }
  }
  final String id, href, label;
  factory ReadingResource.fromJson(Object? value) {
    final row = ReadingWire.object(value, {'id', 'href', 'label'});
    return ReadingResource(
      id: ReadingWire.text(row['id']),
      href: ReadingWire.text(row['href']),
      label: ReadingWire.text(row['label'], empty: true),
    );
  }
  Map<String, dynamic> toJson() => {'id': id, 'href': href, 'label': label};
}

class ReadingTitle {
  ReadingTitle({
    required this.catalog,
    required this.role,
    required this.format,
    required this.sourceRevision,
    required Iterable<ReadingResource> readingOrder,
  }) : readingOrder = List.unmodifiable(readingOrder) {
    ReadingWire.subtype(catalog.subtype.name);
    readingText(sourceRevision);
    if (catalog.sources.length != 1 ||
        catalog.segments.isNotEmpty ||
        (catalog.subtype == MediaSubtype.ebook) !=
            {
              ReadingFormat.epub,
              ReadingFormat.txt,
              ReadingFormat.pdf,
            }.contains(format) ||
        (catalog.subtype == MediaSubtype.ebook &&
            (role == ReadingRole.issue ||
                catalog.metadata.comicStyle != null)) ||
        this.readingOrder.isEmpty ||
        this.readingOrder.length > 200000 ||
        this.readingOrder.map((r) => r.id).toSet().length !=
            this.readingOrder.length ||
        this.readingOrder.map((r) => r.href).toSet().length !=
            this.readingOrder.length) {
      throw FormatException('Invalid reading title');
    }
  }
  final CatalogTitle<ReadingMetadata> catalog;
  final ReadingRole role;
  final ReadingFormat format;
  final String sourceRevision;
  final List<ReadingResource> readingOrder;
}

class ReadingProgress {
  ReadingProgress({
    required this.id,
    required this.sourceId,
    required this.sourceRevision,
    required this.location,
    required this.finished,
  }) {
    if (id.kind != CatalogEntityKind.title) {
      throw FormatException('Progress belongs to a title');
    }
    readingText(sourceId);
    readingText(sourceRevision);
  }
  final CatalogIdentity id;
  final String sourceId, sourceRevision;
  final ReadingLocation location;
  final bool finished;

  /// Stale positions remain portable; opening requires explicit recovery.
  bool matches(ReadingTitle title) =>
      id == title.catalog.id &&
      sourceId == title.catalog.sources.single.id &&
      sourceRevision == title.sourceRevision;
  Map<String, dynamic> toJson() => {
    ...ReadingWire.id(id),
    'sourceId': sourceId,
    'sourceRevision': sourceRevision,
    'location': location.toJson(),
    'finished': finished,
  };
}

class ReadingSettingsLayer {
  ReadingSettingsLayer({
    required this.scope,
    required this.subtype,
    this.collectionId,
    this.entityId,
    Map<String, dynamic> values = const {},
  }) : values = ReaderSettings.validate(subtype, values) {
    if (scope == SettingsScope.app
        ? collectionId != null || entityId != null
        : collectionId == null ||
              (scope == SettingsScope.collection
                  ? entityId != null
                  : entityId == null)) {
      throw FormatException('Invalid reader settings owner');
    }
    if (collectionId != null) readingText(collectionId!);
    if (entityId != null) readingText(entityId!);
  }
  final SettingsScope scope;
  final MediaSubtype subtype;
  final String? collectionId, entityId;
  final Map<String, Object> values;
  String get key =>
      jsonEncode([subtype.name, scope.name, collectionId, entityId]);
  SettingsLayer get layer => SettingsLayer(scope, key, {
    for (final e in values.entries)
      e.key: SettingOverride<Object>.value(e.value),
  });
  Map<String, dynamic> toJson() => {
    'scope': scope.name,
    'subtype': subtype.name,
    if (collectionId != null) 'collectionId': collectionId,
    if (entityId != null) 'entityId': entityId,
    'values': values,
  };
}

/// One atomic reading snapshot. No legacy MediaKind, ID or collection codec.
class ReadingCatalog {
  ReadingCatalog({
    Iterable<CatalogCollection> collections = const [],
    Iterable<CatalogGroup<ReadingMetadata>> groups = const [],
    Iterable<ReadingTitle> titles = const [],
    Iterable<GroupMembership> memberships = const [],
    Iterable<ReadingProgress> progress = const [],
    Iterable<ReadingSettingsLayer> settings = const [],
  }) : collections = List.unmodifiable(collections),
       groups = List.unmodifiable(groups),
       titles = List.unmodifiable(titles),
       memberships = List.unmodifiable(memberships),
       progress = List.unmodifiable(progress),
       settings = List.unmodifiable(settings) {
    final owners = {for (final c in this.collections) c.id: c};
    final titleMap = {for (final t in this.titles) t.catalog.id: t};
    final groupMap = {for (final g in this.groups) g.id: g};
    if (this.collections.length > 10000 ||
        this.groups.length > 200000 ||
        this.titles.length > 200000 ||
        this.progress.length > 200000 ||
        this.settings.length > 200000 ||
        this.memberships.length > 200000 ||
        owners.length != this.collections.length ||
        titleMap.length != this.titles.length ||
        groupMap.length != this.groups.length ||
        this.progress.map((p) => p.id).toSet().length != this.progress.length ||
        this.settings.map((s) => s.key).toSet().length !=
            this.settings.length) {
      throw FormatException('Duplicate identity or excessive reading catalog');
    }
    for (final c in this.collections) {
      ReadingWire.subtype(c.subtype.name);
      readingText(c.name);
      if (c.roots.length > 100 ||
          c.roots.map((r) => r.uri).toSet().length != c.roots.length) {
        throw FormatException('Invalid reading roots');
      }
      for (final r in c.roots) {
        readingText(r.name, empty: true);
        _sourceUri(r.uri);
        if (r.contentHint != null) {
          throw FormatException('Reading roots cannot use video hints');
        }
      }
    }
    for (final g in this.groups) {
      if (owners[g.id.collectionId]?.subtype != g.subtype ||
          g.kind != CatalogGroupKind.series) {
        throw FormatException('Invalid reading group owner');
      }
    }
    final sourceIds = <String>{};
    for (final t in this.titles) {
      final c = owners[t.catalog.id.collectionId];
      final s = t.catalog.sources.single;
      if (c?.subtype != t.catalog.subtype ||
          !c!.roots.any((r) => r.uri == s.rootUri) ||
          !sourceIds.add(jsonEncode([c.id, s.id]))) {
        throw FormatException('Invalid reading source owner');
      }
      _sourceUri(s.uri);
      readingText(s.name, empty: true);
    }
    GroupSnapshot(
      groups: this.groups,
      titles: titleMap.keys,
      memberships: this.memberships,
      titleSubtypes: {
        for (final t in this.titles) t.catalog.id: t.catalog.subtype,
      },
    );
    if (this.memberships.any(
      (m) =>
          m.kind != MembershipKind.structural ||
          m.child.kind != CatalogEntityKind.title ||
          m.order > 200000,
    )) {
      throw FormatException('Invalid reading structural membership');
    }
    for (final p in this.progress) {
      final t = titleMap[p.id];
      if (t == null ||
          (p.location is TextReadingLocation) !=
              ({ReadingFormat.epub, ReadingFormat.txt}.contains(t.format))) {
        throw FormatException('Invalid reading progress owner');
      }
      if (p.matches(t)) {
        final location = p.location;
        if (location is TextReadingLocation &&
                !t.readingOrder.any((r) => r.id == location.resourceId) ||
            location is PageReadingLocation &&
                (location.pageIndex >= t.readingOrder.length ||
                    t.readingOrder[location.pageIndex].id != location.pageId)) {
          throw FormatException('Dangling reading position');
        }
      }
    }
    for (final s in this.settings) {
      if (s.scope == SettingsScope.app) continue;
      if (owners[s.collectionId]?.subtype != s.subtype ||
          s.scope == SettingsScope.group &&
              !groupMap.containsKey(
                CatalogIdentity(
                  s.collectionId!,
                  s.entityId!,
                  CatalogEntityKind.group,
                ),
              ) ||
          s.scope == SettingsScope.title &&
              !titleMap.containsKey(
                CatalogIdentity(
                  s.collectionId!,
                  s.entityId!,
                  CatalogEntityKind.title,
                ),
              )) {
        throw FormatException('Dangling reader settings');
      }
    }
  }
  final List<CatalogCollection> collections;
  final List<CatalogGroup<ReadingMetadata>> groups;
  final List<ReadingTitle> titles;
  final List<GroupMembership> memberships;
  final List<ReadingProgress> progress;
  final List<ReadingSettingsLayer> settings;

  static void _sourceUri(String value) {
    readingText(value);
    final uri = ReadingWire.uri(value);
    if (uri.scheme != 'content' ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(uri.authority)) {
      throw FormatException('Expected a local content source');
    }
  }

  ReadingCatalog withoutCollection(String id) => ReadingCatalog(
    collections: collections.where((c) => c.id != id),
    groups: groups.where((g) => g.id.collectionId != id),
    titles: titles.where((t) => t.catalog.id.collectionId != id),
    memberships: memberships.where((m) => m.parent.collectionId != id),
    progress: progress.where((p) => p.id.collectionId != id),
    settings: settings.where((s) => s.collectionId != id),
  );
}
