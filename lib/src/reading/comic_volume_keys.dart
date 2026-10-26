import '../features/reading/application/reader_keys.dart';
export '../features/reading/application/reader_keys.dart';

import 'package:flutter/services.dart';

class NativeComicVolumeKeys implements ComicVolumeKeys {
  static const channel = MethodChannel('multiplexr/reading-keys');
  static NativeComicVolumeKeys? _owner;
  @override
  Future<void> configure(bool enabled, void Function(bool) turn) async {
    _owner = this;
    channel.setMethodCallHandler((call) async {
      if (identical(_owner, this) && call.method == 'turn' && enabled) {
        turn(call.arguments == true);
      }
    });
    try {
      await channel.invokeMethod<void>('enabled', enabled);
    } on MissingPluginException {
      /* Hardware keyboard navigation remains available. */
    }
  }

  @override
  Future<void> close() async {
    if (!identical(_owner, this)) return;
    _owner = null;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('enabled', false);
    } on MissingPluginException {
      /* No native key host on this platform. */
    }
  }
}
