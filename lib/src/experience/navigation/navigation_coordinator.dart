import 'dart:async';

import 'navigation_origin.dart';

/// Guards duplicate opens while preserving the caller's existing Navigator stack.
/// A details route and an explicit playback request are distinct operations.
class NavigationCoordinator {
  static final _owners = Expando<NavigationCoordinator>();
  static NavigationCoordinator forOwner(Object owner) =>
      _owners[owner] ??= NavigationCoordinator();
  final Set<String> _opening = {};
  Future<void> run(
    String request,
    Future<void> Function() open, {
    NavigationOrigin? origin,
    FutureOr<void> Function(NavigationOrigin)? restore,
  }) async {
    if (!_opening.add(request)) return;
    try {
      await open();
    } finally {
      _opening.remove(request);
      if (origin != null && restore != null) await restore(origin);
    }
  }
}
