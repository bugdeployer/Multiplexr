import 'package:unorm_dart/unorm_dart.dart' as unorm;

String normalizedMetadataTitle(String value) => unorm
    .nfkc(value)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]', unicode: true), '');

abstract final class MetadataScorer {
  static bool exact(String query, Iterable<Object?> names) {
    final normalized = normalizedMetadataTitle(query);
    return normalized.isNotEmpty &&
        names.any(
          (v) => v is String && normalizedMetadataTitle(v) == normalized,
        );
  }

  static Map<String, dynamic>? uniqueExact({
    required String title,
    required Iterable<Map<String, dynamic>> candidates,
    required List<String> titleFields,
    String year = '',
    String creator = '',
  }) {
    final matches = candidates
        .where(
          (c) =>
              exact(title, titleFields.map((k) => c[k])) &&
              (year.isEmpty ||
                  (c['year'] ??
                              c['release_date'] ??
                              c['first_air_date'] ??
                              c['publicationDate'] ??
                              '')
                          .toString()
                          .split('-')
                          .first ==
                      year) &&
              (creator.isEmpty || exact(creator, [c['author']])),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }
}
