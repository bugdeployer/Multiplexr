import '../settings/domain/media_settings.dart';
import '../features/settings/application/navigation_preferences.dart';
export '../features/settings/application/navigation_preferences.dart'
    show EffectiveMediaNavigation;

import 'package:flutter/material.dart';

import '../library/library_models.dart';

import 'package:app_shell/app_shell.dart';

/// Shared opening behavior. "automatic" preserves existing video workflows.
class TitleOpeningControl extends StatelessWidget {
  const TitleOpeningControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.inheritedLabel = 'Current behavior',
    this.immediateLabel = 'Play immediately',
    this.showAutomatic = true,
  });
  final String value, inheritedLabel, immediateLabel;
  final ValueChanged<String>? onChanged;
  final bool showAutomatic;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'When opening a title'),
    icon: const AppIcon(AppIconRole.expand),
    items: [
      if (showAutomatic)
        DropdownMenuItem(value: 'automatic', child: Text(inheritedLabel)),
      const DropdownMenuItem(value: 'details', child: Text('Show details')),
      DropdownMenuItem(value: 'play', child: Text(immediateLabel)),
    ],
    onChanged: onChanged == null ? null : (v) => onChanged!(v!),
  );
}

class MediaNavigationSettings extends NavigationValues {
  const MediaNavigationSettings({super.openAction, super.rate});
  static double validRate(Object? value) => NavigationValues.validRate(value);
  static String key(String collectionId, String entityId) =>
      NavigationValues.key(collectionId, entityId);
  static Future<MediaNavigationSettings> load(
    NavigationPreferencesHost service,
    String key,
  ) async {
    final value = await service.navigationPreferences.read(key);
    return MediaNavigationSettings(
      openAction: value.openAction,
      rate: value.rate,
    );
  }
}

Future<void> showMediaNavigationSettings(
  BuildContext context,
  NavigationPreferencesHost service,
  String key,
  String title, {
  bool showRate = true,
  String groupLabel = 'Series',
  Iterable<String> ancestorIds = const [],
  SettingsScope targetScope = SettingsScope.title,
}) async {
  final old = await MediaNavigationSettings.load(service, key);
  EffectiveMediaNavigation? parent;
  try {
    parent = await service.navigationPreferences.parentForKey(key, ancestorIds);
  } catch (_) {
    /* Editing overrides remains available if parent I/O fails. */
  }
  if (!context.mounted) return;
  String source(SettingsScope scope) => switch (scope) {
    SettingsScope.app => 'App defaults',
    SettingsScope.collection => 'Collection',
    SettingsScope.group => groupLabel,
    SettingsScope.title => 'This title',
  };
  ResolvedSetting<T> effective<T extends Object>(
    SettingDefinition<T> definition,
    ResolvedSetting<T> inherited,
    MediaNavigationSettings draft,
  ) => const SettingsResolver().resolve(definition, [
    SettingsLayer(inherited.scope, inherited.sourceId, {
      definition.id: SettingOverride.value(inherited.value),
    }),
    draft.layer(targetScope, title),
  ]);
  var action = old.openAction;
  var rate = old.rate;
  String? error;
  bool saving = false;
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: Text('$title settings'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TitleOpeningControl(
                  value: action,
                  inheritedLabel: 'Inherit parent settings',
                  onChanged: saving ? null : (v) => update(() => action = v),
                ),
                if (parent != null) ...[
                  const AppGap(8),
                  Builder(
                    builder: (_) {
                      final value = effective(
                        MediaSettings.opening,
                        parent!.opening,
                        MediaNavigationSettings(openAction: action, rate: rate),
                      );
                      return Text(
                        'Effective: ${value.value == TitleOpenAction.details ? 'Show details' : 'Play immediately'} · ${source(value.scope)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ] else
                  const Text('Parent settings could not be loaded.'),
                if (showRate) const AppGap(24),
                if (showRate)
                  DropdownButtonFormField<double>(
                    icon: const AppIcon(AppIconRole.expand),
                    initialValue: rate,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Playback speed',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('Inherit parent settings'),
                      ),
                      for (final n in {
                        .5,
                        .75,
                        1.0,
                        1.25,
                        1.5,
                        1.75,
                        2.0,
                        2.5,
                        3.0,
                        if (rate > 0) rate,
                      })
                        DropdownMenuItem(value: n, child: Text('${n}x')),
                    ],
                    onChanged: saving ? null : (v) => update(() => rate = v!),
                  ),
                if (showRate && parent != null) ...[
                  const AppGap(8),
                  Builder(
                    builder: (_) {
                      final value = effective(
                        MediaSettings.rate,
                        parent!.rate,
                        MediaNavigationSettings(openAction: action, rate: rate),
                      );
                      return Text(
                        'Effective: ${value.value}x · ${source(value.scope)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                  ),
                ],
                if (error != null) Text(error!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: saving
                ? null
                : () => update(() {
                    action = 'automatic';
                    rate = 0;
                  }),
            child: const Text('Reset to inherited'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    update(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await service.navigationPreferences.save(
                        key,
                        MediaNavigationSettings(openAction: action, rate: rate),
                      );
                      if (dialog.mounted) Navigator.pop(dialog);
                    } catch (_) {
                      if (dialog.mounted) {
                        update(() {
                          saving = false;
                          error = 'Could not save settings. Try again.';
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

Future<EffectiveMediaNavigation> resolveMediaNavigation(
  NavigationPreferencesHost service, {
  required VideoCollection? collection,
  required String collectionId,
  Iterable<String> ancestorIds = const [],
  required String titleId,
  bool legacyDetails = false,
  bool includeTitle = true,
}) => service.navigationPreferences.resolve(
  collection: collection,
  collectionId: collectionId,
  ancestorIds: ancestorIds,
  titleId: titleId,
  legacyDetails: legacyDetails,
  includeTitle: includeTitle,
);
