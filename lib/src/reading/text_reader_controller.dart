import '../features/settings/application/reader_preference_commands.dart';

import 'package:flutter/foundation.dart';

import '../catalog/domain/classification.dart';
import '../settings/domain/media_settings.dart';
import 'domain/reader_adapter.dart';
import 'domain/reader_settings.dart';
import 'domain/reading_catalog.dart';
import 'domain/reading_location.dart';
import '../features/settings/application/reader_preferences.dart';
import '../features/reading/application/reading_progress_store.dart';
import 'reading_text_source.dart';

class TextLocationRecovery implements Exception {
  const TextLocationRecovery();
  @override
  String toString() =>
      'This text position could not be restored. Open the chapter from its beginning or choose another saved position.';
}

class TextReaderController extends ChangeNotifier implements TextReaderAdapter {
  TextReaderController(
    this.source,
    this.repository, {
    required this.authorized,
  });
  final ReadingTextSource source;
  final ReadingProgressStore repository;
  final bool Function(String) authorized;
  ReadingTitle? _title;
  ReadingTitle get title => _title ?? (throw StateError('Reader is closed'));
  ReadingTextResource? content;
  String resourceId = '';
  int offset = 0, _generation = 0;
  bool loading = false, _disposed = false;
  Map<String, Object> preferences = const {};
  Map<String, ResolvedSetting<Object>> provenance = const {};
  @override
  String get id => 'multiplexr-text-v1';
  @override
  MediaSubtype get subtype => MediaSubtype.ebook;
  @override
  Set<ReadingFormat> get formats => {ReadingFormat.epub, ReadingFormat.txt};
  @override
  Set<ReaderCapability> get capabilities => {
    ReaderCapability.contents,
    ReaderCapability.search,
    ReaderCapability.selection,
    ReaderCapability.annotations,
    ReaderCapability.reflow,
  };
  void _access() {
    if (!authorized(title.catalog.id.collectionId)) {
      throw StateError('Reading collection is unavailable');
    }
  }

  Future<List<ReadingContentsEntry>> contents() async {
    _access();
    final entries = await source.contents();
    _access();
    return entries;
  }

  Future<List<ReadingSearchResult>> search(String query) async {
    _access();
    final results = await source.search(query);
    _access();
    return results;
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
    preferences = ReaderSettings.validate(title.catalog.subtype, settings);
    await source.open(title);
    try {
      _access();
      if (restore != null && restore is! TextReadingLocation) {
        throw const TextLocationRecovery();
      }
      final position = restore as TextReadingLocation?;
      await jump(position?.resourceId ?? title.readingOrder.first.id, 0);
      if (position != null) {
        final data = content!;
        int? restored;
        if (position.locatorType == TextLocatorType.textOffset) {
          restored = int.tryParse(position.locator);
        }
        if (position.locatorType == TextLocatorType.cssSelector &&
            position.locator.startsWith('#')) {
          restored = data.anchors[position.locator.substring(1)];
        }
        if (restored == null || restored > data.text.length || restored < 0) {
          throw const TextLocationRecovery();
        }
        if (position.before.isNotEmpty &&
                !data.text.substring(0, restored).endsWith(position.before) ||
            position.after.isNotEmpty &&
                !data.text.substring(restored).startsWith(position.after)) {
          throw const TextLocationRecovery();
        }
        offset = safeOffset(data.text, restored);
      }
      provenance = resolveReaderPreferences(await repository.read(), title);
      _access();
      _notify();
    } catch (_) {
      await source.close();
      rethrow;
    }
  }

  static int safeOffset(String text, int value) {
    var offset = value.clamp(0, text.length);
    if (offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff) {
      offset--;
    }
    return offset;
  }

  Future<void> jump(String id, int position, {String? anchor}) async {
    _access();
    if (!title.readingOrder.any((r) => r.id == id)) {
      throw const TextLocationRecovery();
    }
    final generation = ++_generation;
    loading = true;
    _notify();
    try {
      final next = id == resourceId && content != null
          ? content!
          : await source.resource(id);
      if (generation != _generation || _disposed) {
        throw StateError('Reading request was superseded');
      }
      _access();
      if (anchor != null && anchor.isNotEmpty) {
        final resolved = next.anchors[anchor];
        if (resolved == null) throw const TextLocationRecovery();
        position = resolved;
      }
      if (position < 0 || position > next.text.length) {
        throw const TextLocationRecovery();
      }
      content = next;
      resourceId = id;
      offset = safeOffset(next.text, position);
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void setOffset(int value, {bool notify = true}) {
    _access();
    if (content == null) return;
    offset = safeOffset(content!.text, value);
    if (notify) _notify();
  }

  @override
  Future<TextReadingLocation> location() async {
    _access();
    final text = content?.text ?? (throw StateError('No text resource'));
    return TextReadingLocation(
      resourceId: resourceId,
      locatorType: TextLocatorType.textOffset,
      locator: '$offset',
      progression: text.isEmpty ? 0 : offset / text.length,
      before: text.substring((offset - 40).clamp(0, text.length), offset),
      after: text.substring(offset, (offset + 40).clamp(0, text.length)),
    );
  }

  Future<void> setPreferences(
    Map<String, Object> changes, {
    bool reset = false,
  }) async {
    _access();
    await ReaderPreferenceCommands(
      repository,
      authorized: authorized,
    ).setTitle(title, changes, reset: reset);
    provenance = resolveReaderPreferences(await repository.read(), title);
    _access();
    preferences = {for (final e in provenance.entries) e.key: e.value.value};
    _notify();
  }

  @override
  Future<void> close() async {
    _generation++;
    await source.close();
    content = null;
    resourceId = '';
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
