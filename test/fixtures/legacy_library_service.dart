import 'package:flutter/services.dart';
// Historical provider transport test adapter; never shipped.
import 'package:multiplexr/src/library/library_service.dart' as production;
export 'package:multiplexr/src/library/library_service.dart'
    hide LibraryService;
import 'package:multiplexr/src/library/library_models.dart';

import 'legacy_metadata_request.dart';
import 'legacy_provider_credentials.dart';
import 'legacy_audiobook_metadata_service.dart';

class LibraryService extends production.LibraryService
    implements ProviderCredentialsHost {
  const LibraryService({
    super.transport,
    super.eventHub,
    super.storageOwner,
    super.imports,
  });
  static const channel = production.LibraryService.channel;
  @override
  Future<Map<String, Map<String, dynamic>?>> readStates(
    List<String> keys,
  ) async {
    try {
      return await super.readStates(keys);
    } on MissingPluginException {
      return {for (final key in keys) key: await readState(key)};
    }
  }

  @override
  ProviderCredentials get audiobookCredentials =>
      AudiobookMetadataService.credentials;
  @override
  ProviderCredentials get metadataCredentials =>
      ProviderCredentials(configured: metadataConfigured, commit: saveToken);
  Future<bool> metadataConfigured() async =>
      await transport.invokeMethod<bool>('metadataConfigured') ?? false;
  Future<void> saveToken(String token) =>
      transport.invokeMethod('saveToken', token);
  Future<List<Map<String, dynamic>>> search(String type, String query) async {
    final response = await transport.invokeMapMethod<String, dynamic>(
      'metadataSearch',
      MetadataSearchRequest(type, query).toWire(),
    );
    return (response?['results'] as List? ?? [])
        .map((d) => Map<String, dynamic>.from(d))
        .toList();
  }

  Future<Map<String, dynamic>> searchPage(
    String type,
    String query,
    int page,
  ) async => Map<String, dynamic>.from(
    await transport.invokeMapMethod<String, dynamic>(
          'metadataSearch',
          MetadataSearchRequest(type, query, page: page).toWire(),
        ) ??
        {},
  );

  Future<Map<String, dynamic>> details(
    String type,
    int id, {
    int? season,
    int? episode,
  }) async => Map<String, dynamic>.from(
    await transport.invokeMapMethod('metadataDetails', {
          'type': type,
          'id': id,
          'season': season,
          'episode': episode,
        }) ??
        {},
  );
  Future<List<String>> artwork(VideoAsset asset, String kind) async =>
      List<String>.from(
        await transport.invokeMethod('artwork', {
              'type': asset.mediaSubtype == VideoSubtype.tv ? 'tv' : 'movie',
              'id': asset.providerId,
              'kind': kind,
            }) ??
            [],
      );
}
