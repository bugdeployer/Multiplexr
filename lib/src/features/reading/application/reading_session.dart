import '../../../settings/domain/media_settings.dart';
import '../../../reading/domain/reader_adapter.dart';
import '../../../reading/domain/reader_settings.dart';
import '../../../reading/domain/reading_catalog.dart';
import '../../../reading/domain/reading_location.dart';
import 'reading_progress_store.dart';

/// An app-owned lifecycle; no widgets, native engine or production bindings.
class ReadingSession {
  ReadingSession(this.repository, this.adapter, {required this.authorized});
  final ReadingProgressStore repository;
  final ReaderAdapter adapter;
  final bool Function(String collectionId) authorized;
  ReaderSessionState _state = ReaderSessionState.closed;
  ReaderSessionState get state => _state;
  ReadingTitle? _title;
  bool _busy = false;
  bool _finished = false;
  bool get finished => _finished;

  Future<T> _operation<T>(Future<T> Function() operation) async {
    if (_busy) throw StateError('A reading operation is already active');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  void _access(String collectionId) {
    if (!authorized(collectionId)) {
      throw StateError('Reading collection is unavailable');
    }
  }

  Future<void> open(
    ReadingTitle title, {
    bool restart = false,
    ReadingLocation? recovered,
  }) => _operation(() async {
    if (_state == ReaderSessionState.open) {
      throw StateError('Close the current reading session first');
    }
    _access(title.catalog.id.collectionId);
    if (adapter.subtype != title.catalog.subtype ||
        !adapter.formats.contains(title.format)) {
      throw UnsupportedError('Reader does not support this publication');
    }
    _state = ReaderSessionState.opening;
    try {
      final catalog = await repository.read();
      final current = catalog.titles
          .where((t) => t.catalog.id == title.catalog.id)
          .firstOrNull;
      if (current == null ||
          current.sourceRevision != title.sourceRevision ||
          current.catalog.sources.single.id !=
              title.catalog.sources.single.id ||
          !current.catalog.sources.single.available) {
        throw StateError('Publication is unavailable or changed; reload it');
      }
      final saved = catalog.progress
          .where((p) => p.id == title.catalog.id)
          .firstOrNull;
      if (saved != null &&
          !saved.matches(current) &&
          !restart &&
          recovered == null) {
        _state = ReaderSessionState.recoveryRequired;
        throw ReadingRecoveryRequired(saved);
      }
      final restore = recovered ?? (restart ? null : saved?.location);
      if (restore != null) {
        _validate(catalog, current, restore, saved?.finished ?? false);
      }
      final parent = catalog.memberships
          .where((m) => m.child == current.catalog.id)
          .firstOrNull
          ?.parent;
      final layers =
          catalog.settings
              .where(
                (s) =>
                    s.subtype == current.catalog.subtype &&
                    (s.scope == SettingsScope.app ||
                        s.collectionId == current.catalog.id.collectionId &&
                            (s.scope == SettingsScope.collection ||
                                s.scope == SettingsScope.group &&
                                    s.entityId == parent?.entityId ||
                                s.scope == SettingsScope.title &&
                                    s.entityId == current.catalog.id.entityId)),
              )
              .toList()
            ..sort((a, b) => a.scope.index.compareTo(b.scope.index));
      final settings = {
        for (final d in ReaderSettings.definitions(current.catalog.subtype))
          d.id: const SettingsResolver()
              .resolve(d, layers.map((s) => s.layer))
              .value,
      };
      _access(current.catalog.id.collectionId);
      try {
        await adapter.open(current, restore, settings);
        _access(current.catalog.id.collectionId);
      } catch (_) {
        await adapter.close();
        rethrow;
      }
      _title = current;
      _finished = restart ? false : saved?.finished ?? false;
      _state = ReaderSessionState.open;
    } catch (_) {
      if (_state != ReaderSessionState.recoveryRequired) {
        _state = ReaderSessionState.closed;
      }
      rethrow;
    }
  });

  ReadingProgress _progress(
    ReadingTitle title,
    ReadingLocation location,
    bool finished,
  ) => ReadingProgress(
    id: title.catalog.id,
    sourceId: title.catalog.sources.single.id,
    sourceRevision: title.sourceRevision,
    location: location,
    finished: finished,
  );

  void _validate(
    ReadingCatalog c,
    ReadingTitle title,
    ReadingLocation location,
    bool finished,
  ) {
    ReadingCatalog(
      collections: c.collections,
      groups: c.groups,
      titles: c.titles,
      memberships: c.memberships,
      settings: c.settings,
      progress: [_progress(title, location, finished)],
    );
  }

  Future<void> save({bool? finished}) => _operation(() => _save(finished));
  Future<void> _save(bool? finished) async {
    final title = _title;
    if (_state != ReaderSessionState.open || title == null) {
      throw StateError('No reading session');
    }
    _access(title.catalog.id.collectionId);
    final location = await adapter.location();
    _access(title.catalog.id.collectionId);
    await repository.update((c) async {
      _access(title.catalog.id.collectionId);
      final current = c.titles
          .where((t) => t.catalog.id == title.catalog.id)
          .firstOrNull;
      if (current == null ||
          current.sourceRevision != title.sourceRevision ||
          !current.catalog.sources.single.available ||
          current.catalog.sources.single.id !=
              title.catalog.sources.single.id) {
        throw StateError('Publication changed while reading');
      }
      return ReadingCatalog(
        collections: c.collections,
        groups: c.groups,
        titles: c.titles,
        memberships: c.memberships,
        settings: c.settings,
        progress: [
          ...c.progress.where((p) => p.id != title.catalog.id),
          _progress(title, location, finished ?? _finished),
        ],
      );
    });
    _finished = finished ?? _finished;
  }

  /// A failed save leaves the reader open, allowing retry instead of losing position.
  Future<void> close() => _operation(() async {
    if (_state == ReaderSessionState.open) await _save(null);
    await adapter.close();
    _title = null;
    _state = ReaderSessionState.closed;
  });

  /// Permission revocation or explicit discard must still release the renderer.
  /// The last successfully saved progress stays intact.
  Future<void> discard() => _operation(() async {
    await adapter.close();
    _title = null;
    _state = ReaderSessionState.closed;
  });
}
