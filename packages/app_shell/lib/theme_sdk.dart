/// Theme authoring API backed by the host runtime compiler.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'src/theme_definition.dart';

export 'src/theme_definition.dart'
    show AppThemeDefinition, ThemeTokens, ThemeAsset, AppIconRole;

abstract final class ThemePackageAuthor {
  /// Validate a new data-only format-2 package and its decoded assets.
  static Future<AppThemeDefinition> validate(String source) async {
    final theme = AppThemeDefinition.parse(source);
    // Authoring catches misspelled/unsupported fields instead of dropping them
    // during canonical encoding. Hosts may still import older package shapes.
    const fields = {
      'format',
      'version',
      'id',
      'name',
      'style',
      'font',
      'dark',
      'light',
      'tokens',
      'assets',
    };
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('Unsupported theme author field.');
    }
    if (theme.v2 == null) {
      throw const FormatException('Author packages must use theme format 2.');
    }
    await theme.tokens.prepare();
    return theme;
  }

  /// Canonical portable JSON, with no app installation or preference writes.
  static Future<String> build(Map<String, dynamic> definition) async =>
      (await validate(jsonEncode(definition))).encode();

  /// Embed a validated, attributed font/icon; relative asset paths are required.
  static Map<String, dynamic> asset({
    required String path,
    required String mime,
    required Uint8List bytes,
    required String author,
    required String license,
    String licenseText = '',
  }) => ThemeAsset.parse({
    'path': path,
    'mime': mime,
    'data': base64Encode(bytes),
    'sha256': sha256.convert(bytes).toString(),
    'author': author,
    'license': license,
    'licenseText': licenseText,
  }).toJson();
}
