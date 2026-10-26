import 'dart:convert';

import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/classification.dart';
import 'reading_catalog.dart';

enum ReadingAnnotationKind { bookmark, highlight, note }

class ReadingAnnotation {
  ReadingAnnotation({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.sourceRevision,
    required this.resourceId,
    required this.start,
    required this.end,
    required this.quote,
    required this.before,
    required this.after,
    required this.kind,
    this.note = '',
    this.label = '',
    this.color = 'yellow',
  }) {
    for (final value in [id, sourceId, sourceRevision, resourceId]) {
      ReadingWire.text(value);
    }
    for (final value in [quote, before, after, note, label]) {
      ReadingWire.text(value, empty: true);
    }
    if (title.kind != CatalogEntityKind.title ||
        start < 0 ||
        end < start ||
        end > 8 * 1024 * 1024 ||
        (kind == ReadingAnnotationKind.bookmark
            ? start != end || quote.isNotEmpty
            : start == end || end - start != quote.length) ||
        !{'yellow', 'green', 'blue', 'rose'}.contains(color)) {
      throw FormatException('Invalid reading annotation range');
    }
  }
  final String id,
      sourceId,
      sourceRevision,
      resourceId,
      quote,
      before,
      after,
      note,
      label,
      color;
  final CatalogIdentity title;
  final int start, end;
  final ReadingAnnotationKind kind;
  bool matches(ReadingTitle value) =>
      title == value.catalog.id &&
      sourceId == value.catalog.sources.single.id &&
      sourceRevision == value.sourceRevision;
  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': title.collectionId,
    'titleId': title.entityId,
    'sourceId': sourceId,
    'sourceRevision': sourceRevision,
    'resourceId': resourceId,
    'start': start,
    'end': end,
    'quote': quote,
    'before': before,
    'after': after,
    'kind': kind.name,
    'note': note,
    'label': label,
    'color': color,
  };
  factory ReadingAnnotation.fromJson(Object? raw) {
    final r = ReadingWire.object(raw, {
      'id',
      'collectionId',
      'titleId',
      'sourceId',
      'sourceRevision',
      'resourceId',
      'start',
      'end',
      'quote',
      'before',
      'after',
      'kind',
      'note',
      'label',
      'color',
    });
    if (r['start'] is! int || r['end'] is! int) {
      throw FormatException('Invalid annotation offset');
    }
    return ReadingAnnotation(
      id: ReadingWire.text(r['id']),
      title: CatalogIdentity(
        ReadingWire.text(r['collectionId']),
        ReadingWire.text(r['titleId']),
        CatalogEntityKind.title,
      ),
      sourceId: ReadingWire.text(r['sourceId']),
      sourceRevision: ReadingWire.text(r['sourceRevision']),
      resourceId: ReadingWire.text(r['resourceId']),
      start: r['start'] as int,
      end: r['end'] as int,
      quote: ReadingWire.text(r['quote'], empty: true),
      before: ReadingWire.text(r['before'], empty: true),
      after: ReadingWire.text(r['after'], empty: true),
      kind: ReadingAnnotationKind.values.byName(ReadingWire.text(r['kind'])),
      note: ReadingWire.text(r['note'], empty: true),
      label: ReadingWire.text(r['label'], empty: true),
      color: ReadingWire.text(r['color']),
    );
  }
}

abstract final class ReadingAnnotationCodec {
  static const key = 'reading:annotations:v1';
  static List<ReadingAnnotation> decode(
    Map<String, dynamic> raw,
    ReadingCatalog catalog,
  ) {
    final row = ReadingWire.object(raw, {'version', 'items'});
    if (row['version'] is! int ||
        row['version'] != 1 ||
        jsonEncode(raw).length > 10000000) {
      throw FormatException('Unsupported annotations');
    }
    final items = ReadingWire.list(
      row['items'],
      20000,
    ).map(ReadingAnnotation.fromJson).toList();
    final titles = {for (final t in catalog.titles) t.catalog.id: t};
    final ids = <String>{};
    for (final annotation in items) {
      final title = titles[annotation.title];
      if (!ids.add(annotation.id) ||
          title == null ||
          title.catalog.subtype != MediaSubtype.ebook ||
          annotation.matches(title) &&
              !title.readingOrder.any((r) => r.id == annotation.resourceId)) {
        throw FormatException('Invalid annotation owner');
      }
    }
    return List.unmodifiable(items);
  }

  static Map<String, dynamic> encode(Iterable<ReadingAnnotation> items) => {
    'version': 1,
    'items': [for (final item in items) item.toJson()],
  };
}
