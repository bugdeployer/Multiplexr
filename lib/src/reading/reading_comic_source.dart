import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import '../library/library_service.dart';
import 'domain/reading_catalog.dart';

class ComicPage {
  ComicPage(this.id, this.width, this.height) {
    if (id.isEmpty ||
        width < 1 ||
        height < 1 ||
        width > 40000 ||
        height > 40000 ||
        width * height > 100000000) {
      throw const FormatException('Invalid comic page');
    }
  }
  final String id;
  final int width, height;
  Rect get bounds => Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
}

abstract interface class ReadingComicSource {
  Future<List<ComicPage>> open(ReadingTitle title);
  Future<Rect> bounds(String id, bool crop);
  Future<Uint8List> tile(String id, Rect region, int targetWidth);
  Future<void> close();
}

class NativeReadingComicSource implements ReadingComicSource {
  NativeReadingComicSource(this.service, {this.pdf = false});
  final bool pdf;
  String method(String comic) => pdf ? comic.replaceAll("Comic", "Pdf") : comic;
  final LibraryService service;
  String? _token, _request;
  int _generation = 0;
  void Function()? _detachMaintenance;
  static int _sequence = 0;
  @override
  Future<List<ComicPage>> open(ReadingTitle title) async {
    await close();
    _detachMaintenance = service.maintenance.register(drain: close);
    final generation = _generation;
    final request =
        'comic-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    _request = request;
    try {
      final raw = jsonDecode(
        (await service.transport.invokeMethod<String>(
          method('openReadingComic'),
          {
            'collectionId': title.catalog.id.collectionId,
            'titleId': title.catalog.id.entityId,
            'revision': title.sourceRevision,
            'requestId': request,
          },
        ))!,
      ) as Map<String, dynamic>;
      final token = raw['token'] as String;
      if (_request == request) _request = null;
      if (generation != _generation) {
        await service.transport.invokeMethod<void>(
          method('closeReadingComic'),
          token,
        );
        throw StateError('Comic open was cancelled');
      }
      _token = token;
      final pages = (raw['pages'] as List)
          .map(
            (p) => ComicPage(
              p['id'] as String,
              p['width'] as int,
              p['height'] as int,
            ),
          )
          .toList();
      if (pages.isEmpty ||
          pages.length > 10000 ||
          pages.map((p) => p.id).toSet().length != pages.length) {
        throw const FormatException('Invalid comic pages');
      }
      return pages;
    } catch (_) {
      if (generation == _generation) await close();
      rethrow;
    } finally {
      if (_request == request) _request = null;
    }
  }

  String get _handle => _token ?? (throw StateError('Comic reader is closed'));
  @override
  Future<Rect> bounds(String id, bool crop) async {
    final raw = jsonDecode(
      (await service.transport.invokeMethod<String>(
        method('readingComicInfo'),
        {'token': _handle, 'pageId': id, 'crop': crop},
      ))!,
    ) as Map<String, dynamic>;
    return Rect.fromLTRB(
      (raw['left'] as num).toDouble(),
      (raw['top'] as num).toDouble(),
      (raw['right'] as num).toDouble(),
      (raw['bottom'] as num).toDouble(),
    );
  }

  @override
  Future<Uint8List> tile(String id, Rect region, int targetWidth) async =>
      (await service.transport.invokeMethod<Uint8List>(
        method('readingComicTile'),
        {
          'token': _handle,
          'pageId': id,
          'left': region.left.round(),
          'top': region.top.round(),
          'width': region.width.round(),
          'height': region.height.round(),
          'targetWidth': targetWidth,
        },
      ))!;
  @override
  Future<void> close() async {
    _generation++;
    final request = _request;
    _request = null;
    final token = _token;
    _token = null;
    try {
      if (request != null) {
        await service.transport.invokeMethod<void>(
          'cancelReadingComic',
          request,
        );
      }
      if (token != null) {
        await service.transport.invokeMethod<void>(
          method('closeReadingComic'),
          token,
        );
      }
    } catch (_) {
      _token = token;
      _request = request;
      rethrow;
    }
    _detachMaintenance?.call();
    _detachMaintenance = null;
  }
}
