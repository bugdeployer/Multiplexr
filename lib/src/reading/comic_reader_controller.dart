import '../features/settings/application/reader_preference_commands.dart';

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../catalog/domain/classification.dart';
import '../settings/domain/media_settings.dart';
import 'domain/reader_adapter.dart';
import 'domain/reader_settings.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import 'reading_comic_source.dart';
import '../features/settings/application/reader_preferences.dart';
import '../features/reading/application/reading_progress_store.dart';

class ComicLocationRecovery implements Exception {
  const ComicLocationRecovery();
  @override
  String toString() =>
      'This comic position cannot be restored. Choose a page or explicitly start again.';
}

class ComicReaderController extends ChangeNotifier
    implements ComicReaderAdapter {
  ComicReaderController(
    this.source,
    this.repository, {
    required this.authorized,
    this.pdf = false,
  });
  final bool pdf;
  final ReadingComicSource source;
  final ReadingProgressStore repository;
  final bool Function(String) authorized;
  ReadingTitle? _title;
  ReadingTitle get title =>
      _title ?? (throw StateError('Comic reader is closed'));
  List<ComicPage> pages = const [];
  int pageIndex = 0, _generation = 0, _navigation = 0;
  double offset = 0;
  bool loading = false, _disposed = false;
  Map<String, Object> preferences = const {};
  Map<String, ResolvedSetting<Object>> provenance = const {};
  final _bounds = <String, Rect>{};
  final _tiles = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List>>{};
  Future<void> _queue = Future.value();
  int _bytes = 0;
  static const maxCacheBytes = 8 * 1024 * 1024, maxCacheTiles = 8;
  int get cachedBytes => _bytes;
  int get cachedTiles => _tiles.length;
  @override
  String get id => pdf ? 'multiplexr-pdf-v1' : 'multiplexr-comic-v1';
  @override
  MediaSubtype get subtype => pdf ? MediaSubtype.ebook : MediaSubtype.comics;
  @override
  Set<ReadingFormat> get formats =>
      pdf ? {ReadingFormat.pdf} : {ReadingFormat.cbz, ReadingFormat.images};
  @override
  Set<ReaderCapability> get capabilities => {
    ReaderCapability.contents,
    ReaderCapability.rtl,
    ReaderCapability.webtoon,
    ReaderCapability.zoom,
  };
  Map<String, Object> _pagePreferences(Map<String, Object> values) => pdf
      ? {
          ...values,
          'comicMode': values['pdfMode'] == 'scroll' ? 'webtoon' : 'paged',
          'fit': values['pdfFit'] ?? 'page',
          'direction': 'ltr',
          'spreads': 'single',
          'cropBorders': false,
          'volumeKeys': false,
          'tapZones': 'standard',
        }
      : values;
  bool get webtoon => preferences['comicMode'] == 'webtoon';
  bool get rtl => preferences['direction'] == 'rtl';
  void _access() {
    if (_disposed || !authorized(title.catalog.id.collectionId)) {
      throw StateError('Reading collection is unavailable');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> open(
    ReadingTitle title,
    ReadingLocation? restore,
    Map<String, Object> settings,
  ) async {
    _title = title;
    _access();
    final generation = ++_generation;
    preferences = _pagePreferences(ReaderSettings.validate(subtype, settings));
    try {
      final loaded = await source.open(title);
      _access();
      if (generation != _generation) {
        throw StateError('Comic open was superseded');
      }
      if (!listEquals(
        loaded.map((p) => p.id).toList(),
        title.readingOrder.map((r) => r.id).toList(),
      )) {
        throw const ComicLocationRecovery();
      }
      pages = List.unmodifiable(loaded);
      if (restore != null &&
          (restore is! PageReadingLocation ||
              restore.pageIndex >= pages.length ||
              pages[restore.pageIndex].id != restore.pageId)) {
        throw const ComicLocationRecovery();
      }
      final position = restore as PageReadingLocation?;
      pageIndex = position?.pageIndex ?? 0;
      offset = position?.offset ?? 0;
      await prepare(pageIndex);
      if (!webtoon && preferences['spreads'] == 'landscape' && pageIndex > 0) {
        final first = pageIndex.isEven ? pageIndex - 1 : pageIndex;
        await prepare(first);
        if (first + 1 < pages.length) await prepare(first + 1);
      }
      provenance = resolveReaderPreferences(await repository.read(), title);
      _access();
      _notify();
    } catch (_) {
      await source.close();
      pages = const [];
      rethrow;
    }
  }

  Rect bounds(int index) => !webtoon && preferences['cropBorders'] == true
      ? _bounds[pages[index].id] ?? pages[index].bounds
      : pages[index].bounds;
  Future<void> prepare(int index, {bool force = false}) async {
    _access();
    if ((!force && (webtoon || preferences['cropBorders'] != true)) ||
        _bounds.containsKey(pages[index].id)) {
      return;
    }
    final generation = _generation;
    final page = pages[index];
    final rect = await source.bounds(page.id, true);
    _access();
    if (generation != _generation) {
      throw StateError('Comic request was superseded');
    }
    if (!rect.isFinite ||
        rect.isEmpty ||
        !page.bounds.contains(rect.topLeft) ||
        rect.right > page.width ||
        rect.bottom > page.height) {
      throw const FormatException('Invalid comic crop');
    }
    if (_bounds.length >= 4) _bounds.remove(_bounds.keys.first);
    _bounds[page.id] = rect;
  }

  Future<void> jump(int index, {double withinPage = 0}) async {
    _access();
    readingFraction(withinPage);
    if (index < 0 || index >= pages.length) throw const ComicLocationRecovery();
    final navigation = ++_navigation;
    loading = true;
    _notify();
    try {
      await prepare(index);
      if (!webtoon && preferences['spreads'] == 'landscape' && index > 0) {
        final first = index.isEven ? index - 1 : index;
        await prepare(first);
        if (first + 1 < pages.length) await prepare(first + 1);
      }
      _access();
      if (navigation != _navigation) {
        throw StateError('Comic navigation was superseded');
      }
      pageIndex = index;
      offset = withinPage;
    } finally {
      if (navigation == _navigation) {
        loading = false;
        _notify();
      }
    }
  }

  void anchor(int index, double fraction, {bool notify = false}) {
    _access();
    if (index < 0 || index >= pages.length) throw const ComicLocationRecovery();
    readingFraction(fraction);
    pageIndex = index;
    offset = fraction;
    if (notify) _notify();
  }

  List<int> visiblePages(bool landscape) {
    if (webtoon ||
        !landscape ||
        preferences['spreads'] != 'landscape' ||
        pageIndex == 0) {
      return [pageIndex];
    }
    final first = pageIndex.isEven ? pageIndex - 1 : pageIndex;
    final result = [first, if (first + 1 < pages.length) first + 1];
    return rtl ? result.reversed.toList() : result;
  }

  int turnTarget(bool forward, {required bool landscape}) {
    final spread = visiblePages(landscape);
    return (forward ? spread.reduce(math.max) + 1 : spread.reduce(math.min) - 1)
        .clamp(0, pages.length - 1);
  }

  Future<Uint8List> tile(int index, Rect region, int targetWidth) {
    _access();
    final page = pages[index];
    if (region.isEmpty ||
        !region.isFinite ||
        region.left < 0 ||
        region.top < 0 ||
        region.right > page.width ||
        region.bottom > page.height ||
        targetWidth < 64 ||
        targetWidth > 1536) {
      throw const FormatException('Invalid comic tile');
    }
    final key = '${page.id}:$region:$targetWidth';
    final cached = _tiles.remove(key);
    if (cached != null) {
      _tiles[key] = cached;
      return Future.value(cached);
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    if (_pending.length >= 24) {
      return Future.error(
        StateError('Comic decoder is busy; retry the visible tile'),
      );
    }
    final generation = _generation;
    final operation = _queue.then((_) async {
      _access();
      if (generation != _generation) {
        throw StateError('Comic tile was cancelled');
      }
      final bytes = await source.tile(page.id, region, targetWidth);
      _access();
      if (generation != _generation) {
        throw StateError('Comic tile was cancelled');
      }
      if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) {
        throw const FormatException('Invalid decoded tile');
      }
      while (_tiles.isNotEmpty &&
          (_bytes + bytes.length > maxCacheBytes ||
              _tiles.length >= maxCacheTiles)) {
        _bytes -= _tiles.remove(_tiles.keys.first)!.length;
      }
      _tiles[key] = bytes;
      _bytes += bytes.length;
      return bytes;
    });
    _pending[key] = operation;
    _queue = operation.then<void>(
      (_) {
        _pending.remove(key);
      },
      onError: (Object _, StackTrace _) {
        _pending.remove(key);
      },
    );
    return operation;
  }

  void evictTile(int index, Rect region, int targetWidth) {
    if (index >= pages.length) return;
    final key = '${pages[index].id}:$region:$targetWidth';
    _bytes -= _tiles.remove(key)?.length ?? 0;
  }

  Future<void> prefetch(int index, {int targetWidth = 768}) async {
    if (index < 0 || index >= pages.length) return;
    final generation = _generation;
    try {
      await prepare(index);
      if (generation != _generation) return;
      final b = bounds(index);
      await tile(
        index,
        Rect.fromLTWH(b.left, b.top, b.width, math.min(1024, b.height)),
        targetWidth,
      );
    } catch (_) {
      /* A failed prefetch is retried visibly when the page is opened. */
    }
  }

  @override
  Future<PageReadingLocation> location() async {
    _access();
    if (pages.isEmpty) throw StateError('Comic reader is closed');
    return PageReadingLocation(
      pageId: pages[pageIndex].id,
      pageIndex: pageIndex,
      offset: offset,
    );
  }

  Future<void> setPreferences(
    Map<String, Object> changes, {
    bool reset = false,
  }) async {
    _access();
    if (pdf) {
      changes = {
        for (final entry in changes.entries)
          (entry.key == 'comicMode'
              ? 'pdfMode'
              : entry.key == 'fit'
              ? 'pdfFit'
              : entry.key): entry.key == 'comicMode' && entry.value == 'webtoon'
              ? 'scroll'
              : entry.value,
      };
    }
    await ReaderPreferenceCommands(repository, authorized: authorized).setTitle(
      title,
      changes,
      reset: reset,
      prepare: (next) async {
        final effective = resolveReaderPreferences(next, title);
        if (!pdf &&
            effective['cropBorders']!.value == true &&
            effective['comicMode']!.value == 'paged') {
          await prepare(pageIndex, force: true);
        }
      },
    );
    provenance = resolveReaderPreferences(await repository.read(), title);
    _access();
    preferences = _pagePreferences({
      for (final e in provenance.entries) e.key: e.value.value,
    });
    _notify();
  }

  @override
  Future<void> close() async {
    _generation++;
    _navigation++;
    _tiles.clear();
    _pending.clear();
    _bounds.clear();
    _bytes = 0;
    await source.close();
    pages = const [];
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _navigation++;
    _tiles.clear();
    _bytes = 0;
    super.dispose();
  }
}
