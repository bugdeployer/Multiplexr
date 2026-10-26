import 'package:flutter/services.dart';

import '../application/application_failure.dart';

/// Framework-specific translation stays outside application contracts.
ApplicationFailure applicationFailure(Object error) {
  if (error is ApplicationFailure) return error;
  if (error is MissingPluginException) {
    return const ApplicationFailure(
      ApplicationFailureKind.unavailable,
      'Video collections are currently available on Android.',
    );
  }
  final kind = error is PlatformException
      ? switch (error.code) {
          'cancelled' => ApplicationFailureKind.cancelled,
          'permission' || 'locked' => ApplicationFailureKind.permission,
          'authentication' => ApplicationFailureKind.authentication,
          'rateLimit' => ApplicationFailureKind.rateLimit,
          'network' => ApplicationFailureKind.network,
          'storage' => ApplicationFailureKind.storage,
          'unsupported' || 'unavailable' => ApplicationFailureKind.unavailable,
          'conflict' => ApplicationFailureKind.conflict,
          _ => ApplicationFailureKind.unknown,
        }
      : error is FormatException
      ? ApplicationFailureKind.invalidResponse
      : ApplicationFailureKind.unknown;
  return ApplicationFailure(kind, 'Could not load your library. Try again.');
}
