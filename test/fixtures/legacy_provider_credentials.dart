/// Credentials stay in the native credential store. The application exposes
/// connection status and explicit user-requested replacement/removal only.
class ProviderCredentials {
  const ProviderCredentials({required this.configured, required this.commit});
  final Future<bool> Function() configured;
  final Future<void> Function(String) commit;
  Future<void> save(String value) => commit(value.trim());
}

abstract interface class ProviderCredentialsHost {
  ProviderCredentials get metadataCredentials;
  ProviderCredentials get audiobookCredentials;
}
