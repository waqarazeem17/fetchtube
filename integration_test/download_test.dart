// Runs on a real device/emulator. Exercises the whole native path:
// MethodChannel -> DownloadService -> yt-dlp -> ffmpeg -> MediaStore.
// Needs network; downloads the smallest available format to stay quick.
import 'package:fetchtube/history.dart';
import 'package:fetchtube/ytdlp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _video = 'https://www.youtube.com/watch?v=7wtfhZwyrcc';

const _opts = QueueOptions(
  wifiOnly: false,
  autoRetry: false,
  notifyOnComplete: true,
  maxConcurrent: 1,
);

/// Waits for [id] to reach a terminal state, returning the last event seen.
Future<Download> _settle(String id, {Duration timeout = const Duration(minutes: 5)}) {
  return downloadEvents()
      .where((d) => d.id == id)
      .where((d) => d.status == 'done' || d.status == 'failed')
      .first
      .timeout(timeout);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('metadata: real formats come back', (tester) async {
    final info = await mediaInfo(_video);
    expect(info.title, isNotEmpty);
    expect(info.video, isNotEmpty, reason: 'no video formats — extraction is broken');
    expect(info.audio, isNotEmpty, reason: 'no audio formats — extraction is broken');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('video downloads, merges and lands in MediaStore', (tester) async {
    final info = await mediaInfo(_video);
    final smallest = info.video.last; // lowest resolution keeps the test quick
    final id = await startDownload(
      DownloadRequest(url: _video, title: info.title, formatId: smallest.id),
      _opts,
    );

    final result = await _settle(id);
    expect(result.status, 'done', reason: result.error ?? '');
    expect(result.uri, startsWith('content://'),
        reason: 'file never reached MediaStore');
  }, timeout: const Timeout(Duration(minutes: 6)));

  // Pause kills the yt-dlp process and resume re-runs it; correctness depends on
  // --continue picking up the .part file rather than restarting from zero.
  testWidgets('pause stops the transfer and resume finishes it', (tester) async {
    final info = await mediaInfo(_video);
    final biggest = info.video.first; // big enough that we can interrupt mid-flight
    final request = DownloadRequest(
      url: _video,
      title: info.title,
      formatId: biggest.id,
    );
    final id = await startDownload(request, _opts);

    // Wait until bytes are actually moving, then pause.
    await downloadEvents()
        .where((d) => d.id == id && d.status == 'running' && d.progress > 0)
        .first
        .timeout(const Duration(minutes: 2));
    // Arm the listener before acting: downloadEvents() is a broadcast stream, so an
    // event fired before we subscribe is gone for good.
    final pausedEvent = downloadEvents()
        .where((d) => d.id == id && d.status == 'paused')
        .first
        .timeout(const Duration(seconds: 60));
    await pauseDownload(id);
    final paused = await pausedEvent;
    expect(paused.progress, greaterThan(0));

    final settled = _settle(id);
    await resumeDownload(id, request, _opts);
    final result = await settled;
    expect(result.status, 'done', reason: result.error ?? '');
    expect(result.uri, startsWith('content://'));
  }, timeout: const Timeout(Duration(minutes: 8)));

  // The whole user journey: type a query, pick a result, save it as a song, and
  // still have it listed after a restart.
  testWidgets('search a song, download it, and find it in history', (tester) async {
    final results = await search('Imagine Dragons Believer', limit: 5);
    expect(results, isNotEmpty, reason: 'search returned nothing');
    final track = results.first;
    expect(track.title, isNotEmpty);
    expect(track.url, contains('youtube.com'));

    final info = await mediaInfo(track.url);
    expect(info.audio, isNotEmpty);

    final id = await startDownload(
      DownloadRequest(
        url: track.url,
        title: track.title,
        audioFormat: 'mp3',
        thumbnail: track.thumbnail,
        quality: '${info.audio.first.label} -> MP3',
      ),
      _opts,
    );
    final result = await _settle(id);
    expect(result.status, 'done', reason: result.error ?? '');
    expect(result.filename, endsWith('.mp3'));
    expect(result.bytes, greaterThan(100000), reason: 'suspiciously small song');

    // Persist, then reload from disk the way a cold start would.
    await History.instance.load();
    await History.instance.add(HistoryEntry(
      id: id,
      title: track.title,
      uri: result.uri!,
      filename: result.filename!,
      audio: true,
      bytes: result.bytes,
      date: DateTime.now(),
    ));

    final reloaded = History.instance;
    await reloaded.load();
    final saved = reloaded.where(audio: true).where((e) => e.id == id);
    expect(saved, hasLength(1), reason: 'history did not survive a reload');
    expect(saved.first.filename, endsWith('.mp3'));
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('audio extracts to mp3', (tester) async {
    final id = await startDownload(
      const DownloadRequest(url: _video, title: 'audio test', audioFormat: 'mp3'),
      _opts,
    );
    final result = await _settle(id);
    expect(result.status, 'done', reason: result.error ?? '');
    expect(result.uri, startsWith('content://'));
  }, timeout: const Timeout(Duration(minutes: 6)));
}
