import 'persistence/mutation_coordinator.dart';
import 'theme/theme_compiler.dart';
import 'theme_palettes.dart';
export 'theme_palettes.dart';

import 'dart:convert';

import 'theme_definition.dart';

import 'package:flutter/material.dart';

import 'platform_service.dart';

class ShellSettingsController extends ChangeNotifier {
  ShellSettingsController(
    this.platform, {
    DateTime Function()? clock,
    Iterable<String> notificationCategoryIds = const [
      'completed',
      'errors',
      'activity',
    ],
  }) : clock = clock ?? DateTime.now {
    final ids = notificationCategoryIds.toList();
    if (ids.isEmpty ||
        ids.toSet().length != ids.length ||
        ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError(
        'Notification categories must be unique and nonempty.',
      );
    }
    categories.addEntries(ids.map((id) => MapEntry(id, true)));
    channelAllowed.addEntries(ids.map((id) => MapEntry(id, true)));
    deviceAuthentication.addListener(_authenticationChanged);
  }
  final DateTime Function() clock;
  final ShellPlatform platform;
  bool ready = false, supported = false, dark = true;
  bool locked = false, lockEnabled = false, notifications = false;
  bool notificationAllowed = false, secureDevice = false, biometric = false;
  int darkBase = 1, darkAccent = 1, lightBase = 0, lightAccent = 7;
  bool pixel = true;
  final Map<String, AppThemeDefinition> themes = {};
  AppThemeDefinition? selectedTheme;
  int themeOverrides =
      15; // Legacy palette choices until theme data has loaded.
  String? themeWarning;
  bool get pixelFont => selectedTheme?.pixelFont ?? pixel;
  Color _themeColor(bool night, bool accentColor) {
    final bit = night ? (accentColor ? 2 : 1) : (accentColor ? 8 : 4);
    if (selectedTheme != null && themeOverrides & bit == 0) {
      return night
          ? (accentColor
                ? selectedTheme!.darkAccent
                : selectedTheme!.darkBackground)
          : (accentColor
                ? selectedTheme!.lightAccent
                : selectedTheme!.lightBackground);
    }
    return night
        ? (accentColor
              ? darkAccents[darkAccent].color
              : darkBases[darkBase].color)
        : (accentColor
              ? lightAccents[lightAccent].color
              : lightBases[lightBase].color);
  }

  String _themeState({
    String? selected,
    int? overrides,
    Map<String, AppThemeDefinition>? definitions,
  }) {
    final encoded = jsonEncode({
      'selected': selected ?? selectedTheme?.id ?? (pixel ? 'retro' : 'modern'),
      'overrides': overrides ?? themeOverrides,
      'custom': (definitions ?? themes).values
          .where((t) => !{'retro', 'modern', 'minimal'}.contains(t.id))
          .map((t) => t.toJson())
          .toList(),
    });
    if (utf8.encode(encoded).length > 16777216) {
      throw const FormatException(
        'Installed themes exceed 16 MB. Remove a theme first.',
      );
    }
    return encoded;
  }

  Future<void> _appearanceMutation(Future<void> Function() change) =>
      MutationCoordinator.forOwner(this).run('appearance', change);

  Future<void> selectTheme(String id) =>
      _appearanceMutation(() => _selectTheme(id));
  Future<void> _selectTheme(String id) async {
    final next = themes[id];
    if (next == null) throw const FormatException('Theme not found.');
    final bundledStyleSwitch =
        {'retro', 'modern', 'minimal'}.contains(selectedTheme?.id) &&
        {'retro', 'modern', 'minimal'}.contains(id);
    final overrides = bundledStyleSwitch ? themeOverrides : 0;
    await next.tokens.prepare();
    if (supported) {
      await platform.save({
        'themeState': _themeState(selected: id, overrides: overrides),
        'pixel': next.retro,
      });
    }
    selectedTheme = next;
    themeOverrides = overrides;
    pixel = next.retro;
    notifyListeners();
  }

  Future<void> importTheme(String text) =>
      _appearanceMutation(() => _importTheme(text));
  Future<void> _importTheme(String text) async {
    final next = AppThemeDefinition.parse(text);
    if ({'retro', 'modern', 'minimal'}.contains(next.id)) {
      throw const FormatException(
        'Choose a custom ID; bundled themes cannot be replaced.',
      );
    }
    final updated = {...themes, next.id: next};
    if (updated.keys
            .where((id) => !{'retro', 'modern', 'minimal'}.contains(id))
            .length >
        16) {
      throw const FormatException(
        'Remove a custom theme before adding another.',
      );
    }
    final state = _themeState(
      selected: next.id,
      overrides: 0,
      definitions: updated,
    );
    await next.tokens.prepare();
    if (supported) {
      await platform.save({'themeState': state, 'pixel': next.retro});
    }
    themes.addAll(updated);
    selectedTheme = next;
    pixel = next.retro;
    themeOverrides = 0;
    notifyListeners();
  }

