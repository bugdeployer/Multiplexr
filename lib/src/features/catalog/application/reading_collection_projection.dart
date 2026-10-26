import '../../../catalog/domain/classification.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../reading/domain/reading_catalog.dart';
import '../../../reading/domain/reading_location.dart';
import 'reading_catalog_ports.dart';
import 'collection_presenter.dart';

class ReadingItem {
  const ReadingItem(this.id, this.metadata, this.title);
  final CatalogIdentity id;
  final ReadingMetadata metadata;
  final ReadingTitle? title;
  bool get group => id.kind == CatalogEntityKind.group;
}

class ReadingCollectionProjection {
  ReadingCollectionProjection(
    this.bundle,
    this.controller, {
    this.groupId,
    this.query = '',
    this.author = '',
    this.language = '',
  });
  final ReadingBundle bundle;
  final CollectionController<ReadingItem, CatalogIdentity> controller;
  final CatalogIdentity? groupId;
  final String query, author, language;
  String status(ReadingItem item) {
    final ids = item.group
        ? bundle.catalog.memberships
              .where((m) => m.parent == item.id)
              .map((m) => m.child)
              .toList()
        : [item.id];
    final progress = bundle.catalog.progress
        .where((p) => ids.contains(p.id))
        .toList();
    if (ids.isNotEmpty &&
        progress.where((p) => p.finished).length == ids.length) {
      return 'completed';
    }
    return progress.any(
          (p) =>
              !p.finished &&
              (p.location is TextReadingLocation
                  ? (p.location as TextReadingLocation).locator != '0'
                  : (p.location as PageReadingLocation).pageIndex > 0 ||
                        (p.location as PageReadingLocation).offset > 0),
        )
        ? 'inProgress'
        : 'unread';
  }

  List<ReadingItem> get visible => controller.browse(
    matches: (item) {
      final flat =
          query.isNotEmpty ||
          controller.filter != 'all' ||
          controller.tag.isNotEmpty ||
          controller.folder.isNotEmpty ||
          author.isNotEmpty ||
          language.isNotEmpty;
      if (groupId == null &&
          !flat &&
          item.title != null &&
          bundle.catalog.memberships.any((m) => m.child == item.id)) {
        return false;
      }
      final tags = bundle.management.entity(item.id).tags as List;
      return '${item.metadata.title} ${item.metadata.authors.join(' ')}'
              .toLowerCase()
              .contains(query.toLowerCase()) &&
          (controller.filter == 'all' ||
              controller.filter == 'missing' &&
                  item.title?.catalog.sources.single.available == false ||
              status(item) == controller.filter) &&
          (controller.tag.isEmpty || tags.contains(controller.tag)) &&
          (author.isEmpty || item.metadata.authors.contains(author)) &&
          (language.isEmpty || item.metadata.language == language) &&
          (controller.folder.isEmpty ||
              item.title != null &&
                  bundle.index.entry(item.id)?.rootUri == controller.folder);
    },
    compare: (a, b) {
      if (groupId != null && controller.sort == 'source') {
        final members = bundle.catalog.memberships
            .where((m) => m.parent == groupId)
            .toList();
        return members
            .singleWhere((m) => m.child == a.id)
            .order
            .compareTo(members.singleWhere((m) => m.child == b.id).order);
      }
      final x = controller.sort == 'author'
          ? a.metadata.authors.join(' ')
          : controller.sort == 'source'
          ? a.title?.catalog.sources.single.name ?? a.metadata.title
          : a.metadata.title;
      final y = controller.sort == 'author'
          ? b.metadata.authors.join(' ')
          : controller.sort == 'source'
          ? b.title?.catalog.sources.single.name ?? b.metadata.title
          : b.metadata.title;
      return x.toLowerCase().compareTo(y.toLowerCase());
    },
  );
}
