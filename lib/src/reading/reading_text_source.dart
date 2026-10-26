import 'dart:typed_data';

import 'domain/reading_catalog.dart';

class ReadingTextResource {
  ReadingTextResource({
    required this.text,
    Map<String, int> anchors = const {},
    List<Map<String, dynamic>> styles = const [],
    this.elements = const [],
  }) : anchors = Map.unmodifiable(anchors),
       styles = List.unmodifiable(
         styles.map(Map<String, dynamic>.unmodifiable),
       ) {
    if (text.length > 8 * 1024 * 1024 ||
        this.anchors.length > 100000 ||
        this.styles.length > 100000 ||
        this.anchors.values.any((v) => v < 0 || v > text.length) ||
        this.styles.any(
          (s) =>
              s['start'] is! int ||
              s['end'] is! int ||
              (s['start'] as int) < 0 ||
              (s['end'] as int) > text.length ||
              (s['end'] as int) <= (s['start'] as int) ||
              !{
                'bold',
                'italic',
                'heading',
                'code',
                'quote',
              }.contains(s['kind']),
        )) {
      throw FormatException('Invalid reading text resource');
    }
    if (elements.length > 10000 ||
        elements.any(
          (e) =>
              !{'image', 'link'}.contains(e['kind']) ||
              e['offset'] is! int ||
              (e['offset'] as int) < 0 ||
              (e['offset'] as int) > text.length ||
              e['href'] is! String ||
              (e['href'] as String).length > 4096 ||
              e['label'] is! String,
        )) {
      throw const FormatException('Invalid publication elements');
    }
  }
  final List<Map<String, dynamic>> elements;
  final String text;
  final Map<String, int> anchors;
  final List<Map<String, dynamic>> styles;
  factory ReadingTextResource.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw FormatException('Unsupported text normalization');
    }
    return ReadingTextResource(
      text: json['text'] as String,
      elements: (json['elements'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      anchors: Map<String, int>.from(json['anchors'] as Map),
      styles: (json['styles'] as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList(),
    );
  }
}

class ReadingSearchResult {
  const ReadingSearchResult(
    this.resourceId,
    this.offset,
    this.quote,
    this.context,
  );
  final String resourceId, quote, context;
  final int offset;
}

class ReadingContentsEntry {
  const ReadingContentsEntry(this.resourceId, this.label, {this.anchor = ''});
  final String resourceId, label, anchor;
}

abstract interface class ReadingTextSource {
  Future<void> open(ReadingTitle title);
  Future<ReadingTextResource> resource(String id);
  Future<List<ReadingSearchResult>> search(String query);
  Future<List<ReadingContentsEntry>> contents();
  Future<void> cancel();
  Future<void> close();
  Future<void> textAction(String action, String text);
}

/// Optional publication resources; renderers depend on capabilities rather than native types.
abstract interface class ReadingLinkedResources {
  Future<ReadingTextResource> linkedResource(String resourceId, String href);
}

abstract interface class ReadingImages {
  Future<Uint8List> image(String resourceId, String href);
}
