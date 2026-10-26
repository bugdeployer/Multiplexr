import '../experience/collection/job_status_page.dart';
import 'reading_app_controller.dart';

Future<List<CollectionActivityEntry>> readReadingActivity(
  ReadingAppController app,
  Future<void> Function(String collectionId) open,
) async {
  final bundle = app.bundle;
  if (bundle == null) return [];
  final result = <CollectionActivityEntry>[];
  for (final id in app.library.autoScans.running) {
    if (!app.canAccess(id)) continue;
    final collection = bundle.catalog.collections
        .where((c) => c.id == id)
        .firstOrNull;
    if (collection == null) continue;
    result.add(
      CollectionActivityEntry(
        id: 'reading-scan:$id',
        title: collection.name,
        summary: 'Scanning',
        authorized: () => app.canAccess(id),
        open: () => open(id),
      ),
    );
  }
  for (final row in bundle.management.jobs) {
    final id = row.collectionId;
    if (!app.canAccess(id)) continue;
    final collection = bundle.catalog.collections
        .where((c) => c.id == id)
        .firstOrNull;
    if (collection == null) continue;
    final titles = bundle.catalog.titles
        .where((t) => t.catalog.id.collectionId == id)
        .map((t) => t.catalog.id.entityId)
        .toSet();
    final remaining = (row.remaining as List).where(titles.contains).length;
    final entries = (row.entries as List).where((e) => titles.contains(e.id));
    final review = entries.where((e) => e.status == 'review').length;
    final failed = entries.where((e) => e.status == 'failed').length;
    if (remaining == 0 && review == 0 && failed == 0) continue;
    result.add(
      CollectionActivityEntry(
        id: 'reading:$id',
        title: collection.name,
        summary:
            'Metadata · $remaining remaining · $review to review · $failed failed',
        authorized: () => app.canAccess(id),
        open: () => open(id),
      ),
    );
  }
  return result;
}
