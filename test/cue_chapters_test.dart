import 'package:flutter_test/flutter_test.dart';
import 'package:multiplexr/src/media/audio_models.dart';
import 'package:multiplexr/src/media/audio_player.dart';
import 'package:multiplexr/src/media/contracts.dart';
import 'package:multiplexr/src/media/cue_chapters.dart';

const source = AudioFile(
  id: 'source',
  uri: 'content://whole',
  filename: 'Book.mp3',
  durationMs: 60000,
);
const cue = '''FILE "Book.mp3" MP3
  TRACK 01 AUDIO
    TITLE "Opening"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second chapter"
    INDEX 01 00:10:15
''';
void main() {
  test(
    'one file can own multiple logical chapters using CUE frame timestamps',
    () {
      final markers = parseCueChapters(cue, [source]);
      expect(markers.map((c) => c.startMs), [0, 10200]);
      expect(markers.map((c) => c.endMs), [10200, 60000]);
      final book = Audiobook(
        id: const MediaId(MediaKind.audiobook, 'audiobooks', 'book'),
        metadata: const AudiobookMetadata(title: 'Book'),
        files: const [source],
        chapters: markers,
      );
      final roundTrip = Audiobook.fromJson(book.toJson());
      expect(roundTrip.record.chapters.length, 2);
      expect(roundTrip.durationMs, 60000);
      final request = AudioPlaybackRequest.audiobook(
        roundTrip,
        AudiobookProgress(
          book.id,
          chapterId: markers[1].id,
          positionMs: 5000,
          finished: false,
        ),
      );
      final queue = request.toJson()['files'] as List;
      expect(queue[0]['uri'], queue[1]['uri']);
      expect(queue[0]['id'], isNot(queue[1]['id']));
      expect(queue[1]['startMs'], 10200);
      expect(request.index, 1);
      expect(
        request.positionMs,
        5000,
        reason: 'Resume positions are relative to the chapter range',
      );
    },
  );
  test(
    'missing, ambiguous and malformed CUE sources never guess a mapping',
    () {
      expect(() => parseCueChapters(cue, []), throwsFormatException);
      expect(
        () => parseCueChapters(cue, [
          source,
          const AudioFile(uri: 'content://other', filename: 'Book.mp3'),
        ]),
        throwsFormatException,
      );
      expect(
        () => parseCueChapters(cue.replaceFirst('00:10:15', '00:10:75'), [
          source,
        ]),
        throwsFormatException,
      );
      expect(
        () => parseCueChapters(cue.replaceFirst('INDEX 01 00:00:00', ''), [
          source,
        ]),
        throwsFormatException,
      );
      expect(
        () => parseCueChapters(cue.replaceFirst('00:10:15', '00:00:00'), [
          source,
        ]),
        throwsArgumentError,
      );
      expect(
        () => parseCueChapters(cue.replaceFirst('00:10:15', '01:10:00'), [
          source,
        ]),
        throwsArgumentError,
      );
    },
  );
  test(
    'CUE sidecar basenames resolve across directory separators and files',
    () {
      const second = AudioFile(
        id: 'second',
        uri: 'content://second',
        filename: 'Part 2.flac',
        durationMs: 30000,
      );
      final markers = parseCueChapters(
        '''FILE "dir\\BOOK.mp3" MP3
TRACK 01 AUDIO
INDEX 01 00:00:00
FILE "folder/Part 2.flac" WAVE
TRACK 02 AUDIO
TITLE "Next part"
INDEX 01 00:00:00''',
        [source, second],
      );
      expect(markers.map((c) => c.fileId), ['source', 'second']);
      expect(markers.map((c) => c.endMs), [60000, 30000]);
    },
  );
}
