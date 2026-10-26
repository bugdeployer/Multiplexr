import 'session_mini_player.dart';

import 'package:flutter/material.dart';

import 'music_playback.dart';

/// Uses the shell-owned audio session across routes without creating players.
class SharedAudioMiniPlayer extends StatelessWidget {
  const SharedAudioMiniPlayer({super.key, required this.owner});
  final Object owner;
  static final _sessions = Expando<MusicPlayback>();

  static void register(Object owner, MusicPlayback? playback) {
    _sessions[owner] = playback;
  }

  @override
  Widget build(BuildContext context) {
    final playback = _sessions[owner];
    return playback == null
        ? const SizedBox.shrink()
        : SessionMiniPlayer(playback: playback);
  }
}