  Future<void> removeTheme(String id) =>
      _appearanceMutation(() => _removeTheme(id));
  Future<void> _removeTheme(String id) async {
    if ({'retro', 'modern', 'minimal'}.contains(id)) return;
    final updated = {...themes}..remove(id);
    final next = selectedTheme?.id == id ? themes['retro']! : selectedTheme!;
    final overrides = selectedTheme?.id == id ? 0 : themeOverrides;
    if (supported) {
      await platform.save({
        'themeState': _themeState(
          selected: next.id,
          overrides: overrides,
          definitions: updated,
        ),
        'pixel': next.retro,
      });
    }
    themes.remove(id);
    selectedTheme = next;
    pixel = next.retro;
    themeOverrides = overrides;
    notifyListeners();
  }

  String exportTheme() => AppThemeDefinition(
    id: 'custom-${selectedTheme?.id ?? 'retro'}'.substring(
      0,
      ('custom-${selectedTheme?.id ?? 'retro'}').length.clamp(0, 48),
    ),
    name: '${selectedTheme?.name ?? 'Retro'} copy'.substring(
      0,
      ('${selectedTheme?.name ?? 'Retro'} copy').length.clamp(0, 48),
    ),
    retro: pixel,
    pixelFont: pixelFont,
    v2: selectedTheme?.v2,
    darkBackground: _themeColor(true, false),
    darkAccent: _themeColor(true, true),
    lightBackground: _themeColor(false, false),
    lightAccent: _themeColor(false, true),
  ).encode();

  String exportThemeV2() {
    final data = AppThemeDefinition.parse(exportTheme());
    return jsonEncode({
      ...data.toJson(),
      'version': 2,
      'tokens': data.tokens.toJson(),
      'assets': data.tokens.assets.values.map((a) => a.toJson()).toList(),
    });
  }

  ThemeData previewTheme(AppThemeDefinition definition, {required bool night}) {
    final preview = ShellSettingsController(platform)
      ..selectedTheme = definition
      ..pixel = definition.retro
      ..themeOverrides = 0
      ..dark = night
      ..reduceMotion = reduceMotion;
    try {
      return preview.theme;
    } finally {
      preview.dispose();
    }
  }

  Future<void> resetThemePalette() => _appearanceMutation(_resetThemePalette);
  Future<void> _resetThemePalette() async {
    if (supported) {
      await platform.save({'themeState': _themeState(overrides: 0)});
    }
    themeOverrides = 0;
    notifyListeners();
  }

  Future<void> interfaceStyle(bool value) =>
      _appearanceMutation(() => _interfaceStyle(value));
  Future<void> _interfaceStyle(bool value) async {
    final next = themes[value ? 'retro' : 'modern'];
    if (supported) {
      await platform.save({
        'pixel': value,
        if (next != null) 'themeState': _themeState(selected: next.id),
      });
    }
    selectedTheme = next;
    pixel = value;
    notifyListeners();
  }

  String? error;
  bool followSystem = false,
      systemDark = true,
      compact = false,
      reduceMotion = false;
  bool covered = false,
      useBiometrics = true,
      hidePreviews = true,
      protectScreen = true;
  int lockDelay = 0;
  DateTime? backgroundAt;
  DateTime? _authenticationBackgroundAt;
  void _authenticationChanged() {
    if (deviceAuthentication.active || _authenticationBackgroundAt == null) {
      return;
    }
    if (deviceAuthentication.succeeded) {
      locked = false;
      backgroundAt = null;
    } else if (lockEnabled &&
        (clock().difference(_authenticationBackgroundAt!).isNegative ||
            clock().difference(_authenticationBackgroundAt!).inSeconds >=
                lockDelay)) {
      locked = true;
    }
    _authenticationBackgroundAt = null;
    covered = false;
    notifyListeners();
  }

  @override
  void dispose() {
    deviceAuthentication.removeListener(_authenticationChanged);
    super.dispose();
  }

  /// Host-declared visible session (for example Android PiP), never authorization.
  /// Existing locks are not cleared by this signal.
  bool get visibleSession => false;

  void obscure() {
    if (visibleSession && !locked) return;
    if (lockEnabled && !covered) {
      covered = true;
      notifyListeners();
    }
  }

  final Map<String, bool> categories = {};
  final Map<String, bool> channelAllowed = {};

  void systemBrightness(Brightness value) {
    systemDark = value == Brightness.dark;
    if (followSystem) {
      dark = systemDark;
      notifyListeners();
    }
  }

