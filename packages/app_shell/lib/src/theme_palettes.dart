import 'dart:convert';

import 'package:flutter/services.dart';

typedef Palette = ({String name, Color color});
late final List<Palette> darkBases, lightBases, darkAccents, lightAccents;
bool _loaded = false;

/// Ordering is stable because earlier app versions persisted palette indexes.
Future<void> loadThemePalettes() async {
  if (_loaded) return;
  final data = jsonDecode(
    await rootBundle.loadString(
      'packages/app_shell/assets/themes/palettes.json',
    ),
  ) as Map<String, dynamic>;
  List<Palette> read(String key) => List.unmodifiable(
    (data[key] as List).map((item) {
      final color = item['color'] as String;
      if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)) {
        throw const FormatException('Invalid bundled palette.');
      }
      return (
        name: item['name'] as String,
        color: Color(0xff000000 | int.parse(color.substring(1), radix: 16)),
      );
    }),
  );
  darkBases = read('darkBases');
  lightBases = read('lightBases');
  darkAccents = read('darkAccents');
  lightAccents = read('lightAccents');
  _loaded = true;
}
