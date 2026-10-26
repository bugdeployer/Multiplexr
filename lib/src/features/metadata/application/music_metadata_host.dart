import '../../catalog/application/music_catalog_commands.dart';
import '../../../media/music_catalog_models.dart';

abstract interface class MusicMetadataHost {
  Object get owner;
  MusicCatalogCommands get commands;
  Future<MusicCatalog> readCatalog();
  Future<void> markMetadataApplied(
    String collectionId,
    String trackKey, {
    required bool Function() authorized,
  });
}
