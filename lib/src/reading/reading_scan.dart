// Compatibility constructor for existing adapters and tests. Screens use the
// ReadingLibrary scan factory; workflow and reconciliation are application code.
import '../core/platform/system_clock.dart';
import '../library/library_service.dart';
import '../features/sources/application/reading_scan_workflow.dart';
import 'legacy_reading_sources.dart';
export 'reading_document_scan_plan.dart';
export '../features/sources/application/reading_scan_workflow.dart';

class ReadingScanService extends ReadingScanWorkflow {
  ReadingScanService(LibraryService service, {required super.authorized})
    : super(LegacyReadingSources(service), clock: const SystemClock());
}