  void background() {
    if (!lockEnabled || (visibleSession && !locked)) return;
    if (deviceAuthentication.active) {
      _authenticationBackgroundAt ??= clock();
      obscure();
      return;
    }
    backgroundAt ??= clock();
    covered = true;
    if (lockDelay == 0) locked = true;
    notifyListeners();
  }

  void foreground() {
    if (lockEnabled &&
        backgroundAt != null &&
        (clock().difference(backgroundAt!).isNegative ||
            clock().difference(backgroundAt!).inSeconds >= lockDelay)) {
      locked = true;
    }
    covered = false;
    backgroundAt = null;
    notifyListeners();
  }

  Future<void> preferences({bool? system, bool? dense, bool? motion}) =>
      _appearanceMutation(
        () => _preferences(system: system, dense: dense, motion: motion),
      );
  Future<void> _preferences({bool? system, bool? dense, bool? motion}) async {
    final values = {
      'dark': (system ?? followSystem) ? systemDark : dark,
      'followSystem': system ?? followSystem,
      'compact': dense ?? compact,
      'reduceMotion': motion ?? reduceMotion,
    };
    if (supported) await platform.save(values);
    followSystem = values['followSystem']!;
    compact = values['compact']!;
    reduceMotion = values['reduceMotion']!;
    dark = followSystem ? systemDark : values['dark']!;
    notifyListeners();
  }

  Future<bool> security({
    int? delay,
    bool? biometrics,
    bool? previews,
    bool? screen,
  }) async {
    if (lockEnabled && !await platform.authenticate()) return false;
    final values = {
      'lockDelay': delay ?? lockDelay,
      'useBiometrics': biometrics ?? useBiometrics,
      'hidePreviews': previews ?? hidePreviews,
      'protectScreen': screen ?? protectScreen,
    };
    await platform.saveSecurity(values);
    lockDelay = values['lockDelay'] as int;
    useBiometrics = values['useBiometrics'] as bool;
    hidePreviews = values['hidePreviews'] as bool;
    protectScreen = values['protectScreen'] as bool;
    locked = false;
    covered = false;
    backgroundAt = null;
    notifyListeners();
    return true;
  }

  Future<void> category(String id, bool enabled) async {
    await platform.setCategory(id, enabled);
    categories[id] = enabled;
    notifyListeners();
  }

  List<Palette> get bases => dark ? darkBases : lightBases;
  List<Palette> get accents => dark ? darkAccents : lightAccents;
  int get baseIndex => dark ? darkBase : lightBase;
  int get accentIndex => dark ? darkAccent : lightAccent;
  Color get base => _themeColor(dark, false);
  Color get accent => _themeColor(dark, true);

  ThemeData get theme {
    final tokens =
        selectedTheme?.v2?.tokens ??
        ThemeTokens.parse({}, retro: pixel, pixelFont: pixelFont);
    return ThemeCompiler.compile(
      ThemeCompiler.defaults(
        tokens: tokens,
        base: base,
        accent: accent,
        dark: dark,
        reduceMotion: reduceMotion,
        compact: compact,
      ),
      tokens,
      compact: compact,
      custom:
          selectedTheme?.v2 != null &&
          !tokens.legacyEquivalent(retro: pixel, pixelFont: pixelFont),
      reduceMotion: reduceMotion,
    );
  }

  int _index(dynamic value, int length, int fallback) =>
      value is int && value >= 0 && value < length ? value : fallback;

  /// App adapters may read their own keys without coupling the shell to features.
  void readAppPreferences(Map<String, dynamic> data) {}

