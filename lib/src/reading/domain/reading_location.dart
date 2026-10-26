/// Versioned publication positions, independent of playback time and UI pixels.
sealed class ReadingLocation {
  const ReadingLocation();
  Map<String, dynamic> toJson();

  static ReadingLocation fromJson(Map<String, dynamic> json) {
    final allowed = json['kind'] == 'text'
        ? {
            'version',
            'kind',
            'resourceId',
            'locatorType',
            'locator',
            'progression',
            'before',
            'highlight',
            'after',
          }
        : {'version', 'kind', 'pageId', 'pageIndex', 'offset'};
    if (json['version'] is! int ||
        json['version'] != 1 ||
        json.keys.any((key) => !allowed.contains(key))) {
      throw FormatException('Unsupported reading location');
    }
    return switch (json['kind']) {
      'text' => TextReadingLocation(
        resourceId: json['resourceId'] as String,
        locatorType: TextLocatorType.values.byName(
          json['locatorType'] as String,
        ),
        locator: json['locator'] as String,
        progression: (json['progression'] as num).toDouble(),
        before: json['before'] as String,
        highlight: json['highlight'] as String,
        after: json['after'] as String,
      ),
      'page' => PageReadingLocation(
        pageId: json['pageId'] as String,
        pageIndex: json['pageIndex'] as int,
        offset: (json['offset'] as num).toDouble(),
      ),
      _ => throw FormatException('Unknown reading location'),
    };
  }
}

enum TextLocatorType { epubCfi, cssSelector, textOffset }

void readingText(String value, {int max = 4096, bool empty = false}) {
  if ((!empty && value.trim().isEmpty) || value.length > max) {
    throw FormatException('Invalid reading text');
  }
}

void readingFraction(double value) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw FormatException('Invalid reading fraction');
  }
}

final class TextReadingLocation extends ReadingLocation {
  TextReadingLocation({
    required this.resourceId,
    required this.locatorType,
    required this.locator,
    required this.progression,
    this.before = '',
    this.highlight = '',
    this.after = '',
  }) {
    readingText(resourceId);
    readingText(locator);
    readingFraction(progression);
    for (final text in [before, highlight, after]) {
      readingText(text, empty: true);
    }
    if (locatorType == TextLocatorType.textOffset &&
        !RegExp(r'^(0|[1-9][0-9]{0,14})$').hasMatch(locator)) {
      throw FormatException('Invalid text offset');
    }
    if (locatorType == TextLocatorType.epubCfi &&
        !(locator.startsWith('epubcfi(') && locator.endsWith(')'))) {
      throw FormatException('Invalid EPUB CFI');
    }
  }
  final String resourceId, locator, before, highlight, after;
  final TextLocatorType locatorType;
  final double progression;
  @override
  Map<String, dynamic> toJson() => {
    'version': 1,
    'kind': 'text',
    'resourceId': resourceId,
    'locatorType': locatorType.name,
    'locator': locator,
    'progression': progression,
    'before': before,
    'highlight': highlight,
    'after': after,
  };
}

final class PageReadingLocation extends ReadingLocation {
  PageReadingLocation({
    required this.pageId,
    required this.pageIndex,
    required this.offset,
  }) {
    readingText(pageId);
    if (pageIndex < 0 || pageIndex >= 200000) {
      throw FormatException('Invalid page index');
    }
    readingFraction(offset);
  }
  final String pageId;
  final int pageIndex;
  final double offset;
  @override
  Map<String, dynamic> toJson() => {
    'version': 1,
    'kind': 'page',
    'pageId': pageId,
    'pageIndex': pageIndex,
    'offset': offset,
  };
}
