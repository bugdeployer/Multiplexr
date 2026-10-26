import '../../catalog/application/audiobook_catalog_commands.dart';

abstract interface class AudiobookMetadataHost {
  Object get owner;
  AudiobookCatalogCommands get commands;
  Future<String> downloadArtwork(String location, String provider);
}
