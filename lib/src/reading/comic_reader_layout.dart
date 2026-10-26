import 'dart:math' as math;
import 'dart:ui';

import 'comic_reader_controller.dart';

class ComicPlacement {
  const ComicPlacement(this.index, this.source, this.destination);
  final int index;
  final Rect source, destination;
  double get scale => destination.width / source.width;
}

class ComicTilePlacement {
  const ComicTilePlacement(
    this.page,
    this.source,
    this.destination,
    this.targetWidth,
  );
  final int page, targetWidth;
  final Rect source, destination;
  String get key => '$page:$source:$targetWidth';
}

/// Geometry uses original image coordinates; no scroll pixels enter saved progress.
class ComicReaderLayout {
  ComicReaderLayout(this.controller, this.viewport) {
    final c = controller;
    final result = <ComicPlacement>[];
    if (c.webtoon) {
      var y = 0.0;
      for (var i = 0; i < c.pages.length; i++) {
        final b = c.pages[i].bounds;
        final h = b.height * viewport.width / b.width;
        result.add(
          ComicPlacement(i, b, Rect.fromLTWH(0, y, viewport.width, h)),
        );
        y += h;
      }
      size = Size(viewport.width, math.max(viewport.height, y));
    } else {
      final indices = c.visiblePages(viewport.width > viewport.height);
      final slot = viewport.width / indices.length;
      var height = viewport.height;
      for (var n = 0; n < indices.length; n++) {
        final index = indices[n], b = c.bounds(index);
        final scale = c.preferences['fit'] == 'width'
            ? slot / b.width
            : math.min(slot / b.width, viewport.height / b.height);
        final w = b.width * scale, h = b.height * scale;
        final rect = Rect.fromLTWH(
          n * slot + (slot - w) / 2,
          math.max(0, (viewport.height - h) / 2),
          w,
          h,
        );
        height = math.max(height, rect.bottom);
        result.add(ComicPlacement(index, b, rect));
      }
      size = Size(viewport.width, height);
    }
    placements = List.unmodifiable(result);
  }
  final ComicReaderController controller;
  final Size viewport;
  late final Size size;
  late final List<ComicPlacement> placements;
  static const maxVisibleTiles = 16;
  bool truncated = false;
  Offset originFor(int index, double fraction) {
    final p =
        placements.where((p) => p.index == index).firstOrNull ??
        placements.first;
    final y =
        p.destination.top +
        (fraction * controller.pages[index].height - p.source.top) * p.scale;
    return Offset(0, y.clamp(0, math.max(0, size.height - viewport.height)));
  }

  (int, double) anchor(Offset origin) {
    final p =
        placements
            .where(
              (p) =>
                  p.destination.bottom > origin.dy + .01 &&
                  p.destination.right > origin.dx + .01,
            )
            .firstOrNull ??
        placements.last;
    final sourceY = p.source.top + (origin.dy - p.destination.top) / p.scale;
    return (p.index, (sourceY / controller.pages[p.index].height).clamp(0, 1));
  }

  List<ComicTilePlacement> tiles(Rect visible, double pixelRatio, double zoom) {
    final result = <ComicTilePlacement>[];
    truncated = false;
    for (final p in placements) {
      if (!p.destination.overlaps(visible)) continue;
      final scale = p.scale;
      // Two-dimensional source regions keep large pages sharp while zooming.
      final physicalTile = math.max(
        512.0,
        math.max(viewport.width, viewport.height) * pixelRatio / 3,
      );
      final desired = physicalTile / (scale * zoom * pixelRatio);
      var side = 128;
      while (side < desired && side < 65536) {
        side *= 2;
      }
      final firstRow = math.max(
        0,
        ((visible.top - p.destination.top) / scale / side).floor(),
      );
      final lastRow = math.min(
        (p.source.height / side).ceil(),
        ((visible.bottom - p.destination.top) / scale / side).ceil(),
      );
      final firstCol = math.max(
        0,
        ((visible.left - p.destination.left) / scale / side).floor(),
      );
      final lastCol = math.min(
        (p.source.width / side).ceil(),
        ((visible.right - p.destination.left) / scale / side).ceil(),
      );
      for (var row = firstRow; row < lastRow; row++) {
        for (var col = firstCol; col < lastCol; col++) {
          final top = p.source.top + row * side,
              left = p.source.left + col * side;
          final height = math.min(side.toDouble(), p.source.bottom - top);
          final width = math.min(side.toDouble(), p.source.right - left);
          final source = Rect.fromLTWH(left, top, width, height);
          final dest = Rect.fromLTWH(
            p.destination.left + col * side * scale,
            p.destination.top + row * side * scale,
            width * scale,
            height * scale,
          );
          final pixels = (width * scale * pixelRatio * zoom).ceil();
          final target = pixels <= 512
              ? 512
              : pixels <= 1024
              ? 1024
              : 1536;
          if (result.length == maxVisibleTiles) {
            truncated = true;
            return result;
          }
          result.add(ComicTilePlacement(p.index, source, dest, target));
        }
      }
    }
    return result;
  }
}
