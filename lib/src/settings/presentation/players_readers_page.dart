import 'package:flutter/material.dart';

import '../../features/settings/application/player_preferences.dart';
import '../../catalog/domain/classification.dart';

import 'package:app_shell/app_shell.dart';

import '../../reading/reading_library.dart';
import '../../reading/reading_workflow_widgets.dart';

class PlayersReadersPage extends StatelessWidget {
  const PlayersReadersPage({
    super.key,
    required this.preferences,
    required this.reading,
  });
  final PlayerPreferences preferences;
  final ReadingLibrary reading;
  @override
  Widget build(BuildContext context) {
    final rows =
        <({String title, String subtitle, AppIconRole icon, Widget page})>[
          (
            title: 'Video',
            subtitle: 'Skip backward and forward',
            icon: AppIconRole.movies,
            page: PlayerOptionsPage(
              preferences: preferences,
              kind: PlayerKind.video,
            ),
          ),
          (
            title: 'Music',
            subtitle: 'Shuffle and repeat for new queues',
            icon: AppIconRole.music,
            page: PlayerOptionsPage(
              preferences: preferences,
              kind: PlayerKind.music,
            ),
          ),
          (
            title: 'Audiobooks',
            subtitle: 'Skip backward and forward',
            icon: AppIconRole.music,
            page: PlayerOptionsPage(
              preferences: preferences,
              kind: PlayerKind.audiobooks,
            ),
          ),
          (
            title: 'Ebooks',
            subtitle: 'Default readers, EPUB, TXT and PDF',
            icon: AppIconRole.reading,
            page: ReadingScopedSettingsPage(
              library: reading,
              collectionId: '',
              subtype: MediaSubtype.ebook,
              application: true,
            ),
          ),
          (
            title: 'Comics',
            subtitle: 'Reading direction, page fit and webtoon mode',
            icon: AppIconRole.collections,
            page: ReadingScopedSettingsPage(
              library: reading,
              collectionId: '',
              subtype: MediaSubtype.comics,
              application: true,
            ),
          ),
        ];
    return Scaffold(
      appBar: AppBar(title: const Text('Players & readers')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 24),
                    ListTile(
                      leading: AppIcon(rows[i].icon),
                      title: Text(rows[i].title),
                      subtitle: Text(rows[i].subtitle),
                      trailing: const AppIcon(AppIconRole.disclosure),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(builder: (_) => rows[i].page),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerOptionsPage extends StatefulWidget {
  const PlayerOptionsPage({
    super.key,
    required this.preferences,
    required this.kind,
  });
  final PlayerPreferences preferences;
  final PlayerKind kind;
  @override
  State<PlayerOptionsPage> createState() => _PlayerOptionsPageState();
}

class _PlayerOptionsPageState extends State<PlayerOptionsPage> {
  PlayerOptions? options;
  bool busy = false;
  int formRevision = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final next = await widget.preferences.load(widget.kind);
      if (mounted) {
        setState(() {
          options = next;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load player settings. Retry.');
      }
    }
  }

  Future<void> save(PlayerOptions next, {bool reset = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (reset) {
        await widget.preferences.reset(widget.kind);
      } else {
        await widget.preferences.save(widget.kind, next);
      }
      await load();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not save player settings. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          formRevision++;
        });
      }
    }
  }

  Widget interval(String label, int seconds, bool back) =>
      DropdownButtonFormField<int>(
        key: ValueKey('$label:$seconds:$formRevision'),
        initialValue: seconds,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        icon: const AppIcon(AppIconRole.expand),
        items: [
          for (final value in PlayerOptions.intervals)
            DropdownMenuItem(value: value, child: Text('$value seconds')),
        ],
        onChanged: busy
            ? null
            : (value) {
                if (value != null) {
                  save(
                    PlayerOptions(
                      backSeconds: back ? value : options!.backSeconds,
                      forwardSeconds: back ? options!.forwardSeconds : value,
                      shuffle: options!.shuffle,
                      repeat: options!.repeat,
                    ),
                  );
                }
              },
      );
  @override
  Widget build(BuildContext context) {
    final music = widget.kind == PlayerKind.music;
    final title = switch (widget.kind) {
      PlayerKind.video => 'Video player',
      PlayerKind.music => 'Music player',
      PlayerKind.audiobooks => 'Audiobook player',
    };
    final value = options;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: AppSpacing.of(context).all(20),
        children: [
          Text(
            music
                ? 'Defaults for new queues. Restored queues keep their saved modes.'
                : 'Skip controls use these intervals the next time you open a player.',
          ),
          const AppGap(24),
          if (busy || value == null && error == null)
            const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextButton(
                onPressed: busy ? null : load,
                child: Text(error!),
              ),
            ),
          if (value != null) ...[
            AppSection(
              title: 'Playback defaults',
              children: [
                Padding(
                  padding: AppSpacing.of(context).symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (music) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Shuffle new queues'),
                          value: value.shuffle,
                          onChanged: busy
                              ? null
                              : (enabled) => save(
                                  PlayerOptions(
                                    backSeconds: value.backSeconds,
                                    forwardSeconds: value.forwardSeconds,
                                    shuffle: enabled,
                                    repeat: value.repeat,
                                  ),
                                ),
                        ),
                        const AppGap(20),
                        DropdownButtonFormField<String>(
                          key: ValueKey('${value.repeat}:$formRevision'),
                          initialValue: value.repeat,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Repeat for new queues',
                          ),
                          icon: const AppIcon(AppIconRole.expand),
                          items: const [
                            DropdownMenuItem(
                              value: '',
                              child: Text('Keep current mode'),
                            ),
                            DropdownMenuItem(value: 'off', child: Text('Off')),
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('Repeat queue'),
                            ),
                            DropdownMenuItem(
                              value: 'one',
                              child: Text('Repeat track'),
                            ),
                          ],
                          onChanged: busy
                              ? null
                              : (repeat) {
                                  if (repeat != null) {
                                    save(
                                      PlayerOptions(
                                        backSeconds: value.backSeconds,
                                        forwardSeconds: value.forwardSeconds,
                                        shuffle: value.shuffle,
                                        repeat: repeat,
                                      ),
                                    );
                                  }
                                },
                        ),
                      ] else ...[
                        interval('Skip backward', value.backSeconds, true),
                        const AppGap(20),
                        interval('Skip forward', value.forwardSeconds, false),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const AppGap(24),
            TextButton(
              onPressed: busy ? null : () => save(value, reset: true),
              child: const Text('Reset to defaults'),
            ),
          ],
        ],
      ),
    );
  }
}
