import 'dart:convert';

import '../../../media/audio_models.dart';
import '../../../media/contracts.dart';
import 'audiobook_catalog_ports.dart';

class AudiobookCatalogCommands {
  const AudiobookCatalogCommands(
    this.store, {
    this.collectionId,
    this.authorized,
  });
  final AudiobookCatalogStore store;
  final bool Function(String)? authorized;
  bool canAccess(String id) =>
      (collectionId == null || collectionId == id) &&
      (authorized?.call(id) ?? true);
  final String? collectionId;
  Future<T> _mutate<T>(Future<T> Function() change) => store.mutate(change);

  Future<List<Audiobook>> books() async {
    final data = await store.read();
    if (data == null) return [];
    if (data['version'] != 1) {
      throw const FormatException('Unsupported audio library version');
    }
    return (data['books'] as List)
        .map((b) => Audiobook.fromJson(Map<String, dynamic>.from(b)))
        .where((b) => collectionId == null || b.id.collectionId == collectionId)
        .toList();
  }

  Future<List<Audiobook>> query() async {
    if (collectionId != null && !canAccess(collectionId!)) return [];
    final result = await books();
    return result.where((b) => canAccess(b.id.collectionId)).toList();
  }

  Future<void> remove(Audiobook book) =>
      update((books) => books.where((b) => b.id != book.id).toList());
  Future<void> save(List<Audiobook> books) => _mutate(() => _save(books));
  Future<void> update(List<Audiobook> Function(List<Audiobook>) change) =>
      _mutate(() async {
        await _save(change(await books()));
      });
  Future<void> _save(List<Audiobook> books) async {
    final changedCollections = <String>{};
    if (authorized != null) {
      final previous = {for (final book in await this.books()) book.id: book};
      final next = {for (final book in books) book.id: book};
      for (final id in {...previous.keys, ...next.keys}) {
        if (jsonEncode(previous[id]?.toJson()) !=
            jsonEncode(next[id]?.toJson())) {
          changedCollections.add(id.collectionId);
        }
      }
    }

    if (collectionId != null &&
        books.any((b) => b.id.collectionId != collectionId)) {
      throw ArgumentError('Book belongs to another collection');
    }
    if (books.map((b) => b.id).toSet().length != books.length) {
      throw ArgumentError('Duplicate book identity');
    }
    final all = collectionId == null
        ? books
        : [
            ...await AudiobookCatalogCommands(store).books().then(
              (values) => values
                  .where((b) => b.id.collectionId != collectionId)
                  .toList(),
            ),
            ...books,
          ];
    final state = await store.read();
    if (changedCollections.any((id) => !canAccess(id))) {
      throw StateError('Collection access is required.');
    }
    await store.write({
      if (state?['seriesMetadata'] != null)
        'seriesMetadata': state!['seriesMetadata'],
      'version': 1,
      'books': all.map((b) => b.toJson()).toList(),
    });
  }

  Future<AudiobookSeriesMetadata?> seriesMetadata(String id) async {
    final state = await store.read();
    final value = (state?['seriesMetadata'] as Map?)?[id];
    if (value == null) return null;
    final metadata = AudiobookSeriesMetadata.fromJson(
      Map<String, dynamic>.from(value),
    );
    if (collectionId != null && metadata.collectionId != collectionId) {
      throw StateError('Series belongs to another collection');
    }
    return metadata;
  }

  Future<void> saveSeriesMetadata(AudiobookSeriesMetadata metadata) =>
      _mutate(() async {
        if (collectionId != null && metadata.collectionId != collectionId) {
          throw ArgumentError('Series belongs to another collection');
        }
        final state = await store.read() ?? {'version': 1, 'books': []};
        if (!canAccess(metadata.collectionId)) {
          throw StateError('Collection access is required.');
        }
        await store.write({
          ...state,
          'seriesMetadata': {
            ...?state['seriesMetadata'] as Map?,
            metadata.id: metadata.toJson(),
          },
        });
      });

  Future<Audiobook> add(
    AudiobookMetadata metadata,
    List<AudioFile> files, {
    List<AudiobookChapterMarker>? chapters,
  }) => _mutate(() async {
    final current = await books();
    final sources = files.map((f) => f.uri).toSet();
    for (final b in current) {
      if (b.files.any((f) => sources.contains(f.uri))) {
        throw StateError('Some files already belong to “${b.metadata.title}”.');
      }
    }
    final book = Audiobook(
      id: MediaId(
        MediaKind.audiobook,
        collectionId ?? 'audiobooks',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
      metadata: metadata,
      files: files,
      chapters: chapters,
    );
    await _save([...current, book]);
    return book;
  });

  Future<void> replace(Audiobook book) => _mutate(() async {
    if (!canAccess(book.id.collectionId)) {
      throw StateError('Collection access is required.');
    }
    final current = await books();
    if (!current.any((b) => b.id == book.id)) {
      throw StateError('Book no longer exists.');
    }
    final sources = book.files.map((f) => f.uri).toSet();
    if (current.any(
      (b) => b.id != book.id && b.files.any((f) => sources.contains(f.uri)),
    )) {
      throw StateError('Some files already belong to another book.');
    }
    await _save([for (final b in current) b.id == book.id ? book : b]);
  });
}
