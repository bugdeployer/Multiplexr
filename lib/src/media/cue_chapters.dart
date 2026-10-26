import 'audio_models.dart';
import 'contracts.dart';

/// CUE INDEX 01 uses minutes:seconds:75Hz frames, not milliseconds.
/// Resolve explicit filenames only; never guess which source a sidecar describes.
List<AudiobookChapterMarker> parseCueChapters(
  String text,
  List<AudioFile> files,
) {
  if (text.length > 1000000) {
    throw const FormatException('CUE file is too large.');
  }
  AudioFile? source;
  String? title;
  int? start;
  var track = false;
  final chapters = <AudiobookChapterMarker>[];
  void finish() {
    if (!track) return;
    if (source == null || start == null) {
      throw const FormatException(
        'Every audio track needs a source and INDEX 01.',
      );
    }
    chapters.add(
      AudiobookChapterMarker(
        id: 'cue:${source.id}:$start',
        fileId: source.id,
        title: title?.trim().isNotEmpty == true
            ? title!
            : 'Chapter ${chapters.length + 1}',
        startMs: start!,
      ),
    );
    if (chapters.length > 1000) {
      throw const FormatException('Too many CUE chapters.');
    }
    track = false;
    title = null;
    start = null;
  }

  for (final raw in text.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    final file = RegExp(
      r'^FILE\s+(?:"([^"]+)"|(\S+))\s+\S+$',
      caseSensitive: false,
    ).firstMatch(line);
    if (file != null) {
      finish();
      final name = (file[1] ?? file[2]!)
          .replaceAll('\\', '/')
          .split('/')
          .last
          .toLowerCase();
      final matching = files
          .where((f) => f.filename.toLowerCase() == name)
          .toList();
      if (matching.length != 1) {
        throw FormatException(
          'Select the audio file named ${file[1] ?? file[2]}.',
        );
      }
      source = matching.single;
    } else if (RegExp(r'^TRACK\s+', caseSensitive: false).hasMatch(line)) {
      finish();
      if (!RegExp(
        r'^TRACK\s+\d+\s+AUDIO$',
        caseSensitive: false,
      ).hasMatch(line)) {
        throw const FormatException('Only audio tracks are supported.');
      }
      track = true;
    } else if (track &&
        RegExp(r'^TITLE\s+', caseSensitive: false).hasMatch(line)) {
      title = line.replaceFirst(RegExp(r'^TITLE\s+', caseSensitive: false), '');
      if (title!.startsWith('"') && title!.endsWith('"')) {
        title = title!.substring(1, title!.length - 1);
      }
    } else if (track &&
        RegExp(r'^INDEX\s+01\s+', caseSensitive: false).hasMatch(line)) {
      final match = RegExp(
        r'^INDEX\s+01\s+(\d+):(\d{2}):(\d{2})$',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null || start != null) {
        throw const FormatException('Invalid CUE chapter timestamp.');
      }
      final minutes = int.parse(match[1]!),
          seconds = int.parse(match[2]!),
          frames = int.parse(match[3]!);
      if (seconds >= 60 || frames >= 75) {
        throw const FormatException('Invalid CUE seconds or frames.');
      }
      start = (minutes * 60 + seconds) * 1000 + frames * 1000 ~/ 75;
    }
  }
  finish();
  if (chapters.isEmpty) {
    throw const FormatException('No CUE audio chapters found.');
  }
  final result = <AudiobookChapterMarker>[];
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    final source = files.firstWhere((f) => f.id == chapter.fileId);
    final next =
        i + 1 < chapters.length && chapters[i + 1].fileId == chapter.fileId
        ? chapters[i + 1].startMs
        : null;
    result.add(
      AudiobookChapterMarker(
        id: chapter.id,
        fileId: chapter.fileId,
        title: chapter.title,
        startMs: chapter.startMs,
        endMs: next ?? (source.durationMs > 0 ? source.durationMs : null),
      ),
    );
  }
  // Use the same range/overlap validation as imported or restored catalogs.
  Audiobook(
    id: const MediaId(MediaKind.audiobook, 'audiobooks', 'cue-validation'),
    metadata: const AudiobookMetadata(title: 'CUE validation'),
    files: files,
    chapters: result,
  );
  return result;
}
