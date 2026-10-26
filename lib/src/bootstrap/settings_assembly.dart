import '../settings.dart';
import '../platform_service.dart';
import '../core/platform/legacy_device_settings.dart';
import '../features/settings/application/device_settings.dart';
import '../library/native_player.dart' show PlaybackWindow;

SettingsController createSettingsController(
  PlatformService platform, {
  DateTime Function()? clock,
  DeviceSettingsCommands? commands,
  bool Function()? visibleSession,
}) => SettingsController(
  platform,
  clock: clock,
  deviceSettings:
      commands ?? DeviceSettingsCommands(LegacyDeviceSettings(platform)),
  visibleSessionCheck: visibleSession ?? () => PlaybackWindow.instance.active,
);
