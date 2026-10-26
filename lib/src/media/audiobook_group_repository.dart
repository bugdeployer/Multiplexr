import '../catalog/domain/catalog_models.dart';
import '../catalog/domain/classification.dart';
import '../catalog/domain/group_repository.dart';
import '../features/catalog/application/audiobook_catalog_commands.dart';
import 'audio_models.dart';
import 'audiobook_hierarchy.dart';

CatalogIdentity audiobookTitleIdentity(Audiobook book) =>
    CatalogIdentity(book.id.collectionId, book.id.key, CatalogEntityKind.title);

GroupSnapshot audiobookGroupSnapshot(List<Audiobook> books) {
  final groups = audiobookSeries(books);
  return GroupSnapshot(
    groups: [
      for (final group in groups)
        CatalogGroup<Object?>(
          id: CatalogIdentity(
            group.children.first.id.collectionId,
            group.id,
            CatalogEntityKind.group,
          ),
          subtype: MediaSubtype.audiobooks,
          kind: CatalogGroupKind.series,
          metadata: group.title,
        ),
    ],
    titles: books.map(audiobookTitleIdentity),
    titleSubtypes: {
      for (final book in books)
        audiobookTitleIdentity(book): MediaSubtype.audiobooks,
    },
    memberships: [
      for (final group in groups)
        for (var i = 0; i < group.children.length; i++)
          GroupMembership(
            parent: CatalogIdentity(
              group.children.first.id.collectionId,
              group.id,
              CatalogEntityKind.group,
            ),
            child: audiobookTitleIdentity(group.children[i]),
            kind: MembershipKind.structural,
            order: i,
          ),
    ],
  );
}

/// Commands run inside AudioLibrary's existing serialized read/modify/write.
class AudiobookGroupRepository implements GroupRepository {
  const AudiobookGroupRepository(this.library);
  final AudiobookCatalogCommands library;
  @override
  Future<GroupSnapshot> snapshot() async =>
      audiobookGroupSnapshot(await library.books());
  @override
  Future<void> reorder(
    CatalogIdentity parent,
    List<CatalogIdentity> children,
  ) => library.update((books) {
    if (!library.canAccess(parent.collectionId)) {
      throw StateError('Collection access is required.');
    }
    final order = audiobookGroupSnapshot(books).order(parent, children);
    return [
      for (final book in books)
        if (order.containsKey(audiobookTitleIdentity(book)))
          book.withMetadata({
            'seriesOrder': order[audiobookTitleIdentity(book)]! + 1,
          })
        else
          book,
    ];
  });
}
