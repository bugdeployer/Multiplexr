import '../../../reading/domain/reading_catalog.dart';

class ReadingScanSource {
  ReadingScanSource({
    required this.key,
    required this.name,
    required this.series,
    required Iterable<ReadingResource> resources,
  }) : resources = List.unmodifiable(resources);
  final String key, name, series;
  final List<ReadingResource> resources;
}

/// Review projection only. Commit authority belongs to its issuing source port;
/// persistence documents, snapshots and discovery envelopes never cross here.
class ReadingScanPreview {
  ReadingScanPreview({
    required this.collectionId,
    required this.requestId,
    required this.complete,
    required this.added,
    required this.relinked,
    required this.missing,
    Iterable<String> warnings = const [],
    Iterable<String> unresolved = const [],
    Iterable<ReadingScanSource> sources = const [],
    Iterable<ReadingTitle> titles = const [],
  }) : warnings = List.unmodifiable(warnings),
       unresolved = List.unmodifiable(unresolved),
       sources = List.unmodifiable(sources),
       titles = List.unmodifiable(titles);
  final String collectionId, requestId;
  final bool complete;
  final int added, relinked, missing;
  final List<String> warnings, unresolved;
  final List<ReadingScanSource> sources;
  final List<ReadingTitle> titles;
  bool get canApply => complete && unresolved.isEmpty;
}

class ReadingScanChoices {
  ReadingScanChoices({
    Map<String, String> rootReplacements = const {},
    Map<String, String> relinks = const {},
    Map<String, String> grouping = const {},
    Map<String, List<String>> resourceOrder = const {},
    Iterable<String> titleOrder = const [],
  }) : rootReplacements = Map.unmodifiable(rootReplacements),
       relinks = Map.unmodifiable(relinks),
       grouping = Map.unmodifiable(grouping),
       resourceOrder = Map.unmodifiable({
         for (final e in resourceOrder.entries)
           e.key: List<String>.unmodifiable(e.value),
       }),
       titleOrder = List.unmodifiable(titleOrder);
  final Map<String, String> rootReplacements, relinks, grouping;
  final Map<String, List<String>> resourceOrder;
  final List<String> titleOrder;
}

class ReadingScanRequest {
  ReadingScanRequest({
    required this.collectionId,
    required this.requestId,
    this.encoding = 'utf-8',
    Map<String, String> encodings = const {},
    required this.choices,
  }) : encodings = Map.unmodifiable(encodings);
  final String collectionId, requestId, encoding;
  final Map<String, String> encodings;
  final ReadingScanChoices choices;
}
