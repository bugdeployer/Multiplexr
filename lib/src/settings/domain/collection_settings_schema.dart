import '../../catalog/domain/classification.dart';
import 'media_settings.dart';

enum CollectionFieldOwner {
  identity,
  sources,
  settings,
  scanState,
  navigationState,
}

class CollectionField {
  const CollectionField(
    this.id,
    this.label,
    this.owner,
    this.accepts, {
    this.audioOnly = false,
  });
  final String id, label;
  final CollectionFieldOwner owner;
  final bool Function(Object?) accepts;
  final bool audioOnly;
  Set<SettingsScope> get scopes => switch (id) {
    'openAction' => MediaSettings.opening.scopes,
    'audioRate' => MediaSettings.rate.scopes,
    'player' => MediaSettings.engine.scopes,
    'autoplayNext' => MediaSettings.autoplayNext.scopes,
    _ => const {SettingsScope.collection},
  };
  bool get resettable =>
      owner == CollectionFieldOwner.settings && id != 'name' && id != 'locked';
  Object? get defaultValue => CollectionSettingsSchema.defaults[id];
  bool appliesTo(MediaType type) => !audioOnly || type == MediaType.audio;
}

bool _text(Object? v) => v is String;
bool _flag(Object? v) => v is bool;
bool _number(Object? v) => v is num && v.isFinite && v >= 0;
bool _cardSize(Object? v) => v is num && v.isFinite && v >= 100 && v <= 300;
bool _strings(Object? v) => v is List && v.every((x) => x is String);
bool _roots(Object? v) =>
    v is List &&
    v.every(
      (x) =>
          x is Map &&
          x['uri'] is String &&
          x['name'] is String &&
          (x['contentSubtype'] == null ||
              {'movies', 'tv'}.contains(x['contentSubtype'])),
    );
bool _health(Object? v) =>
    v is Map && v.entries.every((e) => e.key is String && e.value is String);
bool _type(Object? v) => {'video', 'audio'}.contains(v);
bool _subtype(Object? v) =>
    {'videos', 'cinema', 'movies', 'tv', 'audiobooks', 'music'}.contains(v);
bool _view(Object? v) =>
    {'compact', 'list', 'grid', 'netflix', 'posterWall'}.contains(v);
bool _player(Object? v) => {'internal', 'external'}.contains(v);
bool _opening(Object? v) => {'automatic', 'details', 'play'}.contains(v);
bool _rate(Object? v) => v is num && v.isFinite && v >= .5 && v <= 3;

/// Complete persisted collection inventory. Identity/source/runtime fields are
/// explicit owners, not accidentally inheritable user preferences.
abstract final class CollectionSettingsSchema {
  static const Map<String, Object?> defaults = {
    'id': null,
    'name': '',
    'type': 'video',
    'subtype': 'videos',
    'roots': <Object>[],
    'extensions': ['mp4', 'mkv', 'mov', 'webm', 'm4v'],
    'view': 'grid',
    'player': 'internal',
    'openAction': 'automatic',
    'audioRate': 1.0,
    'autoplayNext': false,
    'locked': false,
    'includeInGlobalAudio': true,
    'includeInGlobalCinema': true,
    'includeInGlobalVideos': true,
    'allowFolders': false,
    'sort': 'title',
    'filter': 'all',
    'cardSize': 180.0,
    'scrollOffset': 0.0,
    'folder': '',
    'lastScanAt': 0,
    'rootHealth': <String, String>{},
  };
  static const fields = [
    CollectionField(
      'id',
      'Collection ID',
      CollectionFieldOwner.identity,
      _text,
    ),
    CollectionField(
      'name',
      'Collection name',
      CollectionFieldOwner.settings,
      _text,
    ),
    CollectionField('type', 'Media type', CollectionFieldOwner.identity, _type),
    CollectionField(
      'subtype',
      'Subtype',
      CollectionFieldOwner.identity,
      _subtype,
    ),
    CollectionField(
      'roots',
      'Root folders',
      CollectionFieldOwner.sources,
      _roots,
    ),
    CollectionField(
      'extensions',
      'File types',
      CollectionFieldOwner.sources,
      _strings,
    ),
    CollectionField(
      'view',
      'Default view',
      CollectionFieldOwner.settings,
      _view,
    ),
    CollectionField(
      'player',
      'Default player',
      CollectionFieldOwner.settings,
      _player,
    ),
    CollectionField(
      'openAction',
      'When opening a title',
      CollectionFieldOwner.settings,
      _opening,
    ),
    CollectionField(
      'audioRate',
      'Default playback speed',
      CollectionFieldOwner.settings,
      _rate,
      audioOnly: true,
    ),
    CollectionField(
      'autoplayNext',
      'Autoplay next audiobook',
      CollectionFieldOwner.settings,
      _flag,
      audioOnly: true,
    ),
    CollectionField(
      'locked',
      'Collection lock',
      CollectionFieldOwner.settings,
      _flag,
    ),
    CollectionField(
      'includeInGlobalAudio',
      'Include in global Audiobooks',
      CollectionFieldOwner.settings,
      _flag,
      audioOnly: true,
    ),
    CollectionField(
      'includeInGlobalCinema',
      'Include in global Cinema',
      CollectionFieldOwner.settings,
      _flag,
    ),
    CollectionField(
      'includeInGlobalVideos',
      'Include in global Videos',
      CollectionFieldOwner.settings,
      _flag,
    ),
    CollectionField(
      'allowFolders',
      'Allow folder viewing',
      CollectionFieldOwner.settings,
      _flag,
    ),
    CollectionField('sort', 'Sort', CollectionFieldOwner.settings, _text),
    CollectionField('filter', 'Filter', CollectionFieldOwner.settings, _text),
    CollectionField(
      'cardSize',
      'Card size',
      CollectionFieldOwner.settings,
      _cardSize,
    ),
    CollectionField(
      'scrollOffset',
      'Scroll position',
      CollectionFieldOwner.navigationState,
      _number,
    ),
    CollectionField(
      'folder',
      'Current folder',
      CollectionFieldOwner.navigationState,
      _text,
    ),
    CollectionField(
      'lastScanAt',
      'Last scan',
      CollectionFieldOwner.scanState,
      _number,
    ),
    CollectionField(
      'rootHealth',
      'Folder health',
      CollectionFieldOwner.scanState,
      _health,
    ),
  ];
  static CollectionField field(String id) => fields.firstWhere(
    (f) => f.id == id,
    orElse: () => throw ArgumentError('Unknown collection field: $id'),
  );
  static void validate(
    Map<String, dynamic> values, {
    bool browsingOnly = false,
  }) {
    for (final entry in values.entries) {
      final definition = field(entry.key);
      if (!definition.accepts(entry.value) ||
          browsingOnly &&
              !{
                'view',
                'sort',
                'filter',
                'cardSize',
                'allowFolders',
                'scrollOffset',
                'folder',
              }.contains(entry.key)) {
        throw ArgumentError('Invalid collection setting: ${entry.key}');
      }
    }
  }
}
