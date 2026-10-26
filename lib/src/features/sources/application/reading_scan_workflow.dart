import '../../../core/application/clock.dart';
import 'source_ports.dart';
import 'reading_source_ports.dart';
import 'reading_scan_plan.dart';

abstract interface class ReadingScanTask {
  Future<ReadingScanPreview> preview(String collectionId);
  Future<void> apply(String collectionId, ReadingScanPreview preview);
  Future<void> cancel();
}

class ReadingScanWorkflow implements ReadingScanTask {
  ReadingScanWorkflow(
    this.source, {
    required this.authorized,
    required this.clock,
  });
  final ReadingSources source;
  final Clock clock;
  final bool Function(String collectionId) authorized;
  static int _sequence = 0;
  String? _request;
  bool _cancelled = false;
  Stream<ScanProgressEvent> get progress =>
      source.progress.where((e) => _request != null && e.requestId == _request);
  void _access(String id) {
    if (!authorized(id)) throw StateError('Reading collection is unavailable');
  }

  @override
  Future<ReadingScanPreview> preview(
    String collectionId, {
    String encoding = 'utf-8',
    Map<String, String> encodings = const {},
    Map<String, String> rootReplacements = const {},
    Map<String, String> relinks = const {},
    Map<String, String> grouping = const {},
    Map<String, List<String>> resourceOrder = const {},
    List<String> titleOrder = const [],
  }) async {
    if (_request != null) throw StateError('A reading scan is already active');
    _access(collectionId);
    _cancelled = false;
    final request =
        'reading-${clock.now().microsecondsSinceEpoch}-${_sequence++}';
    _request = request;
    try {
      final response = await source.prepare(
        ReadingScanRequest(
          collectionId: collectionId,
          requestId: request,
          encoding: encoding,
          encodings: encodings,
          choices: ReadingScanChoices(
            rootReplacements: rootReplacements,
            relinks: relinks,
            grouping: grouping,
            resourceOrder: resourceOrder,
            titleOrder: titleOrder,
          ),
        ),
        checkAccess: () {
          _access(collectionId);
          if (_cancelled || _request != request) {
            throw StateError('Reading scan cancelled or superseded');
          }
        },
      );
      _access(collectionId);
      if (_cancelled ||
          response.requestId != request ||
          response.collectionId != collectionId) {
        throw StateError('Reading scan cancelled or superseded');
      }
      return response;
    } finally {
      _request = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final request = _request;
    if (request != null) {
      await source.cancel(request);
    }
  }

  ReadingScanPreview revise(
    ReadingScanPreview preview, {
    Map<String, String> relinks = const {},
    Map<String, String> grouping = const {},
    Map<String, List<String>> resourceOrder = const {},
    List<String> titleOrder = const [],
  }) {
    _access(preview.collectionId);
    return source.revise(
      preview,
      ReadingScanChoices(
        relinks: relinks,
        grouping: grouping,
        resourceOrder: resourceOrder,
        titleOrder: titleOrder,
      ),
    );
  }

  @override
  Future<void> apply(String collectionId, ReadingScanPreview preview) async {
    _access(collectionId);
    if (_cancelled) throw StateError('Reading scan cancelled');
    if (collectionId != preview.collectionId) {
      throw ArgumentError('Wrong scan owner');
    }
    if (!preview.canApply) {
      throw StateError(
        'Resolve incomplete scans and ambiguous sources before applying',
      );
    }
    await source.commit(
      preview,
      checkAccess: () {
        _access(collectionId);
        if (_cancelled) throw StateError('Reading scan cancelled');
      },
    );
  }
}
