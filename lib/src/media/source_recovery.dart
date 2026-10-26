import 'package:flutter/material.dart';

import '../library/collection_form.dart';
import '../library/folder_health.dart';
import '../library/library_controller.dart';

/// Reuses folder health and the existing collection editor; never grants access.
Future<void> recoverCollectionSource(
  BuildContext context,
  String collectionId, {
  required bool Function() authorized,
  LibraryController? controller,
}) async {
  if (!authorized()) return;
  final library = controller ?? SourceRecoveryScope.maybeOf(context);
  if (library == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Open this collection from the library to repair its sources.',
        ),
      ),
    );
    return;
  }
  {
    if (!context.mounted || !authorized()) return;
    final collection = library.collections
        .where((c) => c.id == collectionId)
        .firstOrNull;
    if (collection == null) return;
    await showFolderHealth(
      context,
      collection,
      () async {
        if (!context.mounted || !authorized()) return;
        await collectionDialog(
          context,
          library,
          existing: collection,
          initialSection: 'Sources',
        );
        await library.load();
      },
      verify: () async {
        if (!authorized()) return;
        await library.scan(collectionId);
        if (context.mounted && authorized()) {
          final current = library.collections
              .where((c) => c.id == collectionId)
              .firstOrNull;
          if (current != null) {
            await showFolderHealth(context, current, () async {
              await collectionDialog(
                context,
                library,
                existing: current,
                initialSection: 'Sources',
              );
            });
          }
        }
      },
    );
  }
}

void showUnavailableSource(
  BuildContext context,
  LibraryController library,
  String collectionId,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(
        'This file is unavailable. Reconnect its folder and scan again.',
      ),
      action: SnackBarAction(
        label: 'Folder health',
        onPressed: () => recoverCollectionSource(
          context,
          collectionId,
          controller: library,
          authorized: () => library.canAccessCollection(collectionId),
        ),
      ),
    ),
  );
}

/// The navigation root supplies its existing owner. Repair never constructs
/// another controller, audio engine, authentication grant or persistence owner.
class SourceRecoveryScope extends InheritedWidget {
  const SourceRecoveryScope({
    super.key,
    required this.library,
    required super.child,
  });
  final LibraryController library;
  static LibraryController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SourceRecoveryScope>()
      ?.library;
  @override
  bool updateShouldNotify(SourceRecoveryScope oldWidget) =>
      oldWidget.library != library;
}
