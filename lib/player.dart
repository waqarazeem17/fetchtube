import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'history.dart';
import 'theme.dart';
import 'ytdlp.dart';

/// Plays a saved file in-app. Audio and video share one controller: ExoPlayer
/// handles both, so an audio track is just a video with nothing to draw.
///
/// ponytail: foreground playback only. Audio stops when the app is backgrounded —
/// continuing needs a MediaSession and its own service, which is a bigger piece of
/// work than the rest of this screen combined.
class PlayerScreen extends StatefulWidget {
  final HistoryEntry entry;
  const PlayerScreen({super.key, required this.entry});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _fullscreen = false;
  bool _showControls = true;
  double _volume = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.contentUri(Uri.parse(widget.entry.uri));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      if (!mounted) return;
      // Usually the file was deleted outside the app, or the codec is unsupported.
      setState(() => _error = 'This file could not be played.');
    });
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    // Leaving fullscreen on the way out, otherwise the rest of the app stays landscape.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              title: Text(e.title, maxLines: 1, style: const TextStyle(fontSize: 16)),
            ),
      body: SafeArea(
        top: !_fullscreen,
        child: _error != null ? _errorView() : _player(),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => openFile(widget.entry.uri),
              child: const Text('Open with another app'),
            ),
          ]),
        ),
      );

  Widget _player() {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: Center(child: _stage()),
        ),
      ),
      if (_showControls) _controls(),
    ]);
  }

  /// Video draws itself; audio has nothing to show, so the artwork stands in.
  Widget _stage() {
    if (!widget.entry.audio) {
      return AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      );
    }
    final accent = accentFor(audio: true);
    final thumb = widget.entry.thumbnail;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: thumb == null
              ? Container(
                  color: accent.withValues(alpha: 0.14),
                  child: Icon(Icons.music_note, color: accent, size: 64),
                )
              : Image.network(thumb,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                        color: accent.withValues(alpha: 0.14),
                        child: Icon(Icons.music_note, color: accent, size: 64),
                      )),
        ),
      ),
    );
  }

  Widget _controls() {
    final v = _controller.value;
    final accent = accentFor(audio: widget.entry.audio);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Built-in scrubber: dragging seeks, so no custom slider needed.
        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          colors: VideoProgressColors(
            playedColor: accent,
            bufferedColor: Colors.white24,
            backgroundColor: Colors.white12,
          ),
        ),
        Row(children: [
          Text(formatDuration(v.position), style: kNumericStyle),
          const Spacer(),
          Text(formatDuration(v.duration), style: kNumericStyle),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            iconSize: 44,
            color: accent,
            icon: Icon(v.isPlaying ? Icons.pause_circle : Icons.play_circle),
            tooltip: v.isPlaying ? 'Pause' : 'Play',
            onPressed: () => setState(
                () => v.isPlaying ? _controller.pause() : _controller.play()),
          ),
          IconButton(
            icon: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up),
            tooltip: _volume == 0 ? 'Unmute' : 'Mute',
            onPressed: () => _setVolume(_volume == 0 ? 1 : 0),
          ),
          Expanded(
            child: Slider(
              value: _volume,
              activeColor: accent,
              onChanged: _setVolume,
            ),
          ),
          if (!widget.entry.audio)
            IconButton(
              icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
              tooltip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onPressed: _toggleFullscreen,
            ),
        ]),
      ]),
    );
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    _controller.setVolume(value);
  }
}
