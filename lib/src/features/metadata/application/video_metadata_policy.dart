import '../../../library/library_models.dart';
import 'metadata_matching.dart';

String normalizedTitle(String value) => normalizedMetadataTitle(value);
String metadataQuery(VideoAsset asset, VideoSubtype subtype) =>
    subtype == VideoSubtype.tv
    ? (asset.metadata['series'] ?? asset.title)
    : asset.title;
Map<String, dynamic>? confidentMatch(
  VideoAsset asset,
  VideoSubtype subtype,
  List<Map<String, dynamic>> candidates,
) {
  if (subtype == VideoSubtype.videos) return null;
  final query = normalizedTitle(metadataQuery(asset, subtype));
  // Short numeric residue is not enough evidence for an automatic match.
  if (query.isEmpty ||
      (!RegExp(r'\p{L}', unicode: true).hasMatch(query) &&
          query.runes.length < 3)) {
    return null;
  }
  final year = asset.metadata['year'] ?? '';
  if (subtype == VideoSubtype.movies && !RegExp(r'^\d{4}$').hasMatch(year)) {
    return null;
  }
  if (subtype == VideoSubtype.tv &&
      ((int.tryParse(asset.metadata['season'] ?? '') ?? -1) < 0 ||
          (int.tryParse(asset.metadata['episode'] ?? '') ?? 0) < 1)) {
    return null;
  }
  final fields = subtype == VideoSubtype.movies
      ? ['title', 'original_title']
      : ['series', 'title', 'name', 'original_name'];
  return MetadataScorer.uniqueExact(
    title: metadataQuery(asset, subtype),
    candidates: candidates,
    titleFields: fields,
    year: subtype == VideoSubtype.movies ? year : '',
  );
}
