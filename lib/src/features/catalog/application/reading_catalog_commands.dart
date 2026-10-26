import 'dart:async';

import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/classification.dart';
import '../../../reading/domain/reading_catalog.dart';
import '../../../reading/domain/reading_location.dart';
import '../../../settings/domain/media_settings.dart';
import 'reading_catalog_ports.dart';
export 'reading_catalog_ports.dart';

class ReadingCatalogCommands {
  ReadingCatalogCommands(this.store, {required this.authorized});
  final ReadingCatalogStore store;
  final bool Function(String) authorized;
  void access(String id) {
    if (!authorized(id)) throw StateError('Collection access is required.');
  }

  Future<ReadingBundle> read() => store.read();
  Future<ReadingBundle> readCollection(String id) async {
    access(id);
    final result = await store.read();
    access(id);
    return result;
  }

  Future<void> update(
    String collection,
    FutureOr<void> Function(ReadingTransaction) change,
  ) => store.update(collection, change, checkAccess: () => access(collection));
  Future<void> recordOpened(CatalogIdentity id, int milliseconds) => update(
    id.collectionId,
    (transaction) => transaction.recordOpened(id, milliseconds),
  );
  Future<void> addPageNote(
    ReadingTitle title,
    PageReadingLocation location, {
    required String id,
    required bool bookmark,
    String note = '',
    String? label,
  }) => update(
    title.catalog.id.collectionId,
    (transaction) => transaction.addPageNote(
      title,
      location,
      id: id,
      bookmark: bookmark,
      note: note,
      label: label,
    ),
  );
  Future<void> editPageNote(
    String owner,
    String id, {
    required String note,
    required String label,
  }) => update(
    owner,
    (transaction) =>
        transaction.editPageNote(owner, id, note: note, label: label),
  );
  Future<void> removePageNote(String owner, String id) =>
      update(owner, (transaction) => transaction.removePageNote(owner, id));
  Future<void> removeCollection(String collection) => update(
    collection,
    (transaction) => transaction.removeCollection(collection),
  );
  Future<void> metadata(
    CatalogIdentity id,
    Map<String, dynamic> patch, {
    bool manual = true,
    String provider = '',
    String candidateId = '',
    Map<String, dynamic>? expected,
  }) => update(
    id.collectionId,
    (transaction) => transaction.metadata(
      id,
      patch,
      manual: manual,
      provider: provider,
      candidateId: candidateId,
      expected: expected,
    ),
  );
  Future<void> tags(
    String collection,
    List<CatalogIdentity> ids,
    List<String> tags, {
    String operation = 'replace',
    String? target,
  }) => update(
    collection,
    (transaction) => transaction.tags(
      collection,
      ids,
      tags,
      operation: operation,
      target: target,
    ),
  );
  Future<void> browse(String collection, Map<String, dynamic> values) => update(
    collection,
    (transaction) => transaction.browse(collection, values),
  );
  Future<void> settings(
    String collection,
    MediaSubtype subtype,
    SettingsScope scope,
    String? entityId,
    Map<String, Object> values, {
    bool reset = false,
  }) => update(
    collection,
    (transaction) => transaction.settings(
      collection,
      subtype,
      scope,
      entityId,
      values,
      reset: reset,
    ),
  );
  Future<void> finished(
    String collection,
    List<CatalogIdentity> ids,
    bool finished,
  ) => update(
    collection,
    (transaction) => transaction.finished(collection, ids, finished),
  );
  Future<void> saveCollection(
    CatalogCollection collection, {
    Map<String, dynamic>? preferences,
  }) => update(
    collection.id,
    (transaction) =>
        transaction.saveCollection(collection, preferences: preferences),
  );
  Future<void> saveList(
    String owner,
    String id,
    String name,
    List<String> titles,
  ) => update(
    owner,
    (transaction) => transaction.saveList(owner, id, name, titles),
  );
  Future<void> deleteList(String owner, String id) =>
      update(owner, (transaction) => transaction.deleteList(owner, id));
  Future<void> createCollection(
    CatalogCollection row, {
    Map<String, dynamic>? preferences,
  }) => update(
    row.id,
    (transaction) =>
        transaction.createCollection(row, preferences: preferences),
  );
  Future<void> group(
    String collection,
    String groupId,
    String name,
    List<String> titleIds,
  ) => update(
    collection,
    (transaction) => transaction.group(collection, groupId, name, titleIds),
  );
  Future<void> restorePageNote(String collection, ReadingPageNote note) =>
      update(
        collection,
        (transaction) => transaction.restorePageNote(collection, note),
      );
  Future<void> restoreFinished(
    String collection,
    Map<CatalogIdentity, bool> before,
    bool expected,
  ) => update(
    collection,
    (transaction) => transaction.restoreFinished(collection, before, expected),
  );
  Future<void> role(CatalogIdentity id, ReadingRole role) =>
      update(id.collectionId, (transaction) => transaction.role(id, role));
  Future<void> saveSpace(String collection, Map<String, dynamic> display) =>
      update(
        collection,
        (transaction) => transaction.saveSpace(collection, display),
      );
}
