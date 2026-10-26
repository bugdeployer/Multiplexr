import '../experience/plugins/plugin_contribution_page.dart';
import '../features/catalog/application/extension_catalog.dart';
import '../experience/plugins/plugin_session_actions.dart';
import '../features/playback/application/audio_commands.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'audio_session.dart';
import 'media_cover.dart';
import 'music_playback.dart';

import '../catalog/domain/playlist.dart';

String _time(int ms) =>
    '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}';

class MusicPlayer extends StatelessWidget {
  const MusicPlayer({super.key, required this.playback});
  final MusicPlayback playback;
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _editQueue(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final before = playback.captureQueue();
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Queue updated'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () =>
                  _run(context, () => playback.restoreQueue(before)),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _savePlaylist(BuildContext context) async {
    var input = '';

    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save queue as playlist'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(labelText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await _run(context, () async {
      final repository = playback.repository, saved = playback.captureQueue();
      final songs = playback.queue;
      await repository.savePlaylist(
        MusicPlaylist(
          id: repository.newIdentity(),
          name: name,
          scope: saved.scope == null
              ? const PlaylistScope.global()
              : PlaylistScope.collection(saved.scope!),
          entries: [
            for (final t in songs)
              PlaylistEntry(
                id: repository.newIdentity(),
                track: t.catalogTitle.id,
              ),
          ],
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Playlist saved')));
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final track = playback.current;
      final state = playback.audio.state;
      return Scaffold(
        appBar: AppBar(title: const Text('Now playing')),
        body: track == null
            ? const Center(child: Text('No eligible track is playing.'))
            : ReorderableListView.builder(
                padding: AppSpacing.of(context).all(20),
                buildDefaultDragHandles: false,
                onReorderItem: (oldIndex, newIndex) => _editQueue(
                  context,
                  () => playback.reorderEntry(oldIndex, newIndex),
                ),
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: MediaCover(cover: track.metadata.cover),
                    ),
                    const AppGap(24),
                    Text(
                      track.metadata.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const AppGap(8),
                    Text(track.metadata.artist),
                    if (track.metadata.album.isNotEmpty)
                      Text(track.metadata.album),
                    const AppGap(16),
                    if (state.buffering) const LinearProgressIndicator(),
                    Slider(
                      value: state.positionMs
                          .clamp(0, state.durationMs)
                          .toDouble(),
                      max: state.durationMs > 0
                          ? state.durationMs.toDouble()
                          : 1,
                      semanticFormatterCallback: (v) => _time(v.toInt()),
                      onChanged: state.durationMs > 0
                          ? (v) => _run(
                              context,
                              () => playback.audio.execute(
                                AudioCommand.seek(v.toInt()),
                              ),
                            )
                          : null,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_time(state.positionMs)),
                        Text(_time(state.durationMs)),
                      ],
                    ),
                    const AppGap(12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        IconButton(
                          tooltip: 'Shuffle',
                          isSelected: playback.shuffled,
                          onPressed: () => _run(
                            context,
                            () => playback.setShuffle(!playback.shuffled),
                          ),
                          icon: const AppIcon(AppIconRole.shuffle),
                        ),
                        IconButton(
                          tooltip: 'Previous track',
                          onPressed: () => _run(
                            context,
                            () => playback.audio.execute(
                              const AudioCommand.action(
                                AudioAction.previousTrack,
                              ),
                            ),
                          ),
                          icon: const AppIcon(AppIconRole.previous),
                        ),
                        FilledButton(
                          onPressed: () => _run(
                            context,
                            () => playback.audio.execute(
                              const AudioCommand.action(AudioAction.playPause),
                            ),
                          ),
                          child: AppIcon(
                            state.playing
                                ? AppIconRole.pause
                                : AppIconRole.play,
                            semanticLabel: state.playing ? 'Pause' : 'Play',
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next track',
                          onPressed: () => _run(
                            context,
                            () => playback.audio.execute(
                              const AudioCommand.action(AudioAction.nextTrack),
                            ),
                          ),
                          icon: const AppIcon(AppIconRole.next),
                        ),
                        IconButton(
                          tooltip: 'Repeat: ${playback.repeat.name}',
                          isSelected: playback.repeat != AudioRepeatMode.off,
                          onPressed: () => _run(
                            context,
                            () => playback.setRepeat(
                              AudioRepeatMode.values[(playback.repeat.index +
                                      1) %
                                  3],
                            ),
                          ),
                          icon: AppIcon(
                            playback.repeat == AudioRepeatMode.one
                                ? AppIconRole.repeatOne
                                : AppIconRole.repeat,
                          ),
                        ),
                      ],
                    ),
                    const PluginSessionActions(),
                    PluginDetailExtensions(
                      collection: track.id.collectionId,
                      kind: ExtensionMedia.music,
                      titleId: track.id.itemId,
                    ),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(state.error!),
                      ),
                    const AppGap(24),
                    const Divider(),
                    const AppGap(16),
                    Text(
                      'Queue',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const AppGap(8),
                    Text(
                      playback.shuffled
                          ? 'Shuffle is on. This list keeps your saved queue order.'
                          : 'Drag to reorder. Tap a track to play it.',
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: () => _savePlaylist(context),
                          child: const Text('Save as playlist'),
                        ),
                        TextButton(
                          onPressed: () =>
                              _editQueue(context, playback.clearQueue),
                          child: const Text('Clear queue'),
                        ),
                      ],
                    ),
                    const AppGap(12),
                  ],
                ),
                itemCount: playback.queue.length,
                itemBuilder: (context, i) {
                  final track = playback.queue[i],
                      entry = playback.visibleEntries[i];
                  return ListTile(
                    key: ValueKey(entry.entryId),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: AppIcon(AppIconRole.drag),
                      ),
                    ),
                    title: Text(track.metadata.title),
                    subtitle: Text(track.metadata.artist),
                    selected: entry.entryId == playback.currentEntryId,
                    onTap: () => _run(context, () => playback.selectEntry(i)),
                    trailing: PopupMenuButton<String>(
                      icon: const AppIcon(AppIconRole.menu),
                      tooltip: 'Queue options for ${track.metadata.title}',
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'next',
                          child: Text('Move to next'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from queue'),
                        ),
                      ],
                      onSelected: (value) => _editQueue(
                        context,
                        () => value == 'next'
                            ? playback.moveNext(entry.entryId)
                            : playback.removeEntry(entry.entryId),
                      ),
                    ),
                  );
                },
              ),
      );
    },
  );
}
