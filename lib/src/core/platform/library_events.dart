import 'dart:async';

import 'package:flutter/services.dart';

export '../../features/sources/application/source_ports.dart'
    show ScanProgressEvent;
import '../../features/sources/application/source_ports.dart';

/// Sole owner of library callbacks; consumers subscribe instead of replacing it.
class LibraryEventHub {
  static final _owners = Expando<Map<String, LibraryEventHub>>();
  factory LibraryEventHub(MethodChannel channel) {
    final hubs = _owners[channel.binaryMessenger] ??= {};
    return hubs.putIfAbsent(channel.name, () => LibraryEventHub._(channel));
  }
  LibraryEventHub._(this.channel) {
    _events = StreamController<ScanProgressEvent>.broadcast(
      onListen: () => channel.setMethodCallHandler(_handle),
      onCancel: () => channel.setMethodCallHandler(null),
    );
  }
  final MethodChannel channel;
  late final StreamController<ScanProgressEvent> _events;
  Stream<ScanProgressEvent> get scanProgress => _events.stream;
  Future<void> _handle(MethodCall call) async {
    if (call.method != 'scanProgress') return;
    final event = ScanProgressEvent.decode(call.arguments);
    if (event != null) _events.add(event);
  }
}
