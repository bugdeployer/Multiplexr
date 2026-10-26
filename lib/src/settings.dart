import 'features/settings/application/device_settings.dart';

import 'package:app_shell/app_shell.dart';

import 'platform_service.dart';

export 'package:app_shell/app_shell.dart'
    show
        Palette,
        darkBases,
        lightBases,
        darkAccents,
        lightAccents,
        loadThemePalettes;

/// Only Multiplexr's home-view preferences remain in its app adapter.
class SettingsController extends ShellSettingsController {
  SettingsController(
    PlatformService super.platform, {
    super.clock,
    required this.deviceSettings,
    required this.visibleSessionCheck,
  }) : _loadBuildInfo = platform.buildInfo;
  final Future<Map<String, String>> Function() _loadBuildInfo;
  Future<Map<String, String>>? _buildInfo;
  Future<Map<String, String>> loadBuildInfo() =>
      _buildInfo ??= _loadBuildInfo();
  final bool Function() visibleSessionCheck;
  final DeviceSettingsCommands deviceSettings;
  void _unlocked() {
    locked = false;
    covered = false;
    backgroundAt = null;
    notifyListeners();
  }

  @override
  Future<bool> unlock() async {
    if (!await deviceSettings.authenticate()) return false;
    _unlocked();
    return true;
  }

  @override
  Future<bool> changeLock(bool enabled) async {
    if (!await deviceSettings.changeLock(enabled)) return false;
    lockEnabled = enabled;
    _unlocked();
    return true;
  }

  @override
  Future<bool> security({
    int? delay,
    bool? biometrics,
    bool? previews,
    bool? screen,
  }) async {
    final values = <String, Object>{
      'lockDelay': delay ?? lockDelay,
      'useBiometrics': biometrics ?? useBiometrics,
      'hidePreviews': previews ?? hidePreviews,
      'protectScreen': screen ?? protectScreen,
    };
    if (!await deviceSettings.security(values, locked: lockEnabled)) {
      return false;
    }
    lockDelay = values['lockDelay'] as int;
    useBiometrics = values['useBiometrics'] as bool;
    hidePreviews = values['hidePreviews'] as bool;
    protectScreen = values['protectScreen'] as bool;
    _unlocked();
    return true;
  }

  @override
  Future<void> category(String id, bool enabled) async {
    await deviceSettings.category(id, enabled);
    categories[id] = enabled;
    notifyListeners();
  }

  @override
  Future<void> changeNotifications(bool enabled) async {
    await deviceSettings.notifications(enabled);
    await refresh();
  }

  @override
  PlatformService get platform => super.platform as PlatformService;
  @override
  bool get visibleSession => visibleSessionCheck();
  int libraryView = 0, spacesView = 0;
  @override
  void readAppPreferences(Map<String, dynamic> data) {
    int index(Object? value) =>
        value is int && value >= 0 && value < 3 ? value : 0;
    libraryView = index(data['libraryView']);
    spacesView = index(data['spacesView']);
  }

  Future<void> setHomeView({required bool spaces, required int value}) async {
    await deviceSettings.homeView(
      spaces: spaces,
      value: value,
      persist: supported,
    );
    if (spaces) {
      spacesView = value;
    } else {
      libraryView = value;
    }
    notifyListeners();
  }
}
