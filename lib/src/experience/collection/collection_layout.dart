import 'package:flutter/widgets.dart';

import '../../catalog/domain/classification.dart';

/// Subtype renderers provide artwork/metadata; view geometry remains shared.
class CollectionLayout extends StatelessWidget {
  const CollectionLayout({
    super.key,
    required this.layout,
    required this.cardSize,
    required this.builder,
  });
  final CatalogLayout layout;
  final double cardSize;
  final Widget Function(BuildContext, double width, bool grid, bool compact)
  builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final grid = layout == CatalogLayout.grid;
      final columns = grid
          ? (constraints.maxWidth / cardSize.clamp(80, 1000)).round().clamp(
              1,
              8,
            )
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return builder(context, width, grid, layout == CatalogLayout.compact);
    },
  );
}
