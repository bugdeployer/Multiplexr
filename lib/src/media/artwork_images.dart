import 'package:flutter/widgets.dart';

typedef LocalArtworkImage = ImageProvider<Object>? Function(String path);

/// Rendering receives an image provider factory from the application root.
/// Widgets cannot open files or construct a platform-specific filesystem object.
class ArtworkImages extends InheritedWidget {
  const ArtworkImages({super.key, required this.local, required super.child});
  final LocalArtworkImage local;
  static ImageProvider<Object>? localImage(BuildContext context, String path) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkImages>()?.local(path);
  @override
  bool updateShouldNotify(ArtworkImages oldWidget) => oldWidget.local != local;
}
