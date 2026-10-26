import '../core/platform/system_clock.dart';
import '../library/library_service.dart';
import '../features/sources/application/music_scan_workflow.dart';
import 'legacy_music_discovery.dart';
import 'legacy_music_catalog_store.dart';

class MusicScanner extends MusicScanWorkflow {
  MusicScanner(LibraryService service)
    : super(
        LegacyMusicDiscovery(service),
        LegacyMusicCatalogStore(service),
        const SystemClock(),
      );
}
