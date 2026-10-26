import 'features/settings/application/space_preferences.dart';
export 'features/settings/application/space_preferences.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'library/library_models.dart';
import 'features/settings/application/user_preferences.dart';
import 'library/series.dart';

import 'package:app_shell/app_shell.dart';

String showcaseKey(VideoAsset asset) => jsonEncode([
  asset.collectionId,
  asset.mediaSubtype == VideoSubtype.tv && seriesIdentity(asset) != null
      ? 'series:${seriesIdentity(asset)}'
      : asset.id,
]);

Future<void> showSpaceSettings(
  BuildContext context,
  SpacePreferences preferences,
  UserPreferencesHost service,
  bool videos, {
  List<VideoAsset> eligible = const [],
}) async {
  final original = preferences.forSpace(videos);
  final draft = SpaceDisplay()..restore(original.toJson());
  draft.pins.removeWhere(
    (key) => !eligible.any((asset) => showcaseKey(asset) == key),
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: AppSpacing.of(context).all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${videos ? 'Videos' : 'Cinema'} settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const AppGap(24),
                DropdownButtonFormField<String>(
                  icon: const AppIcon(AppIconRole.expand),
                  initialValue: draft.source,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Showcase artwork',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'pinned',
                      child: Text('Pinned titles'),
                    ),
                    DropdownMenuItem(
                      value: 'recent',
                      child: Text('Recently added'),
                    ),
                    DropdownMenuItem(
                      value: 'favorites',
                      child: Text('Favorites'),
                    ),
                    DropdownMenuItem(
                      value: 'progress',
                      child: Text('Continue watching'),
                    ),
                  ],
                  onChanged: (value) => update(() => draft.source = value!),
                ),
                if (draft.source == 'pinned') ...[
                  const AppGap(12),
                  for (var i = 0; i < draft.pins.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        eligible
                            .firstWhere((a) => showcaseKey(a) == draft.pins[i])
                            .title,
                      ),
                      leading: Text('${i + 1}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Move artwork up',
                            onPressed: i == 0
                                ? null
                                : () => update(() {
                                    final key = draft.pins.removeAt(i);
                                    draft.pins.insert(i - 1, key);
                                  }),
                            icon: const AppIcon(AppIconRole.sortAscending),
                          ),
                          IconButton(
                            tooltip: 'Remove pinned title',
                            onPressed: () =>
                                update(() => draft.pins.removeAt(i)),
                            icon: const AppIcon(AppIconRole.close),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton(
                    onPressed: draft.pins.length >= 3
                        ? null
                        : () async {
                            final chosen = await showDialog<String>(
                              context: context,
                              builder: (dialog) => SimpleDialog(
                                title: const Text('Choose a showcase title'),
                                children: [
                                  SizedBox(
                                    width: 400,
                                    height: 320,
                                    child: ListView(
                                      children: [
                                        for (final asset in eligible.where(
                                          (a) => !draft.pins.contains(
                                            showcaseKey(a),
                                          ),
                                        ))
                                          ListTile(
                                            title: Text(asset.title),
                                            subtitle: Text(
                                              asset.relativePath.isEmpty
                                                  ? asset.filename
                                                  : asset.relativePath,
                                            ),
                                            onTap: () => Navigator.pop(
                                              dialog,
                                              showcaseKey(asset),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (chosen != null && context.mounted) {
                              update(() => draft.pins.add(chosen));
                            }
                          },
                    child: const Text('Add pinned title (up to 3)'),
                  ),
                ],
                const AppGap(16),

                const AppGap(12),
                InterfaceSwitchListTile(
                  title: const Text('Hide watched'),
                  subtitle: const Text(
                    'Browsing lists only. Continue watching, favorites and queues stay available.',
                  ),
                  value: draft.hideWatched,
                  onChanged: (value) => update(() => draft.hideWatched = value),
                ),
                const AppGap(16),
                InterfaceSwitchListTile(
                  title: const Text('Show artwork'),
                  value: draft.artwork,
                  onChanged: (value) => update(() => draft.artwork = value),
                ),
                InterfaceSwitchListTile(
                  title: const Text('Show item and collection counts'),
                  value: draft.counts,
                  onChanged: (value) => update(() => draft.counts = value),
                ),

                const AppGap(16),
                FilledButton(
                  onPressed: () async {
                    final previous = original.toJson();
                    original.restore(draft.toJson());
                    try {
                      await preferences.save(service.userPreferences);
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      original.restore(previous);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not save space settings. Try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SpaceExitGuard extends StatefulWidget {
  const SpaceExitGuard({
    super.key,
    required this.preferences,
    required this.videos,
    required this.child,
    this.name,
    this.display,
    this.exitMessage,
  });
  final String? name, exitMessage;
  final SpaceDisplay? display;
  final SpacePreferences preferences;
  final bool videos;
  final Widget child;
  @override
  State<SpaceExitGuard> createState() => _SpaceExitGuardState();
}

class _SpaceExitGuardState extends State<SpaceExitGuard> {
  @override
  Widget build(BuildContext context) => widget.child;
}
