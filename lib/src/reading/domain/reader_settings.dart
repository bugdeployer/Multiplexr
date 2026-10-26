import 'reading_format.dart';
import '../../catalog/domain/classification.dart';
import '../../settings/domain/media_settings.dart';

/// Wire values stay primitive so the existing inheritance resolver owns policy.
abstract final class ReaderSettings {
  static const _scopes = {
    SettingsScope.app,
    SettingsScope.collection,
    SettingsScope.group,
    SettingsScope.title,
  };
  static final fontSize = SettingDefinition(
    'fontSize',
    18.0,
    _scopes,
    (v) => v is num && v.isFinite && v >= 8 && v <= 72,
  );
  static final lineHeight = SettingDefinition(
    'lineHeight',
    1.5,
    _scopes,
    (v) => v is num && v.isFinite && v >= 1 && v <= 3,
  );
  static final margin = SettingDefinition(
    'margin',
    16.0,
    _scopes,
    (v) => v is num && v.isFinite && v >= 0 && v <= 96,
  );
  static final textMode = SettingDefinition(
    'textMode',
    'paged',
    _scopes,
    (v) => {'paged', 'scroll'}.contains(v),
  );
  static final fontWeight = SettingDefinition(
    'fontWeight',
    400,
    _scopes,
    (v) => v is int && v >= 100 && v <= 900 && v % 100 == 0,
  );
  static final paragraphSpacing = SettingDefinition(
    'paragraphSpacing',
    8.0,
    _scopes,
    (v) => v is num && v.isFinite && v >= 0 && v <= 64,
  );
  static final alignment = SettingDefinition(
    'alignment',
    'start',
    _scopes,
    (v) => {'start', 'justify', 'center'}.contains(v),
  );
  static final foreground = SettingDefinition(
    'readerForeground',
    0xff202020,
    _scopes,
    (v) => v is int && v >= 0xff000000 && v <= 0xffffffff,
  );
  static final background = SettingDefinition(
    'readerBackground',
    0xfffff9e9,
    _scopes,
    (v) => v is int && v >= 0xff000000 && v <= 0xffffffff,
  );
  static final comicMode = SettingDefinition(
    'comicMode',
    'paged',
    _scopes,
    (v) => {'paged', 'webtoon'}.contains(v),
  );
  static final direction = SettingDefinition(
    'direction',
    'ltr',
    _scopes,
    (v) => {'ltr', 'rtl'}.contains(v),
  );
  static final fit = SettingDefinition(
    'fit',
    'page',
    _scopes,
    (v) => {'page', 'width'}.contains(v),
  );
  static final cropBorders = SettingDefinition(
    'cropBorders',
    false,
    _scopes,
    (v) => v is bool,
  );
  static final volumeKeys = SettingDefinition(
    'volumeKeys',
    false,
    _scopes,
    (v) => v is bool,
  );
  static final tapZones = SettingDefinition(
    'tapZones',
    'standard',
    _scopes,
    (v) => {'standard', 'inverted', 'off'}.contains(v),
  );
  static final spreads = SettingDefinition(
    'spreads',
    'single',
    _scopes,
    (v) => {'single', 'landscape'}.contains(v),
  );
  static final palette = SettingDefinition(
    'palette',
    'system',
    _scopes,
    (v) => {'system', 'day', 'sepia', 'dark', 'custom'}.contains(v),
  );
  // References to host-validated font assets, never paths or embedded font data.
  static final fontAsset = SettingDefinition(
    'fontAsset',
    'system',
    _scopes,
    (v) => v is String && RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(v),
  );

  static String readerKey(ReadingFormat format) => 'reader_${format.name}';
  static bool validReader(Object? value) =>
      value is String &&
      (value == 'internal' ||
          value == 'ask' ||
          RegExp(r'^app:[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+$').hasMatch(value));
  static final readerChoices = [
    for (final format in ['epub', 'txt', 'pdf'])
      SettingDefinition('reader_$format', 'internal', _scopes, validReader),
  ];

  static List<SettingDefinition<Object>> definitions(MediaSubtype subtype) =>
      switch (subtype) {
        MediaSubtype.ebook => [
          ...readerChoices,
          SettingDefinition(
            'pdfMode',
            'paged',
            _scopes,
            (v) => {'paged', 'scroll'}.contains(v),
          ),
          SettingDefinition(
            'pdfFit',
            'page',
            _scopes,
            (v) => {'page', 'width'}.contains(v),
          ),
          fontSize,
          lineHeight,
          margin,
          textMode,
          fontAsset,
          fontWeight,
          paragraphSpacing,
          alignment,
          foreground,
          background,
          palette,
        ],
        MediaSubtype.comics => [
          comicMode,
          direction,
          fit,
          palette,
          cropBorders,
          volumeKeys,
          tapZones,
          spreads,
          foreground,
          background,
        ],
        _ => throw ArgumentError('Not a reading subtype'),
      };

  static Map<String, Object> validate(
    MediaSubtype subtype,
    Map<String, dynamic> values,
  ) {
    final schema = {for (final d in definitions(subtype)) d.id: d};
    return Map.unmodifiable({
      for (final entry in values.entries)
        entry.key: _value(schema[entry.key], entry.value),
    });
  }

  static Object _value(SettingDefinition<Object>? definition, Object? value) {
    if (definition == null || value == null || !definition.accepts(value)) {
      throw FormatException('Invalid reader preference');
    }
    // Numeric definitions resolve to double, including integer JSON inputs.
    return definition.defaultValue is double
        ? (value as num).toDouble()
        : value;
  }
}
