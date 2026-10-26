// Historical provider parser fixtures. Not part of the shipping application.
import 'package:multiplexr/src/features/metadata/application/publication_provider.dart';
export 'package:multiplexr/src/features/metadata/application/music_metadata_target.dart';
export 'package:multiplexr/src/features/metadata/application/music_artwork.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';

class MusicResponse {
  const MusicResponse(this.status, this.bytes);
  final int status;
  final List<int> bytes;
}

typedef MusicGet = Future<MusicResponse> Function(Uri uri);

class MusicBrainzProvider implements MusicProvider {
  MusicBrainzProvider({MusicGet? get, this.rateLimit = true})
    : get = get ?? request;
  final MusicGet get;
  final bool rateLimit;
  static final _owner = Object();
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  final _cache = <String, ({DateTime at, Map<String, dynamic> data})>{};
  @override
  String get id => 'musicbrainz';
  @override
  Set<MetadataEntityType> get entities => {
    MetadataEntityType.musicTrack,
    MetadataEntityType.musicAlbum,
  };
  static Future<MusicResponse> request(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'Multiplexr/0.1.1 (https://bugdeployer.github.io)';
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        if (bytes.length + chunk.length > 4000000) {
          throw const FormatException('Music provider response is too large.');
        }
        bytes.add(chunk);
      }
      return MusicResponse(response.statusCode, bytes.takeBytes());
    } on SocketException {
      throw const MetadataFailure(
        MetadataFailureKind.network,
        'Music provider could not be reached.',
      );
    } on TimeoutException {
      throw const MetadataFailure(
        MetadataFailureKind.network,
        'Music provider timed out. Retry the search.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> json(Uri uri) async {
    final cached = _cache[uri.toString()];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return jsonDecode(jsonEncode(cached.data));
    }
    Future<Map<String, dynamic>> load() async {
      if (rateLimit) {
        final wait = 1100 - DateTime.now().difference(_last).inMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        _last = DateTime.now();
      }
      final response = await get(uri);
      if (response.status == 404) return {};
      if (response.status == 429 || response.status == 503) {
        throw const MetadataFailure(
          MetadataFailureKind.rateLimit,
          'Music provider is busy. Wait a moment, then retry.',
        );
      }
      if (response.status != 200) {
        throw MetadataFailure(
          MetadataFailureKind.network,
          'Music provider returned ${response.status}. Retry the search.',
        );
      }
      final data = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bytes)),
      );
      if (_cache.length >= 50) _cache.remove(_cache.keys.first);
      _cache[uri.toString()] = (at: DateTime.now(), data: data);
      return data;
    }

    return rateLimit
        ? MutationCoordinator.forOwner(_owner).run('musicbrainz', load)
        : load();
  }

  String _quoted(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  static String credits(dynamic value) => (value as List? ?? [])
      .map(
        (v) =>
            '${v['name'] ?? v['artist']?['name'] ?? ''}${v['joinphrase'] ?? ''}',
      )
      .join();
  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async {
    request.validate();
    if (!entities.contains(request.entity)) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'MusicBrainz does not support this title.',
      );
    }
    final album = request.entity == MetadataEntityType.musicAlbum;
    final entity = album ? 'release' : 'recording';
    final query =
        '$entity:${_quoted(request.title.trim())}${request.creator.trim().isEmpty ? '' : ' AND artist:${_quoted(request.creator.trim())}'}';
    final data = await json(
      Uri.https('musicbrainz.org', '/ws/2/$entity/', {
        'fmt': 'json',
        'query': query,
        'limit': '20',
        'offset': '${(request.page - 1) * 20}',
      }),
    );
    final rows = (data[album ? 'releases' : 'recordings'] as List? ?? []);
    final total = (data['count'] as num?)?.toInt() ?? rows.length;
    return MetadataSearchPage(
      request: request,
      attribution: 'MusicBrainz',
      total: total,
      totalPages: (total / 20).ceil(),
      nextPage: request.page * 20 < total ? request.page + 1 : null,
      candidates: rows.expand((raw) {
        final row = Map<String, dynamic>.from(raw);
        final releases = album
            ? [row]
            : ((row['releases'] as List? ?? []).isEmpty
                  ? <dynamic>[null]
                  : row['releases'] as List);
        return releases.map((value) {
          final release = value as Map?;
          final releaseId = release?['id'] as String? ?? '';
          return MetadataCandidate(
            provider: id,
            id: album
                ? row['id']
                : '${row['id']}:${releaseId.isEmpty ? 'recording' : releaseId}',
            entity: request.entity,
            attribution: 'MusicBrainz',
            values: {
              'title': row['title'] ?? '',
              'artist': credits(row['artist-credit']),
              if (!album) 'album': release?['title'] ?? '',
              if (album) 'albumArtist': credits(row['artist-credit']),
              if (!album) 'recordingId': row['id'],
              if (releaseId.isNotEmpty) 'releaseId': releaseId,
              if (release?['release-group']?['id'] != null)
                'releaseGroupId': release!['release-group']['id'],
              if (int.tryParse(
                    '${release?['date'] ?? row['first-release-date'] ?? ''}'
                        .split('-')
                        .first,
                  )
                  case final int year)
                'year': year,
              'edition': [
                release?['date'],
                release?['country'],
                release?['disambiguation'],
              ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
            },
          );
        });
      }),
    );
  }

  @override
  Future<List<String>> artwork(String releaseId) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(releaseId)) return [];
    final data = await json(
      Uri.https('coverartarchive.org', '/release/$releaseId/'),
    );
    return (data['images'] as List? ?? [])
        .map(
          (v) => '${v['thumbnails']?['500'] ?? v['image'] ?? ''}'.replaceFirst(
            'http://',
            'https://',
          ),
        )
        .where((url) => url.startsWith('https://'))
        .toSet()
        .toList();
  }

  @override
  Future<String> download(String url) async =>
      await const MethodChannel('multiplexr/audio')
          .invokeMethod<String>('musicCover', url) ??
      '';
}