  Future<void> load() async {
    try {
      themes.addAll(
        AppThemeDefinition.bundled ?? await AppThemeDefinition.loadBundled(),
      );
      final data = await platform.load();
      supported = data['supported'] == true;
      followSystem = data['followSystem'] == true;
      dark = followSystem ? systemDark : data['dark'] != false;
      compact = data['compact'] == true;
      pixel = data['pixel'] != false;
      selectedTheme = themes[pixel ? 'retro' : 'modern'];
      themeOverrides =
          data['hasPalettePreferences'] == true ||
              (!data.containsKey('hasPalettePreferences') &&
                  [
                    'darkBase',
                    'darkAccent',
                    'lightBase',
                    'lightAccent',
                  ].any(data.containsKey))
          ? 15
          : 0;
      if (data['themeState'] is String &&
          (data['themeState'] as String).isNotEmpty) {
        try {
          final text = data['themeState'] as String;
          if (utf8.encode(text).length > 16777216) {
            throw const FormatException();
          }
          final state = jsonDecode(text) as Map<String, dynamic>;
          final custom = state['custom'] as List;
          if (custom.length > 16) throw const FormatException();
          final parsed = <String, AppThemeDefinition>{};
          for (final item in custom) {
            final definition = AppThemeDefinition.parse(jsonEncode(item));
            if (['retro', 'modern', 'minimal'].contains(definition.id) ||
                parsed.containsKey(definition.id)) {
              throw const FormatException();
            }
            await definition.tokens.prepare();
            parsed[definition.id] = definition;
          }
          if (state['overrides'] is! int ||
              (state['overrides'] as int) < 0 ||
              (state['overrides'] as int) > 15) {
            throw const FormatException();
          }
          themes.addAll(parsed);
          selectedTheme = themes[state['selected']] ?? selectedTheme;
          themeOverrides = state['overrides'] as int;
          pixel = selectedTheme!.retro;
        } catch (_) {
          themeWarning =
              'Saved theme could not be loaded. A bundled theme is active.';
        }
      }
      readAppPreferences(data);
      reduceMotion = data['reduceMotion'] == true;
      lockDelay = [0, 30, 60, 300].contains(data['lockDelay'])
          ? data['lockDelay'] as int
          : 0;
      useBiometrics = data['useBiometrics'] != false;
      hidePreviews = data['hidePreviews'] != false;
      protectScreen = data['protectScreen'] != false;
      darkBase = _index(data['darkBase'], darkBases.length, 1);
      darkAccent = _index(data['darkAccent'], darkAccents.length, 1);
      lightBase = _index(data['lightBase'], lightBases.length, 0);
      lightAccent = _index(data['lightAccent'], lightAccents.length, 7);
      lockEnabled = data['lockEnabled'] == true;
      locked = lockEnabled;
      _status(data);
    } catch (_) {
      error = 'Settings could not be loaded. Restart the app to try again.';
      locked = true; // Unknown lock state must fail closed.
    }
    ready = true;
    notifyListeners();
  }

  void _status(Map<String, dynamic> data) {
    notifications = data['notifications'] == true;
    notificationAllowed = data['notificationAllowed'] == true;
    secureDevice = data['secureDevice'] == true;
    biometric = data['biometric'] == true;
    for (final id in categories.keys) {
      categories[id] = data['category_$id'] != false;
      channelAllowed[id] = data['channel_$id'] != false;
    }
  }

  Future<void> refresh() async {
    if (!supported) return;
    _status(await platform.load());
    notifyListeners();
  }

  Future<void> appearance({bool? isDark, int? baseChoice, int? accentChoice}) =>
      _appearanceMutation(
        () => _appearance(
          isDark: isDark,
          baseChoice: baseChoice,
          accentChoice: accentChoice,
        ),
      );

  Future<void> _appearance({
    bool? isDark,
    int? baseChoice,
    int? accentChoice,
  }) async {
    final previous = (
      dark,
      darkBase,
      darkAccent,
      lightBase,
      lightAccent,
      followSystem,
      themeOverrides,
    );
    if (isDark != null) {
      dark = isDark;
      followSystem = false;
    }
    if (baseChoice != null) {
      themeOverrides |= dark ? 1 : 4;
      if (dark) {
        darkBase = baseChoice;
      } else {
        lightBase = baseChoice;
      }
    }
    if (accentChoice != null) {
      themeOverrides |= dark ? 2 : 8;
      if (dark) {
        darkAccent = accentChoice;
      } else {
        lightAccent = accentChoice;
      }
    }
    notifyListeners();
    try {
      if (AppThemeDefinition.contrast(base, accent) < 4.5 ||
          AppThemeDefinition.contrast(theme.colorScheme.surface, accent) <
              4.5) {
        throw const FormatException(
          'Choose background and accent colors with at least 4.5:1 contrast.',
        );
      }
      if (supported) {
        await platform.save({
          'themeState': _themeState(),
          'dark': dark,
          'followSystem': followSystem,
          'darkBase': darkBase,
          'darkAccent': darkAccent,
          'lightBase': lightBase,
          'lightAccent': lightAccent,
        });
      }
    } catch (_) {
      followSystem = previous.$6;
      themeOverrides = previous.$7;
      dark = followSystem ? systemDark : previous.$1;
      darkBase = previous.$2;
      darkAccent = previous.$3;
      lightBase = previous.$4;
      lightAccent = previous.$5;
      notifyListeners();
      rethrow;
    }
  }

  void conceal() {
    if (lockEnabled) {
      locked = true;
      notifyListeners();
    }
  }

  Future<bool> unlock() async {
    if (await platform.authenticate()) {
      locked = false;
      covered = false;
      backgroundAt = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> changeLock(bool enabled) async {
    if (!await platform.authenticate()) return false;
    await platform.setLock(enabled);
    lockEnabled = enabled;
    locked = false;
    covered = false;
    backgroundAt = null;
    notifyListeners();
    return true;
  }

  Future<void> changeNotifications(bool enabled) async {
    if (enabled && !await platform.requestNotifications()) {
      await refresh();
      return;
    }
    await platform.setNotifications(enabled);
    await refresh();
  }
}
