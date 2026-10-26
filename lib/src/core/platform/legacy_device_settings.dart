import 'package:app_shell/app_shell.dart' show ShellPlatform;

import '../../features/settings/application/device_settings.dart';

class LegacyDeviceSettings implements DeviceSettingsPort {
  const LegacyDeviceSettings(this.platform);
  final ShellPlatform platform;
  @override
  Future<bool> authenticate() => platform.authenticate();
  @override
  Future<void> setLock(bool enabled) => platform.setLock(enabled);
  @override
  Future<void> saveSecurity(Map<String, Object> values) =>
      platform.saveSecurity(values);
  @override
  Future<bool> requestNotifications() => platform.requestNotifications();
  @override
  Future<void> setNotifications(bool enabled) =>
      platform.setNotifications(enabled);
  @override
  Future<void> setCategory(String id, bool enabled) =>
      platform.setCategory(id, enabled);
  @override
  Future<void> savePreferences(Map<String, Object> values) =>
      platform.save(values);
  @override
  Future<void> openSecuritySettings() => platform.securitySettings();
}
