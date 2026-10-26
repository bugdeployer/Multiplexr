import '../application/maintenance.dart';
import 'platform_transport.dart';

/// Native requests cannot cross an active restore from a different task.
class MaintenanceTransport implements PlatformTransport {
  const MaintenanceTransport(this.delegate, this.maintenance);
  final PlatformTransport delegate;
  final Maintenance maintenance;
  static const _queries = {
    'load',
    'readState',
    'readStates',
    'readingSnapshot',
  };
  Future<T> _run<T>(String method, Future<T> Function() action) =>
      _queries.contains(method)
      ? maintenance.query(action)
      : maintenance.activity(action);
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) =>
      _run(method, () => delegate.invokeMethod<T>(method, arguments));
  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) => _run(method, () => delegate.invokeMapMethod<K, V>(method, arguments));
}
