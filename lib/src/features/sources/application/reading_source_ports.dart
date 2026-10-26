import 'reading_scan_plan.dart';
import 'source_ports.dart';
import '../../../library/library_models.dart';

abstract interface class ReadingSources {
  Stream<ScanProgressEvent> get progress;
  Future<ReadingScanPreview> prepare(
    ReadingScanRequest request, {
    required void Function() checkAccess,
  });
  ReadingScanPreview revise(
    ReadingScanPreview preview,
    ReadingScanChoices choices,
  );
  Future<void> cancel(String requestId);
  Future<void> commit(
    ReadingScanPreview preview, {
    required void Function() checkAccess,
  });
  Future<LibraryRoot?> pickRoot();
  Future<void> releaseRoots(List<String> uris);
}
