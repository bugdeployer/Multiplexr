import 'application_failure.dart';

/// In-flight request generations, not durable catalog revisions or transactions.
class RequestScope {
  int _revision = 0;
  bool _closed = false;
  RequestContext begin() {
    if (_closed) {
      throw const ApplicationFailure(
        ApplicationFailureKind.cancelled,
        'Closed',
      );
    }
    return RequestContext._(this, ++_revision);
  }

  void invalidate() => _revision++;
  void close() {
    _closed = true;
    invalidate();
  }
}

class RequestContext {
  RequestContext._(this._owner, this.revision);
  final RequestScope _owner;
  final int revision;
  bool _cancelled = false;
  bool get isCurrent =>
      !_cancelled && !_owner._closed && revision == _owner._revision;
  void cancel() => _cancelled = true;
  void check() {
    if (!isCurrent) {
      throw const ApplicationFailure(
        ApplicationFailureKind.cancelled,
        'Cancelled',
      );
    }
  }
}
