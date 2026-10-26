import '../experience/plugins/plugin_session_actions.dart';
import 'audiobook_cover.dart';
import 'grouping.dart';
import 'contracts.dart';

import 'package:app_shell/app_shell.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio_library.dart';
import 'audio_models.dart';
import 'audio_time.dart';
import 'audio_player.dart';
import 'audio_player_components.dart';
import '../features/settings/application/player_preferences.dart';

class AudiobookPlayerPage extends StatefulWidget {
  const AudiobookPlayerPage({
    super.key,
    required this.book,
    required this.catalog,
    this.initialRate,
  });
  final double? initialRate;
  final Audiobook book;
  final AudioLibrary catalog;
  @override
  State<AudiobookPlayerPage> createState() => _AudiobookPlayerPageState();
}

class _AudiobookPlayerPageState extends State<AudiobookPlayerPage> {
  late final catalog = widget.catalog;
  late final player = catalog.audio;
  late final storage = catalog.progress;
  late Audiobook currentBook = widget.book;
  PlayerOptions playerOptions = PlayerOptions.decode(
    PlayerKind.audiobooks,
    null,
  );
  bool opening = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    player.addListener(changed);
    open();
  }

  bool followingBook = false;
  void changed() {
    if (!mounted) return;
    final active = player.state.id;
    if (active != null && active != currentBook.id && !followingBook) {
      followingBook = true;
      catalog
          .books()
          .then((books) {
            final next = books.where((b) => b.id == active).firstOrNull;
            if (mounted && next != null && player.state.id == active) {
              setState(() => currentBook = next);
            }
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() => error = 'Could not load the current audiobook.');
            }
          })
          .whenComplete(() => followingBook = false);
    }
    setState(() {});
  }

  @override
  void dispose() {
    player.removeListener(changed);
    super.dispose();
  }

  Future<void> open() async {
    setState(() {
      opening = true;
      error = null;
    });
    try {
      playerOptions = await catalog.playerPreferences.loadForPlayback(
        PlayerKind.audiobooks,
      );
      if (!mounted) return;
      await player.openBook(currentBook, storage);
      if (widget.initialRate != null) {
        await player.execute(AudioCommand.rate(widget.initialRate!));
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not open this audiobook.');
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> command(AudioCommand command) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await player.execute(command);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not change audio playback.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reorderChapters() async {
    final wasPlaying = player.state.playing;
    if (wasPlaying) {
      await player.execute(const AudioCommand.action(AudioAction.playPause));
    }
    if (!mounted) return;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => GroupOrderPage<AudiobookChapterMarker>(
            title: 'Chapter order',
            items: currentBook.chapterMarkers,
            identity: (c) => c.id,
            label: (c) => c.title,
            save: (ordered) async {
              final updated = Audiobook(
                id: currentBook.id,
                metadata: currentBook.metadata,
                files: currentBook.files,
                chapters: ordered,
              );
              await catalog.replace(updated);
              if (mounted) setState(() => currentBook = updated);
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save chapter order.');
    } finally {
      if (mounted) {
        await player.openBook(currentBook, storage, autoplay: wasPlaying);
        if (wasPlaying && !player.state.playing) {
          await player.execute(
            const AudioCommand.action(AudioAction.playPause),
          );
        }
      }
    }
  }

  Future<void> bookmarks() async {
    try {
      final progress = await storage.read(currentBook.id) as AudiobookProgress?;
      if (!mounted) return;
      final mark = await showModalBottomSheet<AudiobookBookmark>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: AppSpacing.of(context).all(20),
            children: [
              const Text('Bookmarks'),
              if (progress?.bookmarks.isEmpty ?? true)
                const ListTile(title: Text('No bookmarks')),
              for (final b in progress?.bookmarks ?? <AudiobookBookmark>[])
                ListTile(
                  title: Text(b.label),
                  subtitle: Text(audioTime(b.positionMs)),
                  onTap: () => Navigator.pop(context, b),
                ),
            ],
          ),
        ),
      );
      if (!mounted || mark == null) return;
      final index = currentBook.chapterMarkers.indexWhere(
        (c) => c.id == mark.chapterId,
      );
      if (index >= 0) {
        await command(AudioCommand.chapter(index));
        await command(AudioCommand.seek(mark.positionMs));
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not read bookmarks.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = player.state, book = currentBook;
    final chapters = book.record.chapters;
    final active = state.id == book.id;
    final enabled = active && !busy && !opening;
    final index = active ? state.index.clamp(0, chapters.length - 1) : 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiobook'),
        actions: [
          IconButton(
            tooltip: 'Stop audio',
            onPressed: enabled
                ? () => command(const AudioCommand.action(AudioAction.stop))
                : null,
            icon: const AppIcon(AppIconRole.stop),
          ),
        ],
      ),
      body: opening
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppSpacing.of(context).all(24),
              children: [
                Center(
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: AudiobookCover(cover: book.metadata.cover),
                  ),
                ),
                const AppGap(20),
                Text(
                  book.metadata.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (book.metadata.author.isNotEmpty) Text(book.metadata.author),
                if (book.metadata.narrator.isNotEmpty)
                  Text('Narrated by ${book.metadata.narrator}'),
                const AppGap(24),
                Text(
                  chapters[index].title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Chapter ${index + 1} of ${chapters.length}'),
                if (active && state.finished) const Text('Finished'),
                if (error != null || state.error != null) ...[
                  Text(error ?? state.error!),
                  TextButton(onPressed: open, child: const Text('Retry')),
                ],
                if (!active && error == null)
                  TextButton(onPressed: open, child: const Text('Open player')),
                if (state.buffering) const LinearProgressIndicator(),
                Slider(
                  value: state.positionMs.clamp(0, state.durationMs).toDouble(),
                  max: state.durationMs > 0 ? state.durationMs.toDouble() : 1,
                  label: audioTime(state.positionMs),
                  onChanged: enabled && state.durationMs > 0
                      ? (v) => command(AudioCommand.seek(v.round()))
                      : null,
                ),
                Text(
                  '${audioTime(state.positionMs)} / ${audioTime(state.durationMs)}',
                  style: Theme.of(context).extension<ThemeTokens>()?.roleStyle(
                    'timestamp',
                    Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
                  ),
                ),
                const AppGap(12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    IconButton(
                      tooltip: 'Previous chapter',
                      onPressed: enabled && index > 0
                          ? () => command(AudioCommand.chapter(index - 1))
                          : null,
                      icon: const AppIcon(AppIconRole.previous),
                    ),
                    IconButton(
                      tooltip: 'Back ${playerOptions.backSeconds} seconds',
                      onPressed: enabled
                          ? () => command(
                              AudioCommand.seek(
                                (state.positionMs -
                                        playerOptions.backSeconds * 1000)
                                    .clamp(0, 1 << 53),
                              ),
                            )
                          : null,
                      icon: const AppIcon(AppIconRole.replay),
                    ),
                    IconButton.filled(
                      tooltip: state.playing ? 'Pause' : 'Play',
                      onPressed: enabled
                          ? () => command(
                              const AudioCommand.action(AudioAction.playPause),
                            )
                          : null,
                      icon: AppIcon(
                        state.playing ? AppIconRole.pause : AppIconRole.play,
                      ),
                    ),
                    IconButton(
                      tooltip:
                          'Forward ${playerOptions.forwardSeconds} seconds',
                      onPressed: enabled
                          ? () => command(
                              AudioCommand.seek(
                                state.positionMs +
                                    playerOptions.forwardSeconds * 1000,
                              ),
                            )
                          : null,
                      icon: const AppIcon(AppIconRole.seekForward),
                    ),
                    IconButton(
                      tooltip: 'Next chapter',
                      onPressed: enabled && index < chapters.length - 1
                          ? () => command(AudioCommand.chapter(index + 1))
                          : null,
                      icon: const AppIcon(AppIconRole.next),
                    ),
                  ],
                ),
                const PluginSessionActions(),
                const AppGap(16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      children: [
                        AudioControlPair(
                          first: PopupMenuButton<double>(
                            enabled: enabled,
                            tooltip: 'Playback speed',
                            onSelected: (v) => command(AudioCommand.rate(v)),
                            itemBuilder: (_) => [
                              for (final rate in [
                                .5,
                                .75,
                                1.0,
                                1.25,
                                1.5,
                                1.75,
                                2.0,
                                2.5,
                                3.0,
                              ])
                                PopupMenuItem(
                                  value: rate,
                                  child: Text('${rate}x'),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text('${state.rate}x speed'),
                            ),
                          ),
                          second: PopupMenuButton<int>(
                            enabled: enabled,
                            tooltip: 'Sleep timer',
                            onSelected: (v) => command(AudioCommand.sleep(v)),
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 0, child: Text('Off')),
                              const PopupMenuItem(
                                value: -1,
                                child: Text('End of chapter'),
                              ),
                              for (final m in [5, 15, 30, 45, 60])
                                PopupMenuItem(
                                  value: m,
                                  child: Text('$m minutes'),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                state.endOfChapter
                                    ? 'Sleep: chapter end'
                                    : state.deadline > 0
                                    ? 'Sleep: ${((state.deadline - DateTime.now().millisecondsSinceEpoch) / 60000).ceil().clamp(0, 180)} min'
                                    : 'Sleep timer',
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        AudioControlPair(
                          first: TextButton.icon(
                            onPressed: enabled
                                ? () => command(
                                    AudioCommand.bookmark(
                                      'Chapter ${index + 1} · ${audioTime(state.positionMs)}',
                                    ),
                                  )
                                : null,
                            icon: const AppIcon(AppIconRole.bookmarkAdd),
                            label: const Text('Bookmark'),
                          ),
                          second: TextButton(
                            onPressed: enabled ? bookmarks : null,
                            child: const Text('Bookmarks'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const AppGap(24),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  children: [
                    Text(
                      'Chapters',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton(
                      onPressed: enabled ? reorderChapters : null,
                      child: const Text('Reorder chapters'),
                    ),
                  ],
                ),
                const AppGap(12),
                for (var i = 0; i < chapters.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AudioChapterTile(
                      key: ValueKey('chapter:${chapters[i].id}'),
                      number: i + 1,
                      title: chapters[i].title,
                      duration: audioTime(chapters[i].durationMs),
                      selected: active && index == i,
                      playing: state.playing,
                      onTap: enabled
                          ? () => command(AudioCommand.chapter(i))
                          : null,
                    ),
                  ),
              ],
            ),
    );
  }
}
