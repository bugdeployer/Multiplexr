import 'package:flutter/services.dart';

import '../core/platform/platform_transport.dart';
import '../core/platform/maintenance_transport.dart';
import '../core/platform/native_audio_engine.dart';
import '../core/application/maintenance.dart';
import '../media/audio_player.dart';

AudioController createAudioController({
  MethodChannel channel = const MethodChannel('multiplexr/audio'),
  PlatformTransport? transport,
  Maintenance? maintenance,
}) {
  final raw = transport ?? ChannelTransport(channel);
  final engine = NativeAudioEngine(
    maintenance == null ? raw : MaintenanceTransport(raw, maintenance),
  );
  return AudioController(
    engine: engine,
    pickFiles: engine.pickFiles,
    releaseUnusedFiles: engine.releaseUnusedFiles,
    maintenance: maintenance,
  );
}
