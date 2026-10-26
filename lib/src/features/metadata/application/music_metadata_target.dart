import '../../../media/audio_models.dart';
import '../../../media/contracts.dart';
import '../../../media/music_catalog_models.dart';
import '../../catalog/application/music_catalog_commands.dart';
import 'metadata_contracts.dart';
import 'music_metadata_host.dart';

class MusicMetadataTarget implements MetadataTarget {
  MusicMetadataTarget(this.repository, {this.trackId, this.album});
  final MusicMetadataHost repository;
  final MediaId? trackId;
  final MusicAlbum? album;
  @override
  MetadataEntityType get entity => album == null
      ? MetadataEntityType.musicTrack
      : MetadataEntityType.musicAlbum;
  @override
  Object get owner => repository.owner;
  @override
  String get key => trackId?.key ?? 'album:${album!.key}';
  String get collectionId => trackId?.collectionId ?? album!.id.collectionId;
  @override
  bool get authorized => repository.commands.access(collectionId);
  Future<MusicTrack> current() async =>
      (await repository.readCatalog()).tracks.firstWhere(
        (t) => t.id == trackId,
        orElse: () => throw const MetadataFailure(
          MetadataFailureKind.unavailable,
          'Track no longer exists.',
        ),
      );
  @override
  Future<MetadataSnapshot> read() async {
    if (album != null) {
      final extras = await repository.commands.extras();
      final currentAlbums = repository.commands.albums(
        (await repository.readCatalog()).tracks,
        extras,
      );
      final latest = currentAlbums
          .where((a) => a.key == album!.key)
          .firstOrNull;
      if (latest == null) {
        throw const MetadataFailure(
          MetadataFailureKind.unavailable,
          'Album no longer exists.',
        );
      }
      final fields = Map<String, dynamic>.from(
        extras['albums'][album!.key] ?? {},
      );
      return MetadataSnapshot(
        {
          'title': latest.title,
          'artist': latest.artist,
          if (latest.year != null) 'year': latest.year,
          ...fields,
        },
        manualFields: Set<String>.from(
          fields['manualFields'] ??
              (fields['metadataSource'] == 'manual'
                  ? fields.keys.where(
                      (k) => {'title', 'artist', 'year'}.contains(k),
                    )
                  : <String>[]),
        ),
        provider: fields['metadataSource'] ?? '',
      );
    }
    final track = await current();
    return MetadataSnapshot(
      track.metadata.toJson(),
      manualFields: track.overrides.keys.toSet(),
      provider: track.metadata.metadataSource,
    );
  }

  @override
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async => {
    for (final key in [
      'title',
      'artist',
      if (album == null) 'album',
      'year',
      'releaseId',
      'releaseGroupId',
      if (album == null) 'recordingId',
    ])
      if (candidate.values[key] != null &&
          '${candidate.values[key]}'.isNotEmpty)
        key: candidate.values[key],
  };
  @override
  Future<void> commit(
    Map<String, dynamic> selected,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    cancellation.check();
    if (!authorized) {
      throw const MetadataFailure(
        MetadataFailureKind.permission,
        'Collection access required.',
      );
    }
    if (album != null) {
      await repository.commands.setAlbum(album!, {
        ...selected,
        'metadataSource': candidate.provenance,
      });
    } else {
      await repository.commands.patchTrack(trackId!, (track) {
        cancellation.check();
        return MusicTrack(
          id: track.id,
          source: track.source,
          rootId: track.rootId,
          folderId: track.folderId,
          albumId: track.albumId,
          available: track.available,
          overrides: {...track.overrides}
            ..removeWhere((k, v) => selected.containsKey(k)),
          metadata: MusicMetadata.fromJson({
            ...track.metadata.toJson(),
            ...selected,
            'metadataSource': candidate.provenance,
          }),
        );
      });
      await repository.markMetadataApplied(
        collectionId,
        trackId!.key,
        authorized: () => authorized,
      );
    }
  }
}
