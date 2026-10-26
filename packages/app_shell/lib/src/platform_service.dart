import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A device-credential Activity is part of authentication, not an app departure.
/// Keep the scope open until Android returns focus, even if the result arrives first.
final deviceAuthentication = DeviceAuthentication();

class DeviceAuthentication extends ChangeNotifier with WidgetsBindingObserver {
  bool active = false, succeeded = false;
  Completer<void>? _resumed;
  Future<bool> run(Future<bool> Function() authenticate) async {
    if (active) {
      throw PlatformException(
        code: 'busy',
        message: 'Authentication is already open.',
      );
    }
    active = true;
    succeeded = false;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
    try {
      succeeded = await authenticate();
      return succeeded;
    } finally {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
          WidgetsBinding.instance.lifecycleState != null) {
        _resumed = Completer<void>();
        await _resumed!.future;
      }
      WidgetsBinding.instance.removeObserver(this);
      _resumed = null;
      active = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _resumed?.isCompleted == false) {
      _resumed!.complete();
    }
  }
}

/// Android owns persistence, permissions and authentication. Other hosts report
/// unavailable capabilities explicitly rather than simulating device features.
abstract interface class ShellPlatform {
  Future<Map<String, dynamic>> load();
  Future<void> save(Map<String, dynamic> values);
  Future<String?> readThemeFile();
  Future<bool> writeThemeFile(String text);
  Future<bool> authenticate();
  Future<void> setLock(bool enabled);
  Future<void> saveSecurity(Map<String, dynamic> values);
  Future<void> setNotifications(bool enabled);
  Future<bool> requestNotifications();
  Future<void> notificationSettings();
  Future<void> securitySettings();
  Future<void> testNotification([String category = 'completed']);
  Future<void> setCategory(String category, bool enabled);
  Future<void> postNotification(String category, String title, String body);
}

class MethodChannelShellPlatform implements ShellPlatform {
  const MethodChannelShellPlatform({this.channelName = 'app_shell/device'});
  final String channelName;
  MethodChannel get deviceChannel => MethodChannel(channelName);
  @override
  Future<Map<String, dynamic>> load() async {
    try {
      return Map<String, dynamic>.from(
        await deviceChannel.invokeMapMethod<String, dynamic>('load') ?? {},
      );
    } on MissingPluginException {
      return {'supported': false};
    }
  }

  @override
  Future<void> save(Map<String, dynamic> values) =>
      deviceChannel.invokeMethod('save', values);
  @override
  Future<String?> readThemeFile() =>
      deviceChannel.invokeMethod<String>('readThemeFile');
  @override
  Future<bool> writeThemeFile(String text) async =>
      await deviceChannel.invokeMethod<bool>('writeThemeFile', text) ?? false;
  @override
  Future<bool> authenticate() => deviceAuthentication.run(
    () async => await deviceChannel.invokeMethod<bool>('authenticate') ?? false,
  );
  @override
  Future<void> setLock(bool enabled) =>
      deviceChannel.invokeMethod('setLock', enabled);
  @override
  Future<void> setNotifications(bool enabled) =>
      deviceChannel.invokeMethod('setNotifications', enabled);
  @override
  Future<bool> requestNotifications() async =>
      await deviceChannel.invokeMethod<bool>('requestNotifications') ?? false;
  @override
  Future<void> notificationSettings() =>
      deviceChannel.invokeMethod('notificationSettings');
  @override
  Future<void> securitySettings() =>
      deviceChannel.invokeMethod('securitySettings');
  @override
  Future<void> testNotification([String category = 'completed']) =>
      deviceChannel.invokeMethod('testNotification', category);
  @override
  Future<void> saveSecurity(Map<String, dynamic> values) =>
      deviceChannel.invokeMethod('saveSecurity', values);
  @override
  Future<void> setCategory(String category, bool enabled) => deviceChannel
      .invokeMethod('setCategory', {'category': category, 'enabled': enabled});
  @override
  Future<void> postNotification(String category, String title, String body) =>
      deviceChannel.invokeMethod('postNotification', {
        'category': category,
        'title': title,
        'body': body,
      });
}
