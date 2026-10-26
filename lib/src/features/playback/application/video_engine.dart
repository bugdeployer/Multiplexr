class PlaybackTrack {
  const PlaybackTrack(this.id, {this.title, this.language});
  final String id;
  final String? title, language;
  factory PlaybackTrack.fromJson(Map d) =>
      PlaybackTrack(d['id'], title: d['title'], language: d['language']);
}

typedef AudioTrack = PlaybackTrack;
typedef SubtitleTrack = PlaybackTrack;

class PlaybackTracks {
  PlaybackTracks(Map d)
    : audio = (d['audio'] as List? ?? [])
          .map((v) => PlaybackTrack.fromJson(v as Map))
          .toList(),
      subtitle = (d['subtitles'] as List? ?? [])
          .map((v) => PlaybackTrack.fromJson(v as Map))
          .toList();
  final List<PlaybackTrack> audio, subtitle;
}

class PlaybackSelection {
  PlaybackSelection(Map d)
    : audio = PlaybackTrack(d['selectedAudio'] ?? 'auto'),
      subtitle = PlaybackTrack(d['selectedSubtitle'] ?? 'auto');
  final PlaybackTrack audio, subtitle;
}

class PlaybackState {
  PlaybackState([this.data = const {}]);
  final Map data;
  Duration get position => Duration(milliseconds: data['positionMs'] ?? 0);
  Duration get duration => Duration(milliseconds: data['durationMs'] ?? 0);
  bool get playing => data['playing'] == true;
  bool get buffering => data['buffering'] == true;
  bool get completed => data['completed'] == true;
  double get rate => (data['rate'] as num? ?? 1).toDouble();
  double get volume => (data['volume'] as num? ?? 1).toDouble();
  bool get repeat => data['repeat'] == true;
  bool get privateCollection => data['privateCollection'] == true;
  bool get autoPip => data['autoPip'] == true;
  bool get background => data['background'] == true;
  String get fit => data['fit'] as String? ?? 'fit';
  double get subtitleScale =>
      ((data['subtitleScale'] as num?)?.toDouble() ?? 1).clamp(.6, 2);
  bool get subtitleBackground => data['subtitleBackground'] == true;
  String? get externalSubtitle => data['externalSubtitle'] as String?;
  String? get error => data['error'];
  PlaybackTracks get tracks => PlaybackTracks(data);
  PlaybackSelection get track => PlaybackSelection(data);
}

abstract interface class VideoEngine {
  PlaybackState get state;
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
  void dispose();
  Future<void> attach(int id);
  Future<void> refresh();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration value);
  Future<void> setRate(double value);
  Future<void> setVolume(double value);
  Future<void> setRepeat(bool value);
  Future<void> setAutoPip(bool value);
  Future<void> setBackground(bool value);
  Future<void> setFit(String value);
  Future<void> setSubtitleStyle(double scale, bool background);
  Future<void> controlsVisible(bool value);
  Future<void> addSubtitle();
  Future<void> removeSubtitle();
  Future<void> resetPreferences();
  Future<void> retry();
  Future<void> setAudioTrack(PlaybackTrack value);
  Future<void> setSubtitleTrack(PlaybackTrack value);
}

abstract interface class VideoWindow {
  bool get active;
  bool get backgrounded;
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
