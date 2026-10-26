import 'dart:convert';

import 'user_preferences.dart';

class SpaceDisplay {
  bool artwork = true, counts = true, confirmExit = true;
  String source = 'recent';
  bool hideWatched = false;
  int startTab = 0;
  List<String> pins = [];
  Map<String, dynamic> toJson() => {
    'artwork': artwork,
    'counts': counts,
    'confirmExit': confirmExit,
    'source': source,
    'hideWatched': hideWatched,
    'startTab': startTab,
    'pins': List<String>.of(pins),
  };
  void restore(Map<String, dynamic> value) {
    hideWatched = value['hideWatched'] == true;
    final tab = value['startTab'];
    startTab = tab is int ? tab.clamp(0, 2) : 0;
    final savedPins = value['pins'];
    pins = savedPins is List
        ? savedPins
              .whereType<String>()
              .where((pin) => pin.trim().isNotEmpty)
              .toSet()
              .take(3)
              .toList()
        : [];
    artwork = value['artwork'] != false;
    counts = value['counts'] != false;
    confirmExit = value['confirmExit'] != false;
    source =
        ['recent', 'favorites', 'progress', 'pinned'].contains(value['source'])
        ? value['source'] as String
        : 'recent';
  }
}

class SpacePreferences {
  final Map<String, String> _loaded = {};
  Map<String, SpaceDisplay> get _spaces => {
    'cinema': cinema,
    'videos': videos,
    'audiobooks': audiobooks,
    'music': music,
    'ebook': ebook,
    'comics': comics,
  };
  final cinema = SpaceDisplay(),
      videos = SpaceDisplay(),
      audiobooks = SpaceDisplay(),
      music = SpaceDisplay(),
      ebook = SpaceDisplay(),
      comics = SpaceDisplay();
  SpaceDisplay forSpace(bool video) => video ? videos : cinema;
  Future<void> load(UserPreferences preferences) async {
    try {
      final data = await preferences.spaces();
      if (data?['cinema'] is Map) {
        cinema.restore(Map<String, dynamic>.from(data!['cinema']));
      }
      if (data?['audiobooks'] is Map) {
        audiobooks.restore(Map<String, dynamic>.from(data!['audiobooks']));
      }
      if (data?['music'] is Map) {
        music.restore(Map<String, dynamic>.from(data!['music']));
      }
      if (data?['videos'] is Map) {
        videos.restore(Map<String, dynamic>.from(data!['videos']));
      }
      for (final name in ['ebook', 'comics']) {
        if (data?[name] is Map) {
          _spaces[name]!.restore(Map<String, dynamic>.from(data![name]));
        }
      }
      for (final entry in _spaces.entries) {
        _loaded[entry.key] = jsonEncode(entry.value.toJson());
      }
    } catch (_) {
      /* Defaults remain usable when settings cannot be loaded. */
    }
  }

  Future<void> save(UserPreferences preferences) {
    final changed = <String, dynamic>{
      for (final entry in _spaces.entries)
        if (_loaded[entry.key] != jsonEncode(entry.value.toJson()))
          entry.key: entry.value.toJson(),
    };
    if (changed.isEmpty) return Future<void>.value();
    final task = preferences.mergeSpaces(changed).then((_) {
      for (final entry in changed.entries) {
        _loaded[entry.key] = jsonEncode(entry.value);
      }
    });
    return task;
  }
}
