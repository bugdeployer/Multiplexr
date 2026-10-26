import 'package:flutter/material.dart';

import 'theme_tokens.dart';

/// Accessibility and user choices take precedence over package presentation.
@immutable
class AppPresentationPolicy extends ThemeExtension<AppPresentationPolicy> {
  const AppPresentationPolicy({
    required this.reducedMotion,
    required this.compact,
  });
  final bool reducedMotion, compact;
  @override
  AppPresentationPolicy copyWith({bool? reducedMotion, bool? compact}) =>
      AppPresentationPolicy(
        reducedMotion: reducedMotion ?? this.reducedMotion,
        compact: compact ?? this.compact,
      );
  @override
  AppPresentationPolicy lerp(
    covariant AppPresentationPolicy? other,
    double t,
  ) => t < .5 ? this : other ?? this;
}

class AppSpacing {
  AppSpacing.of(BuildContext context)
    : factor =
          (Theme.of(context).extension<ThemeTokens>()?.spacing ?? 1) *
          (Theme.of(context).extension<AppPresentationPolicy>()?.compact == true
              ? .9
              : 1);
  final double factor;
  double value(double base) => base * factor;
  EdgeInsets all(double base) => EdgeInsets.all(value(base));
  EdgeInsets symmetric({double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(
        horizontal: value(horizontal),
        vertical: value(vertical),
      );
}

class AppGap extends StatelessWidget {
  const AppGap(this.extent, {super.key}) : horizontal = false;
  const AppGap.horizontal(this.extent, {super.key}) : horizontal = true;
  final double extent;
  final bool horizontal;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: horizontal ? AppSpacing.of(context).value(extent) : null,
    height: horizontal ? null : AppSpacing.of(context).value(extent),
  );
}

class AppMotion {
  static Duration duration(BuildContext context) {
    final theme = Theme.of(context);
    if (MediaQuery.maybeOf(context)?.disableAnimations == true ||
        theme.extension<AppPresentationPolicy>()?.reducedMotion == true) {
      return Duration.zero;
    }
    return Duration(
      milliseconds: theme.extension<ThemeTokens>()?.motionMs ?? 200,
    );
  }
}

/// One host-owned section treatment for built-in and contributed settings.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });
  final String title;
  final String? description;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: AppSpacing.of(context).symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppSpacing.of(context).symmetric(horizontal: 16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (description != null)
            Padding(
              padding: AppSpacing.of(context).all(16),
              child: Text(
                description!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const AppGap(8),
          ...children,
        ],
      ),
    ),
  );
}
