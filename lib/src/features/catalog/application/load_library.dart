import '../../../core/application/application_failure.dart';
import '../../../core/application/request_scope.dart';
import 'library_ports.dart';

/// Read orchestration is independent of Flutter and the legacy storage adapter.
class LoadLibrary {
  const LoadLibrary(this.repository);
  final LibraryRepository repository;
  Future<LibrarySnapshot> call(RequestContext request) async {
    request.check();
    try {
      final snapshot = await repository.load();
      request.check();
      return snapshot;
    } on ApplicationFailure {
      request.check();
      rethrow;
    } catch (_) {
      request.check();
      throw const ApplicationFailure(
        ApplicationFailureKind.unknown,
        'Could not load your library. Try again.',
      );
    }
  }
}
