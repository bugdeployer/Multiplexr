import 'package:flutter/material.dart';

import '../retro_icons.dart';
import 'theme_tokens.dart';

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.role, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.shadows,
  });
  final AppIconRole role;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final List<Shadow>? shadows;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ThemeTokens>();
    final asset = tokens?.assets[tokens.iconAssets[role.name]];
    if (asset != null) {
      final image = Image.memory(
        asset.bytes,
        width: size ?? 24,
        height: size ?? 24,
        fit: BoxFit.contain,
        color: color ?? IconTheme.of(context).color,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) =>
            Icon(appIconData[role], size: size, color: color, shadows: shadows),
      );
      return Semantics(
        label: semanticLabel,
        child:
            appIconData[role]!.matchTextDirection &&
                Directionality.of(context) == TextDirection.rtl
            ? Transform.flip(flipX: true, child: image)
            : image,
      );
    }
    final icon = appIconData[role]!;
    final mapped = tokens?.pixelIcons == true ? retroIcons[icon] ?? icon : icon;
    final result = Icon(
      mapped,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      shadows: shadows,
    );
    return icon.matchTextDirection &&
            tokens?.pixelIcons == true &&
            Directionality.of(context) == TextDirection.rtl
        ? Transform.flip(flipX: true, child: result)
        : result;
  }
}
