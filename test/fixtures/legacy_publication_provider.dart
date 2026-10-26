// Historical provider parser fixtures. Not part of the shipping application.
import 'package:multiplexr/src/features/metadata/application/publication_provider.dart';
export 'package:multiplexr/src/features/metadata/application/reading_metadata_target.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multiplexr/src/core/persistence/state_repository.dart';
import 'package:multiplexr/src/features/metadata/application/metadata_contracts.dart';
import 'package:multiplexr/src/reading/domain/reading_index.dart';
import 'package:multiplexr/src/reading/domain/reading_management.dart';

class ReadingResponse {
  const ReadingResponse(this.status, this.bytes);
  final int status;
  final Uint8List bytes;
}

typedef ReadingGet = Future<ReadingResponse> Function(Uri uri);

/// Low-volume, user-requested publication/edition lookup only. No content API.
class OpenLibraryReadingProvider implements PublicationProvider {
  OpenLibraryReadingProvider({ReadingGet? get, this.rateLimit = true})
    : get = get ?? request;
  final ReadingGet get;
  final bool rateLimit;
  static final _rateOwner = Object();
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  final _cache = <String, Map<String, dynamic>>{};
  @override
  String get id => 'openlibrary';
  @override
  Set<MetadataEntityType> get entities => {
    MetadataEntityType.ebook,
    MetadataEntityType.comic,
  };
  static Future<ReadingResponse> request(Uri uri) async {
    if (uri.scheme != 'https' ||
        !{'openlibrary.org', 'covers.openlibrary.org'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Invalid publication provider address',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'Multiplexr/0.1.1 (+https://bugdeployer.github.io)';
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 25));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 25))) {
        if (bytes.length + chunk.length >
            (uri.host == 'covers.openlibrary.org' ? 8 : 4) * 1024 * 1024) {
          throw const MetadataFailure(
            MetadataFailureKind.invalidResponse,
            'Publication response exceeds capacity',
          );
        }
        bytes.add(chunk);
      }
      return ReadingResponse(response.statusCode, bytes.takeBytes());
    } on SocketException {
      throw const MetadataFailure(
        MetadataFailureKind.network,
        'Publication provider could not be reached.',
      );
    } on TimeoutException {
      throw const MetadataFailure(
        MetadataFailureKind.network,
        'Publication lookup timed out.',
      );
    } finally {
      client.close(force: true);
    }
  }

  static void status(int value) {
    if (value == 429 || value == 503) {
      throw const MetadataFailure(
        MetadataFailureKind.rateLimit,
        'Publication provider is busy. Wait before retrying.',
      );
    }
    if (value == 401 || value == 403) {
      throw const MetadataFailure(
        MetadataFailureKind.authentication,
        'Publication provider rejected the request.',
      );
    }
    if (value == 404) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Publication data is unavailable.',
      );
    }
    if (value != 200) {
      throw const MetadataFailure(
        MetadataFailureKind.network,
        'Publication lookup failed. Retry later.',
      );
    }
  }

  Future<Map<String, dynamic>> json(Uri uri) async {
    final cached = _cache[uri.toString()];
    if (cached != null) return ReadingIndex.copy(cached);
    Future<Map<String, dynamic>> load() async {
      if (rateLimit) {
        final delay = 1100 - DateTime.now().difference(_last).inMilliseconds;
        if (delay > 0) {
          await Future<void>.delayed(Duration(milliseconds: delay));
        }
        _last = DateTime.now();
      }
      final response = await get(uri);
      status(response.status);
      if (response.bytes.length > 4 * 1024 * 1024) {
        throw const MetadataFailure(
          MetadataFailureKind.invalidResponse,
          'Publication response exceeds capacity',
        );
      }
      final data =
          jsonDecode(utf8.decode(response.bytes)) as Map<String, dynamic>;
      if (_cache.length >= 50) _cache.remove(_cache.keys.first);
      _cache[uri.toString()] = ReadingIndex.copy(data);
      return data;
    }

    return rateLimit
        ? MutationCoordinator.forOwner(_rateOwner).run('reading:provider', load)
        : load();
  }

  @override
  Future<MetadataSearchPage> search(MetadataSearchRequest request) async {
    request.validate();
    if (!entities.contains(request.entity) ||
        request.provider != id ||
        request.page > 100) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Unsupported publication search',
      );
    }
    final isbn = request.title.replaceAll(RegExp(r'[-\s]'), '');
    final data = await json(
      Uri.https('openlibrary.org', '/search.json', {
        if (RegExp(r'^(\d{9}[\dXx]|\d{13})$').hasMatch(isbn))
          'q': 'isbn:$isbn'
        else
          'title': request.title,
        if (request.creator.trim().isNotEmpty) 'author': request.creator,
        'fields': 'key,title,author_name,editions,editions.key,editions.title',
        'limit': '10',
        'page': '${request.page}',
      }),
    );
    final docs = data['docs'] as List;
    if (docs.length > 20) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Too many publication results',
      );
    }
    final values = <MetadataCandidate>[];
    for (final work in docs) {
      final editions = work['editions']?['docs'] as List? ?? const [];
      for (final edition in editions.take(2)) {
        final key = edition['key'];
        if (key is! String || !RegExp(r'^/books/OL[0-9]+M$').hasMatch(key)) {
          continue;
        }
        final title = '${edition['title'] ?? work['title'] ?? ''}';
        if (title.isEmpty) continue;
        final authors = (work['author_name'] as List? ?? const [])
            .take(100)
            .map(
              (s) =>
                  s.toString().substring(0, s.toString().length.clamp(0, 4096)),
            )
            .toSet()
            .toList();
        values.add(
          MetadataCandidate(
            provider: id,
            id: key,
            entity: request.entity,
            attribution: 'Open Library · $key',
            values: {
              'title': title.substring(0, title.length.clamp(0, 4096)),
              'authors': authors,
              'identifier': 'OLID:${key.split('/').last}',
              'edition': key.split('/').last,
            },
          ),
        );
      }
    }
    final total =
        (data['numFound'] ?? data['num_found'] ?? values.length) as int;
    return MetadataSearchPage(
      candidates: values.take(20),
      request: request,
      attribution: 'Open Library',
      total: total,
      totalPages: (total / 10).ceil(),
      nextPage: request.page < 100 && request.page * 10 < total
          ? request.page + 1
          : null,
    );
  }

  @override
  Future<Map<String, dynamic>> details(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    if (candidate.provider != id ||
        !RegExp(r'^/books/OL[0-9]+M$').hasMatch(candidate.id) ||
        !entities.contains(candidate.entity)) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Invalid edition identity',
      );
    }
    cancellation.check();
    final data = await json(
      Uri.https('openlibrary.org', '${candidate.id}.json'),
    );
    cancellation.check();
    if (data['key'] != candidate.id) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Edition identity changed',
      );
    }
    String bounded(Object? value) {
      final s = value?.toString() ?? '';
      return s.substring(0, s.length.clamp(0, 4096));
    }

    final description = data['description'];
    final isbn = (data['isbn_13'] as List? ?? data['isbn_10'] as List? ?? [])
        .firstOrNull;
    final languages = data['languages'] as List? ?? [];
    final cover = (data['covers'] as List? ?? [])
        .whereType<int>()
        .where((i) => i > 0)
        .firstOrNull;
    return {
      ...candidate.values,
      if (data['title'] is String) 'title': bounded(data['title']),
      if (isbn != null) 'identifier': 'ISBN:${bounded(isbn)}',
      if (description != null)
        'description': bounded(
          description is Map ? description['value'] : description,
        ),
      if (languages.isNotEmpty)
        'language': bounded(languages.first['key']).split('/').last,
      if (cover != null)
        'coverUrl':
            'https://covers.openlibrary.org/b/id/$cover-L.jpg?default=false',
    };
  }

  @override
  Future<Uint8List> cover(String url) async {
    ReadingManagement.candidateValues({'coverUrl': url});
    final response = await get(Uri.parse(url));
    status(response.status);
    if (response.bytes.length > 8 * 1024 * 1024) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Cover exceeds capacity',
      );
    }
    return response.bytes;
  }
}
