import 'dart:convert';

// Detached, recursively immutable JSON values keep provider/caller mutations
// from changing the baseline while a review is open.
Object? _freezeMetadata(Object? value) => switch (value) {
  Map() => Map<String, dynamic>.unmodifiable(
    value.map((k, v) => MapEntry(k as String, _freezeMetadata(v))),
  ),
  List() => List<dynamic>.unmodifiable(value.map(_freezeMetadata)),
  _ => value,
};

Map<String, dynamic> _metadataFields(Map<String, dynamic> fields) =>
    _freezeMetadata(jsonDecode(jsonEncode(fields))) as Map<String, dynamic>;

bool metadataValueEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length)
            .every((i) => metadataValueEquals(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every(
          (k) => b.containsKey(k) && metadataValueEquals(a[k], b[k]),
        );
  }
  return a == b;
}

// Describing future records does not register a provider or enable a subtype.
// Append values to preserve existing names and ordinal positions.
enum MetadataEntityType {
  movie,
  television,
  audiobook,
  musicTrack,
  musicAlbum,
  ebook,
  comic,
  image,
}

enum MetadataFailureKind {
  cancelled,
  permission,
  unavailable,
  authentication,
  rateLimit,
  network,
  conflict,
  storage,
  invalidResponse,
}

class MetadataFailure implements Exception {
  const MetadataFailure(this.kind, this.message);
  final MetadataFailureKind kind;
  final String message;
  bool get retryable => kind == MetadataFailureKind.network;
  @override
  String toString() => message;
}

class MetadataCancellation {
  MetadataCancellation({this.checkAccess});
  final void Function()? checkAccess;
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    checkAccess?.call();
    if (_cancelled) {
      throw const MetadataFailure(MetadataFailureKind.cancelled, 'Cancelled');
    }
  }
}

class MetadataSearchRequest {
  const MetadataSearchRequest({
    required this.provider,
    required this.entity,
    required this.title,
    this.creator = '',
    this.locale = 'us',
    this.collectionId = '',
    this.page = 1,
    this.cursor,
    this.artworkOnly = false,
  });
  final String provider, title, creator, locale, collectionId;
  final MetadataEntityType entity;
  final int page;
  final String? cursor;
  // Artwork lookup can use a cover URL without a metadata-record identity.
  // Such a candidate still cannot enter the metadata review/apply path.
  final bool artworkOnly;
  MetadataSearchRequest atPage(int value) => MetadataSearchRequest(
    provider: provider,
    entity: entity,
    title: title,
    creator: creator,
    locale: locale,
    collectionId: collectionId,
    cursor: cursor,
    page: value,
    artworkOnly: artworkOnly,
  );
  MetadataSearchRequest withProvider(String id) => MetadataSearchRequest(
    provider: id,
    entity: entity,
    title: title,
    creator: creator,
    locale: locale,
    page: page,
    cursor: cursor,
    artworkOnly: artworkOnly,
    collectionId: collectionId,
  );
  void validate() {
    if (provider.isEmpty || title.trim().isEmpty || page < 1) {
      throw ArgumentError('Invalid metadata search request');
    }
  }
}

class MetadataImplementation {
  const MetadataImplementation({
    required this.plugin,
    required this.publisher,
    required this.version,
    required this.contribution,
    this.instance = '',
    this.permissionRevision = 0,
    this.collection = '',
  });
  final String plugin, publisher, version, contribution;
  final String instance, collection;
  final int permissionRevision;
  Map<String, Object> toJson() => {
    'plugin': plugin,
    'publisher': publisher,
    'version': version,
    'contribution': contribution,
    'instance': instance,
    'permissionRevision': permissionRevision,
    'collection': collection,
  };
}

