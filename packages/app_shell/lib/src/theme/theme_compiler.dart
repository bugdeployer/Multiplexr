import '../theme_definition.dart' show AppThemeDefinition;

import 'package:flutter/material.dart';

import '../pixel_theme.dart';
import 'theme_tokens.dart';

/// V1 uses the existing defaults verbatim; V2 compiles into Flutter component themes.
class ThemeCompiler {
  static ThemeData defaults({
    required ThemeTokens tokens,
    required Color base,
    required Color accent,
    required bool dark,
    required bool reduceMotion,
    required bool compact,
  }) {
    final pixel = tokens.stepped, pixelFont = tokens.font == 'pixel';
    final foreground = AppThemeDefinition.ink(base);
    var surface = base;
    for (final opacity in [.055, .0275, 0.0]) {
      final candidate = Color.alphaBlend(
        (dark ? Colors.white : Colors.black).withValues(alpha: opacity),
        base,
      );
      if (AppThemeDefinition.contrast(candidate, foreground) >= 4.5 &&
          AppThemeDefinition.contrast(candidate, accent) >= 4.5) {
        surface = candidate;
        break;
      }
    }
    final muted = Color.alphaBlend(foreground.withValues(alpha: .75), surface);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: accent,
          secondary: accent,
          secondaryContainer: accent.withValues(alpha: .15),
          onSecondaryContainer: accent,
          onPrimary: AppThemeDefinition.ink(accent),
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: AppThemeDefinition.contrast(muted, surface) >= 4.5
              ? muted
              : foreground,
          outlineVariant: foreground.withValues(alpha: .12),
        );
    final outline = BorderSide(color: foreground.withValues(alpha: .18));
    OutlinedBorder shape(double radius, {bool border = false}) => pixel
        ? PixelBorder(side: border ? outline : BorderSide.none)
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: border ? outline : BorderSide.none,
          );
    final input = pixel
        ? OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: outline,
          )
        : OutlineInputBorder(borderRadius: BorderRadius.circular(16));
    return ThemeData(
      extensions: [InterfaceStyle(pixel: pixel)],
      fontFamily: pixelFont ? 'Silkscreen' : null,
      checkboxTheme: CheckboxThemeData(shape: shape(4)),
      sliderTheme: pixel
          ? SliderThemeData(
              thumbShape: const PixelSliderThumb(),
              overlayShape: SliderComponentShape.noOverlay,
            )
          : null,
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: interfaceBackIcon,
        closeButtonIconBuilder: interfaceCloseIcon,
      ),
      textTheme: TextTheme(
        headlineSmall: const TextStyle(fontWeight: FontWeight.w700),
        headlineMedium: const TextStyle(fontWeight: FontWeight.w700),
        labelSmall: pixelFont
            ? const TextStyle(
                fontFamily: 'Silkscreen',
                fontSize: 10,
                letterSpacing: .3,
              )
            : null,
      ),
      chipTheme: ChipThemeData(shape: shape(16)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(shape(16))),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(shape(16))),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: shape(16)),
      ),
      useMaterial3: true,
      splashFactory: reduceMotion
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      pageTransitionsTheme: reduceMotion
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoTransitions(),
                TargetPlatform.iOS: _NoTransitions(),
              },
            )
          : const PageTransitionsTheme(),
      colorScheme: scheme,
      scaffoldBackgroundColor: base,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape(28),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape(24, border: pixel),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: shape(18, border: pixel),
        color: surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: input,
        enabledBorder: input,
        focusedBorder: input.copyWith(
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        backgroundColor: base,
        foregroundColor: foreground,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: accent.withValues(alpha: .15),
        indicatorShape: shape(24),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? accent
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: pixelFont ? 'Silkscreen' : null,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: s.contains(WidgetState.selected)
                ? accent
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape(24, border: pixel),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape(16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape(16),
        ),
      ),
    );
  }

  static ThemeData compile(
    ThemeData base,
    ThemeTokens tokens, {
    required bool custom,
    required bool reduceMotion,
    bool compact = false,
  }) {
    final extensions = base.extensions.values.toList();
    extensions.removeWhere((e) => e is ThemeTokens);
    extensions.add(tokens);
    extensions.removeWhere((e) => e is AppPresentationPolicy);
    extensions.add(
      AppPresentationPolicy(reducedMotion: reduceMotion, compact: compact),
    );
    final colors = base.brightness == Brightness.dark
        ? tokens.darkColors
        : tokens.lightColors;
    var surface = colors['surface'] ?? base.colorScheme.surface;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    if (contrast(base.colorScheme.primary, surface) < 4.5) {
      surface = base.colorScheme.surface;
    }
    final requested = colors['content'] ?? base.colorScheme.onSurface;
    final foreground = contrast(requested, surface) >= 4.5
        ? requested
        : contrast(Colors.white, surface) >= contrast(Colors.black, surface)
        ? Colors.white
        : Colors.black;
    final muted = colors['muted'] ?? foreground;
    final scheme = base.colorScheme.copyWith(
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: contrast(muted, surface) >= 4.5 ? muted : foreground,
      outline: colors['outline'],
      error:
          colors['error'] != null && contrast(colors['error']!, surface) >= 4.5
          ? colors['error']
          : null,
      secondaryContainer:
          colors['selection'] != null &&
              contrast(
                    base.colorScheme.onSecondaryContainer,
                    colors['selection']!,
                  ) >=
                  4.5
          ? colors['selection']
          : null,
    );
    base = base.copyWith(colorScheme: scheme);
    extensions.removeWhere((e) => e is InterfaceStyle);
    extensions.add(InterfaceStyle(pixel: tokens.stepped));
    final outline = BorderSide(
      color: base.colorScheme.onSurface.withValues(alpha: .25),
      width: tokens.borderWidth,
    );
    OutlinedBorder shape(double radius, {bool border = false}) => tokens.stepped
        ? PixelBorder(
            step: tokens.step,
            side: border ? outline : BorderSide.none,
          )
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius * tokens.radiusScale),
            side: border ? outline : BorderSide.none,
          );
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        tokens.stepped ? 0 : tokens.fieldRadius * tokens.radiusScale,
      ),
      borderSide: outline,
    );
    final button = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size.square(48 + (-tokens.density * 4).clamp(0, 8)),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: 16 * tokens.spacing,
          vertical: 12 * tokens.spacing,
        ),
      ),
      shape: WidgetStatePropertyAll(shape(tokens.buttonRadius)),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? scheme.primary.withValues(alpha: tokens.pressedOpacity)
            : states.contains(WidgetState.focused)
            ? scheme.primary.withValues(alpha: tokens.pressedOpacity)
            : null,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: tokens.disabledOpacity)
            : null,
      ),
      animationDuration: Duration(
        milliseconds: reduceMotion ? 0 : tokens.motionMs,
      ),
    );
    final text = ThemeData(brightness: base.brightness).textTheme
        .apply(
          fontFamily: tokens.fontFamily ?? 'Roboto',
          fontFamilyFallback: const ['Roboto', 'Noto Sans'],
        )
        .apply(
          bodyColor: base.colorScheme.onSurface,
          displayColor: base.colorScheme.onSurface,
        );
    TextStyle? spaced(TextStyle? style) => style?.copyWith(
      fontSize: (style.fontSize ?? 14) * tokens.fontScale,
      letterSpacing: (style.letterSpacing ?? 0) + tokens.letterSpacing,
    );
    TextStyle? role(String name, TextStyle? fallback) {
      final values = tokens.typography[name];
      if (values == null) return spaced(fallback);
      return spaced(fallback)?.copyWith(
        fontSize:
            (values['size']?.toDouble() ?? fallback?.fontSize ?? 14) *
            tokens.fontScale,
        height: values['height']?.toDouble(),
        letterSpacing:
            (values['spacing']?.toDouble() ?? 0) + tokens.letterSpacing,
        fontWeight: values['weight'] == null
            ? null
            : FontWeight.values[(values['weight']!.toInt() ~/ 100) - 1],
      );
    }

    Color componentSurface(String role) {
      final requested = colors[role];
      return requested != null &&
              contrast(scheme.onSurface, requested) >= 4.5 &&
              contrast(scheme.primary, requested) >= 4.5
          ? requested
          : scheme.surface;
    }

    final density = (tokens.density + (compact ? -1 : 0)).clamp(-2.0, 2.0);
    return base.copyWith(
      extensions: extensions,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: componentSurface('navigation'),
        foregroundColor: scheme.onSurface,
      ),
      textTheme: text.copyWith(
        bodyLarge: role('body', text.bodyLarge),
        bodyMedium: role('body', text.bodyMedium),
        bodySmall: role('metadata', text.bodySmall),
        titleLarge: role('title', text.titleLarge),
        titleMedium: role('title', text.titleMedium),
        titleSmall: role('caption', text.titleSmall),
        labelMedium: role('label', text.labelMedium),
        labelLarge: role('label', text.labelLarge),
        labelSmall: role('metadata', text.labelSmall),
        headlineMedium: role('heading', text.headlineMedium),
        headlineSmall: role('heading', text.headlineSmall),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity(horizontal: density, vertical: density),
      cardTheme: base.cardTheme.copyWith(
        color: componentSurface('card'),
        shape: shape(tokens.cardRadius, border: true),
        elevation: tokens.elevation,
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(side: WidgetStatePropertyAll(outline)),
      ),
      textButtonTheme: TextButtonThemeData(style: button),
      iconButtonTheme: IconButtonThemeData(
        style: button.copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: field,
        enabledBorder: field,
        focusedBorder: field.copyWith(
          borderSide: BorderSide(
            color: base.colorScheme.primary,
            width: tokens.focusWidth,
          ),
        ),
        filled: true,
        fillColor: componentSurface('field'),
        contentPadding: EdgeInsets.all(16 * tokens.spacing),
      ),
      checkboxTheme: base.checkboxTheme.copyWith(shape: shape(4)),
      chipTheme: base.chipTheme.copyWith(shape: shape(tokens.buttonRadius)),
      segmentedButtonTheme: SegmentedButtonThemeData(style: button),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: componentSurface('dialog'),
        shape: shape(tokens.dialogRadius, border: true),
        elevation: tokens.elevation,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        shape: shape(tokens.dialogRadius),
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: componentSurface('menu'),
        shape: shape(tokens.menuRadius, border: true),
        elevation: tokens.elevation,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorShape: shape(tokens.buttonRadius),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: tokens.fontFamily,
            fontSize: 11 * tokens.fontScale,
          ),
        ),
      ),
      sliderTheme: tokens.stepped
          ? base.sliderTheme.copyWith(thumbShape: const PixelSliderThumb())
          : const SliderThemeData(),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding: EdgeInsets.symmetric(horizontal: 16 * tokens.spacing),
        minVerticalPadding: 8 * tokens.spacing,
        shape: shape(tokens.cardRadius),
      ),
    );
  }
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
