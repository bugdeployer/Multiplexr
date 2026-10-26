import 'host_settings.dart';

abstract interface class DeviceSettingsPort {
  Future<bool> authenticate();
  Future<void> setLock(bool enabled);
  Future<void> saveSecurity(Map<String, Object> values);
  Future<bool> requestNotifications();
  Future<void> setNotifications(bool enabled);
  Future<void> setCategory(String id, bool enabled);
  Future<void> savePreferences(Map<String, Object> values);
  Future<void> openSecuritySettings();
}

class DeviceSettingsCommands {
  const DeviceSettingsCommands(this.port);
  final DeviceSettingsPort port;
  Future<bool> authenticate() => port.authenticate();
  Future<bool> changeLock(bool enabled) async {
    if (!await port.authenticate()) return false;
    await port.setLock(enabled);
    return true;
  }

  Future<bool> security(
    Map<String, Object> values, {
    required bool locked,
  }) async {
    HostSettings.validate('app', values);
    if (locked && !await port.authenticate()) return false;
    await port.saveSecurity(values);
    return true;
  }

  Future<void> notifications(bool enabled) async {
    if (enabled && !await port.requestNotifications()) return;
    await port.setNotifications(enabled);
  }

  Future<void> category(String id, bool enabled) {
    HostSettings.validate('notification', {id: enabled});
    return port.setCategory(id, enabled);
  }

  Future<void> homeView({
    required bool spaces,
    required int value,
    required bool persist,
  }) async {
    if (value < 0 || value > 2) throw ArgumentError('Invalid home view');
    if (persist) {
      await port.savePreferences({
        spaces ? 'spacesView' : 'libraryView': value,
      });
    }
  }

  Future<void> openSecuritySettings() => port.openSecuritySettings();
}
