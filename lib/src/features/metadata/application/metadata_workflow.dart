import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'metadata_matching.dart';
import '../../../core/application/mutations.dart';
import 'metadata_contracts.dart';

class MetadataWorkflow {
  MetadataWorkflow(
    Iterable<MetadataProvider> providers, {
    required this.mutations,
    this.commitAuthority,
  }) : _providers = Map.unmodifiable({for (final p in providers) p.id: p}) {
    if (this.providers.length != providers.length) {
      throw ArgumentError('Duplicate metadata provider');
    }
  }
  MetadataWorkflow.dynamic(
    Iterable<MetadataProvider> Function() providers, {
    required this.mutations,
    this.commitAuthority,
  }) : _providerFactory = providers,
       _providers = const {};
  Iterable<MetadataProvider> Function()? _providerFactory;
  final Map<String, MetadataProvider> _providers;
  Map<String, MetadataProvider> get providers => _providerFactory == null
      ? _providers
      : Map.unmodifiable({
          for (final provider in _providerFactory!()) provider.id: provider,
        });
  String get implementationEpoch {
    final rows = [
      for (final p in providers.values)
        p is VersionedMetadataProvider
            ? (p as VersionedMetadataProvider).checkpointIdentity
            : p.id,
    ]..sort();
    return sha256.convert(utf8.encode(jsonEncode(rows))).toString();
  }

  final ApplicationMutations mutations;
  final Future<void> Function(MetadataCandidate, Future<void> Function())?
  commitAuthority;
  Future<MetadataSearchPage> search(
    MetadataSearchRequest request,
    MetadataCancellation cancellation,
  ) async {
    request.validate();
    cancellation.check();
    final provider = request.provider == 'host:auto'
        ? providers.values
              .where((p) => p.entities.contains(request.entity))
              .firstOrNull
        : providers[request.provider];
    if (provider != null &&
        request.provider == 'host:auto' &&
        provider.id != 'host:auto') {
      request = request.withProvider(provider.id);
    }
    if (provider == null || !provider.entities.contains(request.entity)) {
      throw const MetadataFailure(
        MetadataFailureKind.unavailable,
        'Provider does not support this media',
      );
    }
    final page = await provider.search(request);
    cancellation.check();
    final response = page.request;
    if ((response.provider != request.provider &&
            request.provider != 'host:auto') ||
        response.entity != request.entity ||
        response.collectionId != request.collectionId ||
        response.title != request.title ||
        response.creator != request.creator ||
        response.locale != request.locale ||
        response.page != request.page ||
        response.cursor != request.cursor ||
        response.artworkOnly != request.artworkOnly ||
        (page.nextPage != null && page.nextPage! <= request.page) ||
        (page.total != null && page.total! < 0) ||
        (page.totalPages != null && page.totalPages! < 0) ||
        (page.nextPage != null &&
            page.totalPages != null &&
            page.nextPage! > page.totalPages!) ||
        page.candidates.any(
          (c) =>
              c.provider != response.provider ||
              c.entity != request.entity ||
              (!request.artworkOnly && c.id.trim().isEmpty),
        )) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Provider returned an invalid metadata page.',
      );
    }
    return page;
  }

  Future<MetadataReview> review(
    MetadataTarget target,
    MetadataCandidate candidate,
    MetadataCancellation cancellation,
  ) async {
    _access(target);
    cancellation.check();
    if (candidate.id.isEmpty || candidate.entity != target.entity) {
      throw const MetadataFailure(
        MetadataFailureKind.invalidResponse,
        'Candidate does not belong to this media type.',
      );
    }
    final before = await target.read();
    final proposed = await target.resolve(candidate, cancellation);
    cancellation.check();
    _access(target);
    return MetadataReview(
      candidate: candidate,
      targetKey: target.key,
      owner: target.owner,
      before: before,
      proposed: proposed,
      exactTitle: MetadataScorer.exact(
        '${candidate.entity == MetadataEntityType.television ? before.fields['series'] ?? before.fields['title'] ?? '' : before.fields['title'] ?? ''}',
        [
          candidate.values['title'],
          candidate.values['name'],
          candidate.values['original_title'],
          candidate.values['original_name'],
        ],
      ),
    );
  }

  Future<void> apply(
    MetadataTarget target,
    MetadataReview review,
    Set<String> fields,
    MetadataCancellation cancellation,
  ) => mutations.run(target.owner, 'metadata:apply:${target.key}', () async {
    _access(target);
    cancellation.check();
    if (fields.any((key) => !review.proposed.containsKey(key))) {
      throw ArgumentError('Unknown metadata field');
    }
    if (target.key != review.targetKey ||
        !identical(target.owner, review.owner) ||
        target.entity != review.candidate.entity) {
      throw const MetadataFailure(
        MetadataFailureKind.conflict,
        'This review belongs to another title.',
      );
    }
    final latest = await target.read();
    final patch = <String, dynamic>{};
    for (final key in fields) {
      final value = review.proposed[key];
      if (metadataValueEquals(latest.fields[key], value)) continue;
      if (!metadataValueEquals(latest.fields[key], review.before.fields[key])) {
        throw const MetadataFailure(
          MetadataFailureKind.conflict,
          'Metadata changed while reviewing. Reopen the match before applying.',
        );
      }
      patch[key] = value;
    }
    cancellation.check();
    _access(target);
    if (fields.isNotEmpty &&
        (patch.isNotEmpty ||
            latest.provider != review.candidate.provenance ||
            latest.candidateId != review.candidate.id)) {
      Future<void> commit() =>
          target.commit(patch, review.candidate, cancellation);
      await authorizeCommit(review.candidate, commit);
    }
  });
  Future<void> authorizeCommit(
    MetadataCandidate candidate,
    Future<void> Function() operation,
  ) async {
    if (candidate.implementation == null) {
      await operation();
      return;
    }
    if (commitAuthority != null) {
      await commitAuthority!(candidate, operation);
      return;
    }
    final delegate = providers.values
        .whereType<MetadataCommitProvider>()
        .firstOrNull;
    if (delegate != null) {
      await delegate.commitCandidate(candidate, operation);
      return;
    }
    throw const MetadataFailure(
      MetadataFailureKind.permission,
      'Plugin commit authority unavailable.',
    );
  }

  void _access(MetadataTarget target) {
    if (!target.authorized) {
      throw const MetadataFailure(
        MetadataFailureKind.permission,
        'Collection access is required.',
      );
    }
  }
}
