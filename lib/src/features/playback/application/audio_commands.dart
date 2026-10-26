import '../../../media/audio_session.dart' show AudioRepeatMode;

enum AudioAction {
  pause,
  stop,
  playPause,
  nextTrack,
  previousTrack,
  clearQueue,
}

sealed class AudioCommand {
  const AudioCommand();
  const factory AudioCommand.action(AudioAction action) = AudioActionCommand;
  const factory AudioCommand.seek(int milliseconds) = AudioSeek;
  const factory AudioCommand.chapter(int index) = AudioChapter;
  const factory AudioCommand.rate(double rate) = AudioRate;
  const factory AudioCommand.sleep(int minutes) = AudioSleep;
  const factory AudioCommand.repeat(AudioRepeatMode mode) = AudioRepeat;
  const factory AudioCommand.bookmark(String label) = AudioBookmark;
  const factory AudioCommand.external(String uri) = AudioExternal;
  void validate() {
    final valid = switch (this) {
      AudioSeek(:final milliseconds) => milliseconds >= 0,
      AudioChapter(:final index) => index >= 0,
      AudioRate(:final rate) => rate.isFinite && rate >= .5 && rate <= 3,
      AudioSleep(:final minutes) => minutes >= -1 && minutes <= 180,
      AudioBookmark(:final label) =>
        label.trim().isNotEmpty && label.length <= 512,
      AudioExternal(:final uri) => uri.trim().isNotEmpty && uri.length <= 8192,
      AudioActionCommand() || AudioRepeat() => true,
    };
    if (!valid) throw ArgumentError('Invalid audio command');
  }
}

final class AudioActionCommand extends AudioCommand {
  const AudioActionCommand(this.action);
  final AudioAction action;
}

final class AudioSeek extends AudioCommand {
  const AudioSeek(this.milliseconds);
  final int milliseconds;
}

final class AudioChapter extends AudioCommand {
  const AudioChapter(this.index);
  final int index;
}

final class AudioRate extends AudioCommand {
  const AudioRate(this.rate);
  final double rate;
}

final class AudioSleep extends AudioCommand {
  const AudioSleep(this.minutes);
  final int minutes;
}

final class AudioRepeat extends AudioCommand {
  const AudioRepeat(this.mode);
  final AudioRepeatMode mode;
}

final class AudioBookmark extends AudioCommand {
  const AudioBookmark(this.label);
  final String label;
}

final class AudioExternal extends AudioCommand {
  const AudioExternal(this.uri);
  final String uri;
}
