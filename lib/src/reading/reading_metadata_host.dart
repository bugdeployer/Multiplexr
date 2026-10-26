import 'dart:typed_data';

import '../features/catalog/application/reading_catalog_commands.dart';
import '../core/application/maintenance.dart';

/// Metadata adapters depend on commands and persistence ownership, never the
/// facade that constructs their registry/provider.
abstract interface class ReadingMetadataHost {
  Maintenance get maintenance;
  Object get owner;
  bool Function(String) get authorized;
  ReadingCatalogCommands get commands;
  Future<String> storeArtwork(Uint8List bytes);
}
