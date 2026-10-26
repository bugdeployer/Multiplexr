import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/core/platform/platform_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('plugin catalog writes acquire separate native permits across asynchronous work', () async {
    const channel = MethodChannel('multiplexr/library');
    const transport = ChannelTransport(channel);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    var permits = 0;
    await NativeCatalogCommit.run(
      () async => {'approval': 'permit-${++permits}'},
      () async {
        await transport.invokeMethod<void>('readState', 'music:library');
        await Future<void>.delayed(Duration.zero);
        await transport.invokeMethod<void>('writeState', {
          'key': 'music:library',
        });
        await transport.invokeMethod<void>('writeState', {
          'key': 'metadata:music',
        });
      },
    );
    await transport.invokeMethod<void>('writeState', {'key': 'ordinary'});
    expect(calls.map((c) => c.method), [
      'readState',
      'pluginCommit',
      'pluginCommit',
      'writeState',
    ]);
    expect((calls[1].arguments as Map)['identity'], {'approval': 'permit-1'});
    expect((calls[2].arguments as Map)['identity'], {'approval': 'permit-2'});
    expect(permits, 2);
  });
  test(
    'revocation while acquiring a permit prevents the native write',
    () async {
      const channel = MethodChannel('multiplexr/library');
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            writes++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await expectLater(
        NativeCatalogCommit.run(
          () async => throw StateError('Revoked'),
          () =>
              const ChannelTransport(channel)
                  .invokeMethod<void>('applyMetadata', '{}'),
        ),
        throwsStateError,
      );
      expect(writes, 0);
    },
  );
}
