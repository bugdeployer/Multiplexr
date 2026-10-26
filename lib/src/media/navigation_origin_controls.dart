import 'package:flutter/material.dart';

import '../experience/navigation/navigation_origin.dart';

/// Route return uses the same live controls; no replacement of Navigator history.
void restoreOrigin(
  BuildContext context,
  NavigationOrigin origin, {
  required TextEditingController query,
  ScrollController? scroll,
  VoidCallback? controls,
}) {
  if (!context.mounted) return;
  query.text = origin.query;
  controls?.call();
  if (scroll != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && scroll.hasClients) {
        scroll.jumpTo(
          origin.scrollOffset.clamp(0, scroll.position.maxScrollExtent),
        );
      }
    });
  }
}
