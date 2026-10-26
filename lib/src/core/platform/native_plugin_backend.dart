import 'package:flutter/services.dart';

import '../../features/plugins/application/plugin_platform.dart';

class NativePluginBackend implements PluginBackend {
  NativePluginBackend({
    this.channel = const MethodChannel('multiplexr/plugins'),
  });
  final MethodChannel channel;
  @override
  Future<Object?> command(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async {
    try {
      return await channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      if (method == 'cancel' || method == 'disableAll') return null;
      if (method == 'list') return <Object?>[];
      if (method == 'status') {
        return 'Plugin platform is unavailable on this device.';
      }
      rethrow;
    }
  }

  @override
  void listen(
    Future<String> Function(String, String) call,
    void Function() changed,
  ) {
    channel.setMethodCallHandler((request) async {
      if (request.method == 'changed') {
        changed();
        return null;
      }
      if (request.method != 'hostCall') throw MissingPluginException();
      final value = Map<String, dynamic>.from(request.arguments as Map);
      return call(value['token'] as String, value['request'] as String);
    });
  }
}
