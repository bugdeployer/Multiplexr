import 'dart:async';

import 'package:flutter/services.dart';

enum PlatformFailureKind {
  cancelled,
  permission,
  authentication,
  rateLimit,
  network,
  storage,
  unavailable,
  conflict,
  unknown,
}

/// Keeps legacy error codes/catches working while exposing a typed category.
class PlatformFailure extends PlatformException {
  PlatformFailure(PlatformException error)
    : kind = switch (error.code) {
        'cancelled' => PlatformFailureKind.cancelled,
        'permission' || 'locked' => PlatformFailureKind.permission,
        'authentication' => PlatformFailureKind.authentication,
        'rateLimit' => PlatformFailureKind.rateLimit,
        'network' => PlatformFailureKind.network,
        'storage' => PlatformFailureKind.storage,
        'unsupported' || 'unavailable' => PlatformFailureKind.unavailable,
        'conflict' => PlatformFailureKind.conflict,
        _ => PlatformFailureKind.unknown,
      },
      super(
        code: error.code,
        message: error.message,
        details: error.details,
        stacktrace: error.stacktrace,
      );
  final PlatformFailureKind kind;
}

abstract interface class PlatformTransport {
  Future<T?> invokeMethod<T>(String method, [Object? arguments]);
  Future<Map<K, V>?> invokeMapMethod<K, V>(String method, [Object? arguments]);
}

/// Host-only context carried to the native catalog executor. Never exposed to scripts.
class NativeCatalogCommit {
  static final _key = Object();
  static Future<void> run(
    Future<Map<String, Object>> Function() permit,
    Future<void> Function() operation,
  ) => runZoned(operation, zoneValues: {_key: permit});
}

class ChannelTransport implements PlatformTransport {
  const ChannelTransport(this.channel);
  final MethodChannel channel;
  static final _stores = Expando<Map<String, Object>>();
  Object get persistenceOwner => (_stores[channel.binaryMessenger] ??= {})
      .putIfAbsent(channel.name, Object.new);
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    try {
      final permit =
          Zone.current[NativeCatalogCommit._key]
              as Future<Map<String, Object>> Function()?;
      if (permit != null &&
          channel.name == 'multiplexr/library' &&
          const {
            'writeState',
            'applyMetadata',
            'commitReadingManagement',
          }.contains(method)) {
        return await channel.invokeMethod<T>('pluginCommit', {
          'identity': await permit(),
          'method': method,
          'arguments': arguments,
        });
      }
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw PlatformFailure(e);
    }
  }

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Object? arguments,
  ]) async {
    final value = await invokeMethod<Object>(method, arguments);
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Platform response must be a map.');
    }
    return Map<K, V>.from(value);
  }
}