class MetadataCandidate {
  MetadataCandidate({
    required this.provider,
    required this.id,
    required this.entity,
    required Map<String, dynamic> values,
    required this.attribution,
    this.implementation,
  }) : _encoded = jsonEncode(values);
  final String provider, id, attribution;
  final MetadataImplementation? implementation;
  final MetadataEntityType entity;
  String get provenance {
    if (implementation == null) {
      return provider;
    }
    final token = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'plugin': implementation!.plugin,
          'publisher': implementation!.publisher,
          'version': implementation!.version,
          'contribution': implementation!.contribution,
        }),
      ),
    );
    return 'plugin:$token';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider,
    'entity': entity.name,
    'attribution': attribution,
    'values': values,
    if (implementation != null) 'implementation': implementation!.toJson(),
  };
  factory MetadataCandidate.fromJson(
    Map<String, dynamic> value, {
    String? provider,
    MetadataEntityType? entity,
    String attribution = '',
  }) {
    final implementation = value['implementation'] as Map?;
    return MetadataCandidate(
      provider: value['provider'] as String? ?? provider ?? '',
      id: value['id'] as String,
      entity: value['entity'] == null
          ? entity!
          : MetadataEntityType.values.byName(value['entity'] as String),
      values: Map<String, dynamic>.from(value['values'] as Map),
      attribution: value['attribution'] as String? ?? attribution,
      implementation: implementation == null
          ? null
          : MetadataImplementation(
              plugin: implementation['plugin'] as String,
              publisher: implementation['publisher'] as String,
              version: implementation['version'] as String,
              contribution: implementation['contribution'] as String,
              instance: implementation['instance'] as String,
              permissionRevision: implementation['permissionRevision'] as int,
              collection: implementation['collection'] as String,
            ),
    );
  }
  final String _encoded;
  Map<String, dynamic> get values =>
      Map<String, dynamic>.from(jsonDecode(_encoded));
}

class MetadataSearchPage {
  MetadataSearchPage({
    required Iterable<MetadataCandidate> candidates,
    required this.request,
    this.nextPage,
    this.totalPages,
    this.total,
    this.nextCursor,
    required this.attribution,
  }) : candidates = List.unmodifiable(candidates);
  final List<MetadataCandidate> candidates;
  final MetadataSearchRequest request;
  final int? nextPage, totalPages, total;
  final String? nextCursor;
  final String attribution;
}

abstract interface class VersionedMetadataProvider {
  String get checkpointIdentity;
}

abstract interface class MetadataProvider {
  String get id;
  Set<MetadataEntityType> get entities;
  Future<MetadataSearchPage> search(MetadataSearchRequest request);
}

class MetadataSnapshot {
  MetadataSnapshot(
    Map<String, dynamic> fields, {
    Set<String> manualFields = const {},
    this.provider = '',
    this.candidateId = '',
  }) : fields = _metadataFields(fields),
       manualFields = Set.unmodifiable(manualFields);
  final Map<String, dynamic> fields;
  final Set<String> manualFields;
  final String provider, candidateId;
}

class MetadataReview {
  MetadataReview({
    required this.candidate,
    required this.targetKey,
    required this.owner,
    required this.before,
    required Map<String, dynamic> proposed,
    this.exactTitle = false,
  }) : proposed = _metadataFields(proposed);
  final MetadataCandidate candidate;
  final String targetKey;
  final Object owner;
  final bool exactTitle;
  final MetadataSnapshot before;
  final Map<String, dynamic> proposed;
  Set<String> get defaults => proposed.keys
      .where(
        (k) =>
            !before.manualFields.contains(k) &&
            proposed[k] != null &&
            proposed[k].toString().isNotEmpty,
      )
      .toSet();
}

abstract interface class MetadataTarget {
  MetadataEntityType get entity;
  Object get owner;
  String get key;
  bool get authorized;
  Future<MetadataSnapshot> read();
  Future<Map<String, dynamic>> resolve(
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  );
  Future<void> commit(
    Map<String, dynamic> selected,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  );
}

/// Registry delegates preserve the same host commit authority as their workflow.
abstract interface class MetadataCommitProvider {
  Future<void> commitCandidate(
    MetadataCandidate candidate,
    Future<void> Function() operation,
  );
}
