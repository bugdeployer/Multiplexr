class PluginDenied implements Exception {
  const PluginDenied([this.code = 'permission_denied']);
  final String code;
}
