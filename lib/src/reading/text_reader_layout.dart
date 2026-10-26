import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain/reading_annotations.dart';
import 'reading_text_source.dart';
import 'text_reader_controller.dart';

class TextReaderLayout {
  const TextReaderLayout(
    this.resource,
    this.style,
    this.scaler,
    this.direction,
    this.align,
    this.paragraphSpacing, {
    this.annotations = const [],
  });
  final ReadingTextResource resource;
  final TextStyle style;
  final TextScaler scaler;
  final TextDirection direction;
  final TextAlign align;
  final double paragraphSpacing;
  final List<ReadingAnnotation> annotations;
  static const maxWindow = 8192;
  static const colors = {
    'yellow': Color(0xffffe082),
    'green': Color(0xffb9f6ca),
    'blue': Color(0xffb3e5fc),
    'rose': Color(0xffffcdd2),
  };

  TextSpan span(int start, int end) {
    final text = resource.text;
    final events = <int, List<(String, int)>>{start: [], end: []};
    void range(int first, int last, String name) {
      if (last <= start || first >= end) return;
      (events[math.max(first, start).toInt()] ??= []).add((name, 1));
      (events[math.min(last, end).toInt()] ??= []).add((name, -1));
    }

    for (final s in resource.styles) {
      range(s['start'] as int, s['end'] as int, s['kind'] as String);
    }
    for (final annotation in annotations) {
      range(annotation.start, annotation.end, 'mark:${annotation.color}');
    }
    var cursor = text.indexOf('\n\n', start);
    while (cursor >= 0 && cursor + 1 < end) {
      range(cursor + 1, cursor + 2, 'spacing');
      cursor = text.indexOf('\n\n', cursor + 2);
    }
    final offsets = events.keys.toList()..sort();
    final active = <String, int>{};
    final children = <TextSpan>[];
    for (var i = 0; i + 1 < offsets.length; i++) {
      final offset = offsets[i];
      for (final event in events[offset]!) {
        active[event.$1] = (active[event.$1] ?? 0) + event.$2;
      }
      TextStyle value = const TextStyle();
      if ((active['bold'] ?? 0) > 0 || (active['heading'] ?? 0) > 0) {
        value = value.copyWith(
          fontWeight: (style.fontWeight?.value ?? 400) > 700
              ? style.fontWeight
              : FontWeight.bold,
        );
      }
      if ((active['italic'] ?? 0) > 0 || (active['quote'] ?? 0) > 0) {
        value = value.copyWith(fontStyle: FontStyle.italic);
      }
      if ((active['heading'] ?? 0) > 0) {
        value = value.copyWith(fontSize: style.fontSize! * 1.3);
      }
      if ((active['code'] ?? 0) > 0) {
        value = value.copyWith(fontFamily: 'monospace');
      }
      if ((active['spacing'] ?? 0) > 0) {
        value = value.copyWith(
          fontSize: math.max(.1, paragraphSpacing),
          height: 1,
        );
      }
      final mark = active.entries
          .where((e) => e.key.startsWith('mark:') && e.value > 0)
          .firstOrNull;
      if (mark != null) {
        value = value.copyWith(
          backgroundColor: colors[mark.key.substring(5)],
          color: const Color(0xff161616),
        );
      }
      children.add(
        TextSpan(text: text.substring(offset, offsets[i + 1]), style: value),
      );
    }
    return TextSpan(style: style, children: children);
  }

  TextPainter painter(int start, int end, double width) => TextPainter(
    text: span(start, end),
    textScaler: scaler,
    textDirection: direction,
    textAlign: align,
  )..layout(maxWidth: math.max(1, width));

  int pageEnd(int start, double width, double height) {
    final end = TextReaderController.safeOffset(
      resource.text,
      math.min(resource.text.length, start + maxWindow),
    );
    if (start >= end) return end;
    final p = painter(start, end, width);
    try {
      final lines = p.computeLineMetrics();
      final visible = lines
          .where((line) => line.baseline + line.descent <= math.max(height, 1))
          .toList();
      final last = visible.isEmpty ? lines.first : visible.last;
      final position = p.getPositionForOffset(
        Offset(last.left + .1, last.baseline),
      );
      var boundary = p.getLineBoundary(position).end;
      if (boundary < end - start && resource.text[start + boundary] == '\n') {
        boundary++;
      }
      return TextReaderController.safeOffset(
        resource.text,
        math.min(end, start + math.max(1, boundary)),
      );
    } finally {
      p.dispose();
    }
  }

  int pageBefore(int end, double width, double height) {
    final start = TextReaderController.safeOffset(
      resource.text,
      math.max(0, end - maxWindow),
    );
    if (start >= end) return start;
    final p = painter(start, end, width);
    try {
      final lines = p.computeLineMetrics();
      final threshold = p.height - math.max(1, height);
      final line =
          lines
              .where((line) => line.baseline - line.ascent >= threshold)
              .firstOrNull ??
          lines.last;
      final position = p.getPositionForOffset(Offset(line.left, line.baseline));
      return TextReaderController.safeOffset(
        resource.text,
        start + p.getLineBoundary(position).start,
      );
    } finally {
      p.dispose();
    }
  }
}

class ReaderPalette {
  const ReaderPalette(this.background, this.foreground);
  final Color background, foreground;
  static double contrast(Color a, Color b) =>
      (math.max(a.computeLuminance(), b.computeLuminance()) + .05) /
      (math.min(a.computeLuminance(), b.computeLuminance()) + .05);
  static ReaderPalette resolve(
    Map<String, Object> settings,
    ColorScheme scheme,
  ) {
    final palette = switch (settings['palette']) {
      'day' => const ReaderPalette(Color(0xfffffff8), Color(0xff202020)),
      'sepia' => const ReaderPalette(Color(0xfff4e8d0), Color(0xff352a20)),
      'dark' => const ReaderPalette(Color(0xff171717), Color(0xffeeeeee)),
      'custom' => ReaderPalette(
        Color(settings['readerBackground'] as int),
        Color(settings['readerForeground'] as int),
      ),
      _ => ReaderPalette(scheme.surface, scheme.onSurface),
    };
    if (contrast(palette.background, palette.foreground) >= 4.5) return palette;
    final foreground = contrast(palette.background, Colors.black) >= 4.5
        ? Colors.black
        : Colors.white;
    return ReaderPalette(palette.background, foreground);
  }
}
