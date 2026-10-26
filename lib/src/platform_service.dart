import 'features/settings/application/host_settings.dart';

import 'package:flutter/services.dart';

import 'features/settings/application/collection_privacy.dart';

import 'package:app_shell/app_shell.dart';
export 'package:app_shell/app_shell.dart'
    show DeviceAuthentication, deviceAuthentication;

/// Multiplexr retains its channel name and native preference/security adapter.
class PlatformService extends MethodChannelShellPlatform
    implements CollectionPrivacy {
  const PlatformService() : super(channelName: 'multiplexr/device');
  static const channel = MethodChannel('multiplexr/device');
  Future<Map<String, String>> buildInfo() async =>
      (await channel.invokeMapMethod<String, String>('buildInfo')) ?? const {};

  @override
  Future<void> collectionPrivacy(bool enabled) =>
      channel.invokeMethod('collectionPrivacy', enabled);
  @override
  Future<void> save(Map<String, dynamic> values) {
    HostSettings.validate('app', values);
    return super.save(values);
  }

  @override
  Future<void> saveSecurity(Map<String, dynamic> values) {
    HostSettings.validate('app', values);
    return super.saveSecurity(values);
  }

  @override
  Future<void> setCategory(String category, bool enabled) {
    HostSettings.validate('notification', {category: enabled});
    return super.setCategory(category, enabled);
  }
}
