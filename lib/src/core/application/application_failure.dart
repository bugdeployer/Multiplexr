/// Stable application categories; adapters translate platform/provider details.
enum ApplicationFailureKind {
  cancelled,
  permission,
  authentication,
  rateLimit,
  network,
  storage,
  unavailable,
  conflict,
  invalidResponse,
  unknown,
}

class ApplicationFailure implements Exception {
  const ApplicationFailure(this.kind, this.message);
  final ApplicationFailureKind kind;
  final String message;
  @override
  String toString() => message;
}
