import '../../../core/application/application_failure.dart';
import 'metadata_contracts.dart';

/// UI consumes already translated application failures. Native/provider details
/// are translated by adapters and never inspected through a platform exception.
String metadataFailureMessage(Object error) => switch (error) {
  MetadataFailure(:final message) => message,
  ApplicationFailure(:final message) => message,
  _ => 'Metadata provider could not complete the request.',
};
