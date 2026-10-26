export 'theme/app_components.dart';
import 'theme/theme_tokens.dart';
import 'theme/app_icon.dart';
export 'theme/app_icon.dart';
export 'theme/theme_tokens.dart' show AppIconRole;

import 'dart:math' as math;

import 'package:pixelarticons/pixelarticons.dart';

import 'retro_icons.dart';

import 'package:flutter/material.dart';

@immutable
class InterfaceStyle extends ThemeExtension<InterfaceStyle> {
  const InterfaceStyle({required this.pixel});
  final bool pixel;
  @override
  InterfaceStyle copyWith({bool? pixel}) =>
      InterfaceStyle(pixel: pixel ?? this.pixel);
  @override
  InterfaceStyle lerp(covariant InterfaceStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

bool isPixel(BuildContext context) =>
    Theme.of(context).extension<InterfaceStyle>()?.pixel ?? false;

Widget interfaceBackIcon(BuildContext context) =>
    const AppIcon(AppIconRole.back);
Widget interfaceCloseIcon(BuildContext context) =>
    const AppIcon(AppIconRole.close);

class PixelSliderThumb extends SliderComponentShape {
  const PixelSliderThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 12);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) => context.canvas.drawRect(
    Rect.fromCenter(center: center, width: 12, height: 12),
    Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..isAntiAlias = false,
  );
}

/// Select the icon family from the active theme while retaining action semantics.
@Deprecated('Use AppIcon with an explicit AppIconRole.')
class InterfaceIcon extends Icon {
  const InterfaceIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.shadows,
  });
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ThemeTokens>();
    if (!(tokens?.pixelIcons ?? isPixel(context)) || icon == null) {
      return super.build(context);
    }
    final mapped = Icon(
      retroIcons[icon] ?? Pixel.circlequestion,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      shadows: shadows,
    );
    return icon!.matchTextDirection &&
            Directionality.of(context) == TextDirection.rtl
        ? Transform.flip(flipX: true, child: mapped)
        : mapped;
  }
}

class InterfaceSwitchListTile extends StatelessWidget {
  const InterfaceSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title, subtitle, secondary;
  final EdgeInsetsGeometry? contentPadding;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ThemeTokens>();
    if (!(tokens?.stepped ?? isPixel(context)) && tokens?.radiusScale != 0) {
      return SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        contentPadding: contentPadding,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: onChanged != null,
        child: ListTile(
          contentPadding: contentPadding,
          leading: secondary,
          title: title,
          subtitle: subtitle,
          enabled: onChanged != null,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          trailing: ExcludeSemantics(
            child: Opacity(
              opacity: onChanged == null ? (tokens?.disabledOpacity ?? .38) : 1,
              child: Container(
                width: 48,
                height: 28,
                padding: const EdgeInsets.all(4),
                decoration: ShapeDecoration(
                  color: value
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  shape: interfaceShape(
                    context,
                    radius: 14,
                    side: BorderSide(
                      color: value ? scheme.primary : scheme.outline,
                    ),
                  ),
                ),
                child: Align(
                  alignment: value
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: Container(
                    width: 16,
                    height: 16,
                    color: value ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

OutlinedBorder interfaceShape(
  BuildContext context, {
  double radius = 18,
  BorderSide side = BorderSide.none,
}) => (Theme.of(context).extension<ThemeTokens>()?.stepped ?? isPixel(context))
    ? PixelBorder(
        side: side,
        step: Theme.of(context).extension<ThemeTokens>()?.step ?? 3,
      )
    : RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          radius *
              (Theme.of(context).extension<ThemeTokens>()?.radiusScale ?? 1),
        ),
        side: side,
      );
BorderRadius interfaceRadius(BuildContext context, double radius) =>
    BorderRadius.circular(
      (Theme.of(context).extension<ThemeTokens>()?.stepped ?? isPixel(context))
          ? 0
          : radius *
                (Theme.of(context).extension<ThemeTokens>()?.radiusScale ?? 1),
    );

/// Orthogonal stair-step corners. Stroke, ink clipping and outer clipping share one path.
class PixelBorder extends OutlinedBorder {
  const PixelBorder({super.side, this.step = 3});
  final double step;
  Path path(Rect rect) {
    final s = math.min(step, math.min(rect.width, rect.height) / 6);
    final l = rect.left, r = rect.right, t = rect.top, b = rect.bottom;
    return Path()
      ..moveTo(l + s * 2, t)
      ..lineTo(r - s * 2, t)
      ..lineTo(r - s * 2, t + s)
      ..lineTo(r - s, t + s)
      ..lineTo(r - s, t + s * 2)
      ..lineTo(r, t + s * 2)
      ..lineTo(r, b - s * 2)
      ..lineTo(r - s, b - s * 2)
      ..lineTo(r - s, b - s)
      ..lineTo(r - s * 2, b - s)
      ..lineTo(r - s * 2, b)
      ..lineTo(l + s * 2, b)
      ..lineTo(l + s * 2, b - s)
      ..lineTo(l + s, b - s)
      ..lineTo(l + s, b - s * 2)
      ..lineTo(l, b - s * 2)
      ..lineTo(l, t + s * 2)
      ..lineTo(l + s, t + s * 2)
      ..lineTo(l + s, t + s)
      ..lineTo(l + s * 2, t + s)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => path(rect);
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      path(rect.deflate(side.width));
  @override
  bool operator ==(Object other) =>
      other is PixelBorder && other.side == side && other.step == step;
  @override
  int get hashCode => Object.hash(side, step);
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is PixelBorder
      ? PixelBorder(
          side: BorderSide.lerp(a.side, side, t),
          step: a.step + (step - a.step) * t,
        )
      : super.lerpFrom(a, t);
  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is PixelBorder
      ? PixelBorder(
          side: BorderSide.lerp(side, b.side, t),
          step: step + (b.step - step) * t,
        )
      : super.lerpTo(b, t);
  @override
  PixelBorder copyWith({BorderSide? side}) =>
      PixelBorder(side: side ?? this.side, step: step);
  @override
  PixelBorder scale(double t) =>
      PixelBorder(side: side.scale(t), step: step * t);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawPath(path(rect.deflate(side.width / 2)), side.toPaint());
    }
  }
}

class InterfaceClip extends StatelessWidget {
  const InterfaceClip({super.key, required this.child, this.radius = 18});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: ShapeBorderClipper(shape: interfaceShape(context, radius: radius)),
    child: child,
  );
}

enum PixelSymbol { library, spaces, settings, video, folder, plus, sparkle }

/// Compatibility wrapper for the existing semantic navigation symbols.
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.symbol, {super.key, this.size = 24, this.color});
  final PixelSymbol symbol;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Icon(
    switch (symbol) {
      PixelSymbol.library => Pixel.grid2x22,
      PixelSymbol.spaces => Pixel.blocks,
      PixelSymbol.settings => Pixel.slidershorizontal,
      PixelSymbol.video => Pixel.video,
      PixelSymbol.folder => Pixel.folder,
      PixelSymbol.plus => Pixel.plus,
      PixelSymbol.sparkle => Pixel.sparkles,
    },
    size: size,
    color: color,
  );
}
