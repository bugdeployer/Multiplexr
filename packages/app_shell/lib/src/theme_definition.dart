import 'theme/theme_tokens.dart';
export 'theme/theme_tokens.dart' show ThemeTokens, ThemeAsset, AppIconRole;

import 'dart:convert';

import 'theme_palettes.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Portable data only: themes cannot load code, remote assets or arbitrary fonts.
class AppThemeDefinition {
  static Map<String, AppThemeDefinition>? bundled;
  static Future<Map<String, AppThemeDefinition>>? _bundled;
  static Future<Map<String, AppThemeDefinition>> loadBundled() =>
      _bundled ??= () async {
        await loadThemePalettes();
        final font = FontLoader('Silkscreen')
          ..addFont(
            rootBundle.load(
              'packages/app_shell/assets/fonts/Silkscreen-Regular.ttf',
            ),
          );
        await font.load();
        final result = <String, AppThemeDefinition>{};
        for (final id in ['retro', 'modern', 'minimal']) {
          result[id] = parse(
            await rootBundle.loadString(
              'packages/app_shell/assets/themes/$id.json',
            ),
          );
        }
        for (final theme in result.values) {
          await theme.tokens.prepare();
        }
        bundled = Map.unmodifiable(result);
        return bundled!;
      }();
  const AppThemeDefinition({
    required this.id,
    required this.name,
    required this.retro,
    required this.pixelFont,
    required this.darkBackground,
    required this.darkAccent,
    required this.lightBackground,
    required this.lightAccent,
    this.v2,
  });
  final ThemeDefinitionV2? v2;
  ThemeTokens get tokens =>
      v2?.tokens ?? ThemeTokens.parse({}, retro: retro, pixelFont: pixelFont);
  final String id, name;
  final bool retro, pixelFont;
  final Color darkBackground, darkAccent, lightBackground, lightAccent;

  static AppThemeDefinition parse(String text) {
    if (utf8.encode(text).length > 4194304) {
      throw const FormatException('Theme exceeds 4 MB.');
    }
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final code in text.codeUnits) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (code == 92) {
          escaped = true;
        } else if (code == 34) {
          quoted = false;
        }
      } else if (code == 34) {
        quoted = true;
      } else if (code == 123 || code == 91) {
        if (++depth > 12) {
          throw const FormatException('Theme nesting exceeds 12 levels.');
        }
      } else if (code == 125 || code == 93) {
        depth--;
      }
    }
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> ||
        json['format'] != 'multiplexr-theme' ||
        ![1, 2].contains(json['version'])) {
      throw const FormatException('Unsupported theme format or version.');
    }
    if (json['version'] == 1 && utf8.encode(text).length > 16384) {
      throw const FormatException('Theme exceeds 16 KB.');
    }
    final id = json['id'], name = json['name'];
    if (id is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 48 ||
        name.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Use a short name and a lowercase theme ID.');
    }
    if (!['retro', 'modern'].contains(json['style']) ||
        !['pixel', 'system'].contains(json['font'])) {
      throw const FormatException(
        'Style must be retro or modern; font must be pixel or system.',
      );
    }
    Color color(dynamic mode, String key) {
      final value = mode is Map ? mode[key] : null;
      if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        throw FormatException('$key must be an opaque #RRGGBB color.');
      }
      return Color(0xff000000 | int.parse(value.substring(1), radix: 16));
    }

    final db = color(json['dark'], 'background'),
        da = color(json['dark'], 'accent');
    final lb = color(json['light'], 'background'),
        la = color(json['light'], 'accent');
    for (final pair in [(db, da), (lb, la)]) {
      if (contrast(pair.$1, pair.$2) < 4.5) {
        throw const FormatException(
          'Accent and background need at least 4.5:1 contrast in both modes.',
        );
      }
    }
    return AppThemeDefinition(
      id: id,
      name: name.trim(),
      retro: json['style'] == 'retro',
      pixelFont: json['font'] == 'pixel',
      darkBackground: db,
      darkAccent: da,
      lightBackground: lb,
      lightAccent: la,
      v2: json['version'] == 2
          ? ThemeDefinitionV2.parse(
              json,
              retro: json['style'] == 'retro',
              pixelFont: json['font'] == 'pixel',
            )
          : null,
    );
  }

  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  static Color ink(Color background) =>
      contrast(background, Colors.white) >= contrast(background, Colors.black)
      ? Colors.white
      : Colors.black;
  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  Map<String, dynamic> toJson() => {
    'format': 'multiplexr-theme',
    'version': v2 == null ? 1 : 2,
    if (v2 != null) ...v2!.toJson(),
    'id': id,
    'name': name,
    'style': retro ? 'retro' : 'modern',
    'font': pixelFont ? 'pixel' : 'system',
    'dark': {'background': hex(darkBackground), 'accent': hex(darkAccent)},
    'light': {'background': hex(lightBackground), 'accent': hex(lightAccent)},
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// Single JSON package: manifest and tokens plus bounded, checksummed assets.
class ThemeDefinitionV2 {
  const ThemeDefinitionV2(this.tokens);
  final ThemeTokens tokens;
  static ThemeDefinitionV2 parse(
    Map<String, dynamic> data, {
    required bool retro,
    required bool pixelFont,
  }) {
    final raw = data['assets'] ?? [];
    if (raw is! List || raw.length > 64) {
      throw const FormatException('At most 64 theme assets.');
    }
    final assets = <String, ThemeAsset>{};
    var bytes = 0;
    var fonts = 0;
    for (final item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid theme asset.');
      }
      final asset = ThemeAsset.parse(item);
      bytes += asset.bytes.length;
      if (asset.mime.startsWith('font/')) fonts++;
      if (assets.containsKey(asset.path) || bytes > 3145728 || fonts > 2) {
        throw const FormatException(
          'Duplicate assets or package limit exceeded.',
        );
      }
      assets[asset.path] = asset;
    }
    final tokens = data['tokens'];
    if (tokens is! Map<String, dynamic>) {
      throw const FormatException('V2 requires theme tokens.');
    }
    return ThemeDefinitionV2(
      ThemeTokens.parse(
        tokens,
        retro: retro,
        pixelFont: pixelFont,
        assets: assets,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'tokens': tokens.toJson(),
    'assets': tokens.assets.values.map((a) => a.toJson()).toList(),
  };
}
