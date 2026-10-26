import '../../metadata/application/metadata_batch_journal.dart';
import '../../../catalog/domain/catalog_models.dart';

/// Detached read projections. Storage versions, raw documents and codecs never
/// cross the catalog port. Collections and nested values are immutable.
class ReadingEvidence {
  ReadingEvidence({
    required this.id,
    required this.rootUri,
    required this.cover,
    required this.encoding,
    required this.manualCover,
    required Iterable<String> manualFields,
  }) : manualFields = List.unmodifiable(manualFields);
  final CatalogIdentity id;
  final String rootUri, cover, encoding;
  final bool manualCover;
  final List<String> manualFields;
}

class ReadingRootHealth {
  const ReadingRootHealth(this.collectionId, this.uri, this.complete);
  final String collectionId, uri;
  final bool complete;
}

class ReadingIndexView {
  ReadingIndexView(
    Iterable<ReadingEvidence> entries,
    Iterable<ReadingRootHealth> roots,
  ) : entries = List.unmodifiable(entries),
      roots = List.unmodifiable(roots);
  final List<ReadingEvidence> entries;
  final List<ReadingRootHealth> roots;
  ReadingEvidence? entry(CatalogIdentity id) =>
      entries.where((e) => e.id == id).firstOrNull;
}

class ReadingEntityView {
  ReadingEntityView({
    required this.id,
    Iterable<String> tags = const [],
    Iterable<String> manualFields = const [],
    this.cover = '',
    this.coverMode = 'fit',
    this.manualCover = false,
    this.provider = '',
    this.candidateId = '',
    this.lastOpened = 0,
  }) : tags = List.unmodifiable(tags),
       manualFields = List.unmodifiable(manualFields);
  final CatalogIdentity id;
  String get collectionId => id.collectionId;
  final List<String> tags, manualFields;
  final String cover, coverMode, provider, candidateId;
  final bool manualCover;
  final int lastOpened;
}

class ReadingBrowseView {
  ReadingBrowseView({
    required this.collectionId,
    required this.layout,
    required this.sort,
    required this.openAction,
    this.cardSize,
    Iterable<String>? formats,
  }) : formats = formats == null ? null : List.unmodifiable(formats);
  final String collectionId, layout, sort, openAction;
  final double? cardSize;
  final List<String>? formats;
}

class ReadingListView {
  ReadingListView(
    this.collectionId,
    this.id,
    this.name,
    Iterable<String> titles,
  ) : titles = List.unmodifiable(titles);
  final String collectionId, id, name;
  final List<String> titles;
}

class ReadingPageNote {
  const ReadingPageNote({
    required this.id,
    required this.collectionId,
    required this.titleId,
    required this.sourceId,
    required this.sourceRevision,
    required this.pageId,
    required this.pageIndex,
    required this.offset,
    required this.kind,
    required this.note,
    required this.label,
  });
  final String id,
      collectionId,
      titleId,
      sourceId,
      sourceRevision,
      pageId,
      kind,
      note,
      label;
  final int pageIndex;
  final double offset;
}

class ReadingSpaceView {
  ReadingSpaceView(
    this.collectionId, {
    required this.source,
    required this.artwork,
    required this.counts,
    required this.confirmExit,
    required this.hideWatched,
    required this.startTab,
    required Iterable<String> pins,
  }) : pins = List.unmodifiable(pins);
  final String collectionId, source;
  final bool artwork, counts, confirmExit, hideWatched;
  final int startTab;
  final List<String> pins;
}

class ReadingJobEntryView {
  const ReadingJobEntryView(this.id, this.status);
  final String id, status;
}

class ReadingJobView {
  ReadingJobView(
    this.collectionId,
    this.provider,
    this.done,
    this.total,
    Iterable<String> remaining,
    Iterable<ReadingJobEntryView> entries,
    this.journal,
  ) : remaining = List.unmodifiable(remaining),
      entries = List.unmodifiable(entries);
  final String collectionId, provider;
  final int done, total;
  final MetadataBatchJournal journal;
  final List<String> remaining;
  final List<ReadingJobEntryView> entries;
}

class ReadingManagementView {
  ReadingManagementView({
    required Iterable<ReadingEntityView> entities,
    required Iterable<ReadingBrowseView> collections,
    required Iterable<ReadingListView> lists,
    required Iterable<ReadingPageNote> pageNotes,
    required Iterable<ReadingSpaceView> spaces,
    required Iterable<ReadingJobView> jobs,
  }) : entities = List.unmodifiable(entities),
       collections = List.unmodifiable(collections),
       lists = List.unmodifiable(lists),
       pageNotes = List.unmodifiable(pageNotes),
       spaces = List.unmodifiable(spaces),
       jobs = List.unmodifiable(jobs);
  final List<ReadingEntityView> entities;
  final List<ReadingBrowseView> collections;
  final List<ReadingListView> lists;
  final List<ReadingPageNote> pageNotes;
  final List<ReadingSpaceView> spaces;
  final List<ReadingJobView> jobs;
  ReadingEntityView entity(CatalogIdentity id) =>
      entities.where((e) => e.id == id).firstOrNull ??
      ReadingEntityView(id: id);
}
