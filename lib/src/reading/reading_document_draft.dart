import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';

class ReadingDocumentDraft {
  ReadingDocumentDraft(this.catalog, this.index, this.management);
  final Map<String, dynamic> catalog, index, management;
  Map<String, dynamic> row(CatalogIdentity id) =>
      (catalog[id.kind == CatalogEntityKind.group ? 'groups' : 'titles']
              as List)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (r) =>
                r['collectionId'] == id.collectionId && r['id'] == id.entityId,
          );
  Map<String, dynamic> managed(CatalogIdentity id) {
    final rows = management['entities'] as List;
    final existing = rows
        .where(
          (r) =>
              r['collectionId'] == id.collectionId &&
              r['id'] == id.entityId &&
              r['kind'] == id.kind.name,
        )
        .firstOrNull;
    if (existing != null) return existing as Map<String, dynamic>;
    final value = {
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
    rows.add(value);
    return value;
  }

  Map<String, dynamic>? evidence(CatalogIdentity id) =>
      id.kind != CatalogEntityKind.title
      ? null
      : (index['entries'] as List)
            .cast<Map<String, dynamic>>()
            .where(
              (r) =>
                  r['collectionId'] == id.collectionId &&
                  r['id'] == id.entityId,
            )
            .firstOrNull;
}
