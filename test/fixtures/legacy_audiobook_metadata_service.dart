import 'legacy_provider_credentials.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:multiplexr/src/media/contracts.dart';

class AudiobookMetadataService implements MediaMetadataProvider {
  const AudiobookMetadataService();
  static const channel = MethodChannel('multiplexr/audio');
  static final credentials = ProviderCredentials(
    configured: () async =>
        await channel.invokeMethod<bool>('metadataDbConfigured') ?? false,
    commit: (value) => channel.invokeMethod<void>('metadataDbSave', value),
  );
  @override
  String get providerId => 'audible';
  @override
  Set<MediaKind> get supportedKinds => const {MediaKind.audiobook};
  @override
  Future<List<Map<String, dynamic>>> search(MediaKind kind, String query) {
    if (!supportedKinds.contains(kind)) {
      throw UnsupportedError('This provider supports audiobooks only.');
    }
    return find(query);
  }

  Future<List<Map<String, dynamic>>> find(
    String title, {
    String author = '',
    String region = 'us',
    String provider = 'audible',
    int page = 1,
  }) async {
    final result = await channel.invokeMethod<String>('searchMetadata', {
      'title': title,
      'author': author,
      'region': region,
      'provider': provider,
      'page': page,
    });
    return (jsonDecode(result ?? '[]') as List)
        .map(
          (value) => <String, dynamic>{
            ...Map<String, dynamic>.from(value),
            'region': region,
          },
        )
        .toList();
  }

  Future<String> cover(String url, {String provider = 'audible'}) async =>
      await channel.invokeMethod<String>('metadataCover', {
        'url': url,
        'provider': provider,
      }) ??
      '';
}
