import 'package:flutter/services.dart';

import '../../features/sources/application/media_imports.dart';
import 'platform_transport.dart';

class NativeMediaImports implements MediaImports {
  const NativeMediaImports({
    this.transport = const ChannelTransport(MethodChannel('multiplexr/audio')),
  });
  final PlatformTransport transport;
  @override
  Future<String?> cover() async {
    final result = await transport.invokeMethod<String>('pickCover');
    if (result != null &&
        (!result.startsWith('data:image/jpeg;base64,') ||
            result.length > 2000000)) {
      throw const FormatException('Invalid selected cover');
    }
    return result;
  }

  @override
  Future<String?> chapterDocument() =>
      transport.invokeMethod<String>('pickChapters');
  @override
  Future<void> openAudio(String uri) => transport.invokeMethod('external', uri);
}
