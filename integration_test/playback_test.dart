// Verifies the two playback engines against a real file on the device.
//
// The audio path uses just_audio + just_audio_background (so music survives the
// app being backgrounded); the video path uses video_player. Both are driven
// here directly rather than through the UI, because tapping coordinates on an
// emulator proved far less reliable than calling the same APIs the screens do.
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:fetchtube/ytdlp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';

const _video = 'https://www.youtube.com/watch?v=7wtfhZwyrcc';

const _opts = QueueOptions(
  wifiOnly: false,
  autoRetry: true,
  notifyOnComplete: false,
  maxConcurrent: 1,
);

Future<Download> _settle(String id) => downloadEvents()
    .where((d) => d.id == id && (d.status == 'done' || d.status == 'failed'))
    .first
    .timeout(const Duration(minutes: 6));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.fetchtube.fetchtube.playback',
      androidNotificationChannelName: 'Playback',
    );
  });

  testWidgets('audio plays, seeks and reports position', (tester) async {
    final id = await startDownload(
      const DownloadRequest(url: _video, title: 'bg audio', audioFormat: 'mp3'),
      _opts,
    );
    final saved = await _settle(id);
    expect(saved.status, 'done', reason: saved.error ?? '');

    final player = AudioPlayer();
    addTearDown(player.dispose);

    // The MediaItem tag is what drives the lockscreen notification; without it
    // just_audio_background throws, so this also asserts the wiring is right.
    final duration = await player.setAudioSource(
      AudioSource.uri(
        Uri.parse(saved.uri!),
        tag: MediaItem(id: id, title: 'bg audio'),
      ),
    );
    expect(duration, isNotNull, reason: 'could not read the saved audio file');
    expect(duration!.inSeconds, greaterThan(60));

    await player.play();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(player.playing, isTrue);
    expect(player.position.inMilliseconds, greaterThan(0));

    // Seek near the end, then confirm the clock actually moved there.
    final target = duration - const Duration(seconds: 10);
    await player.seek(target);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      (player.position - target).inSeconds.abs(),
      lessThan(5),
      reason: 'seek did not take effect',
    );

    await player.pause();
    expect(player.playing, isFalse);
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('video plays and seeks', (tester) async {
    final info = await mediaInfo(_video);
    final smallest = info.video.last;
    final id = await startDownload(
      DownloadRequest(
        url: _video,
        title: 'video playback',
        formatId: smallest.id,
      ),
      _opts,
    );
    final saved = await _settle(id);
    expect(saved.status, 'done', reason: saved.error ?? '');

    final controller = VideoPlayerController.contentUri(Uri.parse(saved.uri!));
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(controller.value.isInitialized, isTrue);
    expect(controller.value.duration.inSeconds, greaterThan(0));
    // A real video track, not an audio file that happens to open.
    expect(controller.value.size.width, greaterThan(0));

    await controller.play();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(controller.value.isPlaying, isTrue);

    final target = const Duration(seconds: 30) < controller.value.duration
        ? const Duration(seconds: 30)
        : Duration(seconds: controller.value.duration.inSeconds ~/ 2);
    await controller.seekTo(target);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(
      (controller.value.position - target).inSeconds.abs(),
      lessThan(5),
      reason: 'seek did not take effect',
    );

    await controller.pause();
    expect(controller.value.isPlaying, isFalse);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
