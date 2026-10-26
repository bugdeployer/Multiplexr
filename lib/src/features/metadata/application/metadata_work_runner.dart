import 'metadata_contracts.dart';

/// Single-flight, bounded (one item) runner. Work IDs are checkpointed before
/// I/O and consumed after commit; hosts own durable journal storage.
class MetadataJobBusy extends MetadataFailure {
  const MetadataJobBusy()
    : super(
        MetadataFailureKind.conflict,
        'A metadata job is already running for this collection.',
      );
}

class MetadataWorkRunner {
  MetadataWorkRunner({required this.classify});
  final MetadataFailure Function(Object) classify;
  static final _owners = Expando<Set<String>>();
  Future<bool> run<T>({
    required Object owner,
    required String key,
    required Iterable<T> work,
    required MetadataCancellation cancellation,
    required Future<void> Function() checkpoint,
    required Future<void> Function(T) process,
    required Future<void> Function(T) completed,
    Future<void> Function()? yieldBatch,
    Future<void> Function()? prepare,
  }) async {
    final active = _owners[owner] ??= <String>{};
    if (!active.add(key)) {
      throw const MetadataJobBusy();
    }
    try {
      if (cancellation.cancelled) return false;
      await checkpoint();
      if (cancellation.cancelled) return false;
      if (prepare != null) await prepare();
      if (cancellation.cancelled) return false;
      for (final item in work) {
        if (cancellation.cancelled) return false;
        await process(item);
        if (cancellation.cancelled) return false;
        await completed(item);
        await checkpoint();
        if (yieldBatch != null) await yieldBatch();
      }
      return true;
    } finally {
      active.remove(key);
    }
  }

  /// Transient network retries only; auth/rate limit/storage require user action.
  Future<T> request<T>(
    Future<T> Function() operation,
    MetadataCancellation cancellation, {
    Future<void> Function(Duration)? delay,
    int attempts = 3,
  }) async {
    final wait = delay ?? Future<void>.delayed;
    for (var attempt = 0; ; attempt++) {
      cancellation.check();
      try {
        final result = await operation();
        cancellation.check();
        return result;
      } catch (error) {
        final failure = classify(error);
        if (!failure.retryable || attempt + 1 >= attempts) rethrow;
        await wait(Duration(milliseconds: 200 * (1 << attempt)));
      }
    }
  }
}
