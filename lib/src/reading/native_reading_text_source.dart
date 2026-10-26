import 'dart:convert';
import 'dart:typed_data';

import '../library/library_service.dart';
import 'domain/reading_catalog.dart';
import 'reading_text_source.dart';

class NativeReadingTextSource
    implements ReadingTextSource, ReadingLinkedResources, ReadingImages {
  NativeReadingTextSource(this.service);
  final LibraryService service;
  String? _token, _request;
  int _generation = 0;
  void Function()? _detachMaintenance;
  static int _sequence = 0;
  String _newRequest() =>
      'text-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
  @override
  Future<void> open(ReadingTitle title) async {
    await close();
    _detachMaintenance = service.maintenance.register(drain: close);
    final generation = _generation;
    final request = _newRequest();
    _request = request;
    try {
      final token = (await service.transport.invokeMethod<String>(
        'openReadingText',
        {
          'collectionId': title.catalog.id.collectionId,
          'titleId': title.catalog.id.entityId,
          'revision': title.sourceRevision,
          'requestId': request,
        },
      ))!;
      if (generation != _generation) {
        await service.transport.invokeMethod<void>('closeReadingText', token);
        throw StateError('Reading open cancelled');
      }
      _token = token;
    } finally {
      if (_request == request) _request = null;
    }
  }

  @override
  Future<ReadingTextResource> resource(String id) async =>
      ReadingTextResource.fromJson(
        jsonDecode(
          (await service.transport.invokeMethod<String>('readingTextResource', {
            'token': _token ?? (throw StateError('Reader is closed')),
            'resourceId': id,
          }))!,
        ) as Map<String, dynamic>,
      );
  @override
  Future<ReadingTextResource> linkedResource(
    String resourceId,
    String href,
  ) async => ReadingTextResource.fromJson(
    jsonDecode(
      (await service.transport.invokeMethod<String>('readingTextLink', {
        'token': _token ?? (throw StateError('Reader is closed')),
        'resourceId': resourceId,
        'href': href,
      }))!,
    ) as Map<String, dynamic>,
  );

  @override
  Future<Uint8List> image(String resourceId, String href) async =>
      (await service.transport.invokeMethod<Uint8List>('readingTextImage', {
        'token': _token ?? (throw StateError('Reader is closed')),
        'resourceId': resourceId,
        'href': href,
      }))!;
  @override
  Future<List<ReadingSearchResult>> search(String query) async {
    await cancel();
    final request = _newRequest();
    _request = request;
    try {
      final json = jsonDecode(
        (await service.transport.invokeMethod<String>('searchReadingText', {
          'token': _token,
          'requestId': request,
          'query': query,
        }))!,
      ) as Map<String, dynamic>;
      if (_request != request) throw StateError('Search was cancelled');
      return (json['results'] as List)
          .map(
            (r) => ReadingSearchResult(
              r['resourceId'] as String,
              r['offset'] as int,
              r['quote'] as String,
              r['context'] as String,
            ),
          )
          .toList();
    } finally {
      if (_request == request) _request = null;
    }
  }

  @override
  Future<List<ReadingContentsEntry>> contents() async =>
      (jsonDecode(
            (await service.transport.invokeMethod<String>(
              'readingTextContents',
              _token,
            ))!,
          ) as List)
          .map(
            (r) => ReadingContentsEntry(
              r['resourceId'] as String,
              r['label'] as String,
              anchor: r['anchor'] as String,
            ),
          )
          .toList();
  @override
  Future<void> cancel() async {
    final request = _request;
    _request = null;
    if (request != null) {
      await service.transport.invokeMethod<void>('cancelReadingText', request);
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    await cancel();
    final token = _token;
    _token = null;
    try {
      if (token != null) {
        await service.transport.invokeMethod<void>('closeReadingText', token);
      }
    } catch (_) {
      _token = token;
      rethrow;
    }
    _detachMaintenance?.call();
    _detachMaintenance = null;
  }

  @override
  Future<void> textAction(String action, String text) =>
      service.transport.invokeMethod<void>('readingTextAction', {
        'action': action,
        'text': text,
      });
}
