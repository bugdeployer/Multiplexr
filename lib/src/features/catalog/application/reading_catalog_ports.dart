import '../../../reading/domain/reading_location.dart';

import 'dart:async';

import '../../metadata/application/metadata_batch_journal.dart';

import '../../../catalog/domain/catalog_models.dart';
import '../../../catalog/domain/classification.dart';
import '../../../reading/domain/reading_catalog.dart';
import 'reading_views.dart';
export 'reading_views.dart';
import '../../../settings/domain/media_settings.dart';

class ReadingBundle {
  ReadingBundle(this.catalog, this.index, this.management);
  final ReadingCatalog catalog;
  final ReadingIndexView index;
  final ReadingManagementView management;
}

/// Collection-scoped semantic commands. Persistence documents and codecs are
/// exclusively adapter implementation details; callers cannot edit snapshots.
abstract interface class ReadingTransaction {
  Future<void> artwork(CatalogIdentity id, String reference, String mode);
  Future<void> journal(
    String collection,
    String provider,
    MetadataBatchJournal Function(MetadataBatchJournal?) change,
  );
  Future<void> recordOpened(CatalogIdentity id, int milliseconds);
  Future<void> addPageNote(
    ReadingTitle title,
    PageReadingLocation location, {
    required String id,
    required bool bookmark,
    String note = '',
    String? label,
  });
  Future<void> editPageNote(
    String owner,
    String id, {
    required String note,
    required String label,
  });
  Future<void> removePageNote(String owner, String id);
  Future<void> removeCollection(String collection);
  Future<void> metadata(
    CatalogIdentity id,
    Map<String, dynamic> patch, {
    bool manual = true,
    String provider = '',
    String candidateId = '',
    Map<String, dynamic>? expected,
  });
  Future<void> tags(
    String collection,
    List<CatalogIdentity> ids,
    List<String> tags, {
    String operation = 'replace',
    String? target,
  });
  Future<void> browse(String collection, Map<String, dynamic> values);
  Future<void> settings(
    String collection,
    MediaSubtype subtype,
    SettingsScope scope,
    String? entityId,
    Map<String, Object> values, {
    bool reset = false,
  });
  Future<void> finished(
    String collection,
    List<CatalogIdentity> ids,
    bool finished,
  );
  Future<void> saveCollection(
    CatalogCollection collection, {
    Map<String, dynamic>? preferences,
  });
  Future<void> saveList(
    String owner,
    String id,
    String name,
    List<String> titles,
  );
  Future<void> deleteList(String owner, String id);
  Future<void> createCollection(
    CatalogCollection row, {
    Map<String, dynamic>? preferences,
  });
  Future<void> group(
    String collection,
    String groupId,
    String name,
    List<String> titleIds,
  );
  Future<void> restorePageNote(String collection, ReadingPageNote note);
  Future<void> restoreFinished(
    String collection,
    Map<CatalogIdentity, bool> before,
    bool expected,
  );
  Future<void> role(CatalogIdentity id, ReadingRole role);
  Future<void> saveSpace(String collection, Map<String, dynamic> display);
}

abstract interface class ReadingCatalogStore {
  Future<ReadingBundle> read();
  Future<void> update(
    String collection,
    FutureOr<void> Function(ReadingTransaction) change, {
    required void Function() checkAccess,
  });
}
