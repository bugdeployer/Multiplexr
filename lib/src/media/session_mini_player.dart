import '../features/playback/application/audio_commands.dart';

import 'package:flutter/material.dart';

import 'package:app_shell/app_shell.dart';

import 'audio_models.dart';
import 'audiobook_player_page.dart';
import 'contracts.dart';
import 'media_cover.dart';
import 'music_playback.dart';
import 'music_player.dart' show MusicPlayer;

class SessionMiniPlayer extends StatefulWidget {
  const SessionMiniPlayer({super.key, required this.playback});
  final MusicPlayback playback;
  @override
  State<SessionMiniPlayer> createState() => _SessionMiniPlayerState();
}

class _SessionMiniPlayerState extends State<SessionMiniPlayer> {
  Audiobook? book;
  MediaId? requested;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    widget.playback.addListener(changed);
    widget.playback.library.addListener(changed);
    changed();
  }

  void changed() {
    if (!mounted) return;
    final id = widget.playback.audio.state.id;
    if (id?.kind == MediaKind.audiobook && requested != id) {
      requested = id;
      final current = ++revision;
      widget.playback.library
          .audiobookCatalog(collectionId: id!.collectionId)
          .books()
          .then((all) {
            if (mounted && current == revision) {
              setState(() => book = all.where((b) => b.id == id).firstOrNull);
            }
          })
          .catchError((Object _) {});
    }
    setState(() {});
  }

  @override
  void dispose() {
    revision++;
    widget.playback.removeListener(changed);
    widget.playback.library.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback,
        state = playback.audio.state,
        id = state.id;
    final library = playback.library;
    if (id == null ||
        !library.collections.any((c) => c.id == id.collectionId) ||
        !library.canAccessCollection(id.collectionId)) {
      return const SizedBox.shrink();
    }
    final music = id.kind == MediaKind.music ? playback.current : null;
    final audioBook = id.kind == MediaKind.audiobook && book?.id == id
        ? book
        : null;
    if (music == null && audioBook == null) return const SizedBox.shrink();
    final title = music?.metadata.title ?? audioBook!.metadata.title;
    final creator = music?.metadata.artist ?? audioBook!.metadata.author;
    final cover = music?.metadata.cover ?? audioBook!.metadata.cover;
    return SafeArea(
      top: false,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SizedBox.square(
                dimension: 48,
                child: MediaCover(cover: cover),
              ),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                state.error ?? creator,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => music != null
                      ? MusicPlayer(playback: playback)
                      : AudiobookPlayerPage(
                          book: audioBook!,

                          catalog: library.audiobookCatalog(
                            collectionId: audioBook.id.collectionId,
                          ),
                        ),
                ),
              ),
              trailing: IconButton(
                tooltip: state.playing ? 'Pause' : 'Play',
                icon: AppIcon(
                  state.playing ? AppIconRole.pause : AppIconRole.play,
                ),
                onPressed: () async {
                  try {
                    await playback.audio.execute(
                      const AudioCommand.action(AudioAction.playPause),
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            ),
            if (state.durationMs > 0)
              LinearProgressIndicator(
                value: (state.positionMs / state.durationMs).clamp(0, 1),
              ),
          ],
        ),
      ),
    );
  }
}
