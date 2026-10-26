import '../../../media/audio_models.dart';
import '../../../media/contracts.dart';
import 'audiobook_metadata_host.dart';
import 'metadata_contracts.dart';
import 'artwork_service.dart';

class AudiobookMetadataTarget implements MetadataTarget {
  AudiobookMetadataTarget(this.library, this.id);
  @override
  MetadataEntityType get entity => MetadataEntityType.audiobook;
  final AudiobookMetadataHost library;
  final MediaId id;
  final artwork = ArtworkService();
  String? _remoteCover, _localCover;
  @override
  Object get owner => library.owner;
  @override
  String get key => id.key;
  @override
  bool get authorized => library.commands.canAccess(id.collectionId);
  Future<Audiobook> current() async {
    final book = (await library.commands.books())
        .where((b) => b.id == id)
        .firstOrNull;
    if (book == null) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'This audiobook no longer exists.',
      );
    }
    return book;
  }

  @override
  Future<MetadataSnapshot> read() async {
    final m = (await current()).metadata;
    return MetadataSnapshot(
      {
        ...m.toJson(),
        if (_localCover != null && m.cover == _localCover)
          'cover': _remoteCover,
      },
      provider: m.metadataSource == 'manual' && m.providerId.isNotEmpty
          ? (m.providerId.startsWith('audiobookdb:')
                ? 'audiobookdb'
                : 'audible')
          : m.metadataSource,
      candidateId: m.providerId,
      manualFields: {
        if (m.metadataSource == 'manual') ...textFields,
        if (m.coverSource == 'manual') 'cover',
      },
    );
  }

  static const textFields = {
    'title',
    'author',
    'narrator',
    'description',
    'language',
    'publisher',
    'publicationDate',
  };
  @override
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async => {
    for (final field in textFields)
      if ((candidate.values[field] ?? '').toString().isNotEmpty)
        field: candidate.values[field],
    if ((candidate.values['coverUrl'] ?? '').toString().isNotEmpty)
      'cover': candidate.values['coverUrl'],
  };
  @override
  Future<void> commit(
    Map<String, dynamic> selected,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    final before = await current();
    final patch = Map<String, dynamic>.from(selected);
    if (patch['cover'] != null) {
      patch['cover'] = await artwork.select(
        ArtworkCandidate(
          location: patch['cover'],
          role: ArtworkRole.cover,
          source: ArtworkSource.online,
          ownerId: key,
          provider: candidate.provenance,
          attribution: candidate.attribution,
        ),
        cancellation,
        download: (url) => library.downloadArtwork(url, candidate.provider),
      );
      _remoteCover = selected['cover'];
      _localCover = patch['cover'];
      patch['coverSource'] = candidate.provider;
    }
    // Read after artwork I/O; retain source order, chapters, tags and grouping.
    cancellation.check();
    final book = before;
    if (!authorized) {
      throw const MetadataFailure(
        MetadataFailureKind.permission,
        'Collection access is required.',
      );
    }
    await library.commands.update((values) {
      cancellation.check();
      final current = values.where((b) => b.id == id).firstOrNull;
      if (current == null) {
        throw const MetadataFailure(
          MetadataFailureKind.unavailable,
          'This audiobook no longer exists.',
        );
      }
      for (final key in selected.keys) {
        if (current.metadata.toJson()[key] != book.metadata.toJson()[key]) {
          throw const MetadataFailure(
            MetadataFailureKind.conflict,
            'Metadata changed during artwork download. Reopen the match.',
          );
        }
      }
      return [
        for (final value in values)
          if (value.id == id)
            current.withMetadata({
              ...patch,
              'providerId': candidate.id,
              'metadataSource': current.metadata.metadataSource == 'manual'
                  ? 'manual'
                  : candidate.provenance,
            })
          else
            value,
      ];
    });
  }
}
