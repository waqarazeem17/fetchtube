// Parsing is the only non-trivial logic that runs off-device: yt-dlp's format list
// is noisy (many codec variants per resolution) and this is where we collapse it.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fetchtube/history.dart';
import 'package:fetchtube/settings.dart';
import 'package:fetchtube/ytdlp.dart';

void main() {
  // Captured from yt-dlp 2026.07.04 on-device. Guards against schema drift and against
  // the real-world messiness synthetic fixtures miss (fractional bitrates, storyboards).
  group('real yt-dlp output', () {
    late MediaInfo info;
    setUpAll(() {
      final raw = File('test/fixtures/believer_info.json').readAsStringSync();
      info = MediaInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    });

    test('collapses 33 raw formats to one row per quality', () {
      expect(info.title, contains('Believer'));
      expect(info.duration, const Duration(seconds: 217));
      expect(info.video.map((f) => f.height), [1080, 720, 480, 360, 240, 144]);
    });

    test('storyboards never appear as video qualities', () {
      // sb0..sb3 carry heights (180/90/45/27) but vcodec "none".
      expect(info.video.map((f) => f.height), isNot(contains(180)));
      expect(info.video.every((f) => f.hasVideo), isTrue);
    });

    test('fractional bitrates render as whole numbers', () {
      // Source has 130.329 / 129.5 / 49.593 / 48.811 kbps.
      expect(info.audio, isNotEmpty);
      for (final f in info.audio) {
        expect(f.label, matches(RegExp(r'^\d+kbps · [A-Z0-9]+$')));
      }
    });
  });

  // Every string here is an error actually observed on-device.
  group('error messages', () {
    test('a stale link is not reported as a network outage', () {
      // yt-dlp nests the real cause inside generic wording; specific must win.
      expect(
        humanizeYtDlpError('ERROR: unable to download video data: HTTP Error 403: Forbidden'),
        contains('expired'),
      );
    });

    test('rate limiting and bot checks are distinguished', () {
      expect(humanizeYtDlpError('HTTP Error 429: Too Many Requests'),
          contains('rate-limiting'));
      expect(
        humanizeYtDlpError("ERROR: Sign in to confirm you're not a bot."),
        contains('automated'),
      );
    });

    test('real connectivity failures still map to no internet', () {
      expect(humanizeYtDlpError('[Errno 7] No address associated with hostname'),
          'No internet connection.');
    });

    test('an unrecognised error keeps yt-dlp own wording, minus the prefix', () {
      expect(humanizeYtDlpError('ERROR: Postprocessing: Conversion failed!'),
          'Postprocessing: Conversion failed!');
    });
  });

  group('default video quality picker', () {
    MediaFormat fmt(int height) =>
        MediaFormat.fromJson({'format_id': '$height', 'height': height, 'ext': 'mp4'});
    final formats = [1080, 720, 480, 360].map(fmt).toList();

    test('"best" picks the top row', () {
      final s = Settings.instance..defaultVideoQuality = 'best';
      expect(s.pickDefaultVideo(formats)!.height, 1080);
    });

    test('a cap picks the nearest row at or below it', () {
      final s = Settings.instance..defaultVideoQuality = '600';
      expect(s.pickDefaultVideo(formats)!.height, 480);
    });

    test('a cap below every row falls back to the lowest, never nothing', () {
      final s = Settings.instance..defaultVideoQuality = '144';
      expect(s.pickDefaultVideo(formats)!.height, 360);
    });

    test('an empty format list yields no crash and no pick', () {
      final s = Settings.instance..defaultVideoQuality = 'best';
      expect(s.pickDefaultVideo([]), isNull);
    });
  });

  group('history', () {
    HistoryEntry entry(String id, {bool audio = false}) => HistoryEntry(
          id: id,
          title: 'Believer',
          uri: 'content://media/external/downloads/$id',
          filename: 'Believer.${audio ? "mp3" : "mp4"}',
          audio: audio,
          bytes: 5488229,
          quality: audio ? '160kbps · M4A' : '1080p · MP4',
          date: DateTime(2026, 7, 26),
        );

    test('survives a JSON round trip', () {
      final restored = HistoryEntry.fromJson(jsonDecode(
          jsonEncode(entry('a').toJson())) as Map<String, dynamic>);
      expect(restored.id, 'a');
      expect(restored.bytes, 5488229);
      expect(restored.date, DateTime(2026, 7, 26));
      expect(restored.subtitle, '1080p · MP4 • 5.2 MB');
    });

    test('a truncated file is discarded instead of crashing', () {
      // Half-written JSON must not brick startup.
      expect(() => jsonDecode('[{"id":"a","tit'), throwsFormatException);
    });

    test('entries split by media type', () {
      final all = [entry('a'), entry('b', audio: true), entry('c', audio: true)];
      expect(all.where((e) => e.audio).length, 2);
      expect(all.where((e) => !e.audio).length, 1);
    });
  });

  group('download progress', () {
    Download event(Map<String, dynamic> over) => Download.fromEvent({
          'id': '1', 'title': 't', 'status': 'running', 'audio': false,
          'progress': 0, 'eta': -1, 'total': -1, 'speed': '', ...over,
        });

    test('received bytes derive from percent and total', () {
      // yt-dlp reports a percentage and a total, never a byte count.
      final d = event({'progress': 50.0, 'total': 1048576});
      expect(d.received, 524288);
      expect(formatBytes(d.received), '512 KB');
    });

    test('unknown total does not fabricate a byte count', () {
      expect(event({'progress': 50.0}).received, -1);
      expect(formatBytes(-1), '');
    });

    test('status drives active/finished', () {
      expect(event({'status': 'converting'}).active, isTrue);
      expect(event({'status': 'done'}).finished, isTrue);
      expect(event({'status': 'failed'}).active, isFalse);
    });
  });

  test('search entries map to results, with derived thumbnail fallback', () {
    final r = SearchResult.fromJson({
      'id': 'abc123',
      'title': 'Believer',
      'channel': 'ImagineDragonsVEVO',
      'duration': 204,
    });
    expect(r.title, 'Believer');
    expect(r.uploader, 'ImagineDragonsVEVO');
    expect(formatDuration(r.duration), '3:24');
    expect(r.url, 'https://www.youtube.com/watch?v=abc123');
    expect(r.thumbnail, contains('abc123'));
  });

  test('formats dedupe per resolution/bitrate, sort desc, and split a/v', () {
    final info = MediaInfo.fromJson({
      'title': 'Believer',
      'formats': [
        // Two codec variants of 1080p must collapse to one row.
        {'format_id': '137', 'ext': 'mp4', 'height': 1080, 'vcodec': 'avc1', 'acodec': 'none'},
        {'format_id': '248', 'ext': 'webm', 'height': 1080, 'vcodec': 'vp9', 'acodec': 'none'},
        {'format_id': '136', 'ext': 'mp4', 'height': 720, 'vcodec': 'avc1', 'acodec': 'none'},
        {'format_id': '140', 'ext': 'm4a', 'abr': 128, 'vcodec': 'none', 'acodec': 'mp4a'},
        {'format_id': '251', 'ext': 'webm', 'abr': 160, 'vcodec': 'none', 'acodec': 'opus'},
      ],
    });
    expect(info.video.map((f) => f.height), [1080, 720]);
    expect(info.audio.map((f) => f.bitrate), [160, 128]);
    expect(info.video.first.label, '1080p · MP4');
    expect(info.audio.first.label, '160kbps · WEBM');
  });

  test('a video-only source yields no invented audio qualities', () {
    final info = MediaInfo.fromJson({
      'title': 'x',
      'formats': [
        {'format_id': '137', 'ext': 'mp4', 'height': 1080, 'vcodec': 'avc1', 'acodec': 'none'},
      ],
    });
    expect(info.audio, isEmpty);
    expect(info.video, hasLength(1));
  });

  test('missing duration and formats degrade instead of throwing', () {
    final info = MediaInfo.fromJson({});
    expect(info.title, 'Untitled');
    expect(formatDuration(info.duration), '');
    expect(info.video, isEmpty);
  });
}
