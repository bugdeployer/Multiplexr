import 'package:flutter/services.dart';

import '../core/platform/platform_transport.dart';
import '../features/metadata/application/metadata_contracts.dart';

MetadataFailure metadataFailure(Object error) {
  if (error is MetadataFailure) return error;
  final code = error is PlatformException
      ? error.code
      : error is PlatformFailure
      ? error.code
      : '';
  final kind = switch (code) {
    'authentication' => MetadataFailureKind.authentication,
    'rateLimit' => MetadataFailureKind.rateLimit,
    'network' => MetadataFailureKind.network,
    'storage' => MetadataFailureKind.storage,
    'permission' || 'locked' => MetadataFailureKind.permission,
    'conflict' => MetadataFailureKind.conflict,
    'unavailable' || 'unsupported' => MetadataFailureKind.unavailable,
    'cancelled' => MetadataFailureKind.cancelled,
    _ => MetadataFailureKind.invalidResponse,
  };
  return MetadataFailure(
    kind,
    (error is PlatformException ? error.message : null) ??
        switch (kind) {
          MetadataFailureKind.authentication =>
            'Provider rejected the credential. Update Settings → Metadata.',
          MetadataFailureKind.rateLimit =>
            'Provider rate limit reached. Wait before resuming.',
          MetadataFailureKind.network =>
            'Network unavailable. Check your connection.',
          MetadataFailureKind.storage => 'Could not save to device storage.',
          MetadataFailureKind.permission => 'Collection access is required.',
          MetadataFailureKind.cancelled => 'Cancelled',
          MetadataFailureKind.conflict =>
            'Metadata changed while reviewing. Reopen the match.',
          MetadataFailureKind.unavailable =>
            'This metadata or artwork is unavailable.',
          _ => 'Metadata provider could not complete the request.',
        },
  );
}
