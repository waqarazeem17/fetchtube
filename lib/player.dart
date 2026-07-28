import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:video_player/video_player.dart';

import 'history.dart';
import 'theme.dart';
import 'ytdlp.dart';

/// Plays a saved file in-app.
///
/// Two engines on purpose. Music has to keep playing once the app is backgrounded,
/// which needs a MediaSession and a mediaPlayback foreground service — just_audio
/// (+ just_audio_background) provides both. Video has no such requirement and stays
/// on video_player, which can actually draw frames.
class PlayerScreen extends StatelessWidget {
  final HistoryEntry entry;
  const PlayerScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) =>
      entry.audio ? _AudioPlayer(entry: entry) : _VideoPlayer(entry: entry);
}

/// Shared chrome so both players look identical apart from the stage.
class _PlayerScaffold extends StatelessWidget {
  final HistoryEntry entry;
  final Widget stage;
  final Widget controls;
  final bool fullscreen;
  const _PlayerScaffold({
    required this.entry,
    required this.stage,
    required this.controls,
    this.fullscreen = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: fullscreen
        ? null
        : AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              entry.title,
              maxLines: 1,
              style: const TextStyle(fontSize: 16),
            ),
          ),
    body: SafeArea(
      top: !fullscreen,
      child: Column(
        children: [
          Expanded(child: Center(child: stage)),
          controls,
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String uri;
  const _ErrorView({required this.uri});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This file could not be played.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => openFile(uri),
            child: const Text('Open with another app'),
          ),
        ],
      ),
    ),
  );
}

// ------------------------------------------------------------------ audio

class _AudioPlayer extends StatefulWidget {
  final HistoryEntry entry;
  const _AudioPlayer({required this.entry});

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  final _player = AudioPlayer();
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // The MediaItem tag is what populates the lockscreen/notification, and
      // just_audio_background requires it on every source.
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(widget.entry.uri),
          tag: MediaItem(
            id: widget.entry.id,
            title: widget.entry.title,
            artUri: widget.entry.thumbnail == null
                ? null
                : Uri.parse(widget.entry.thumbnail!),
          ),
        ),
      );
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _PlayerScaffold(
        entry: widget.entry,
        stage: _ErrorView(uri: widget.entry.uri),
        controls: const SizedBox.shrink(),
      );
    }
    final accent = accentFor(context, audio: true);
    return _PlayerScaffold(
      entry: widget.entry,
      stage: _Artwork(entry: widget.entry, accent: accent),
      controls: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, snap) {
          final playing = snap.data?.playing ?? false;
          return _Controls(
            accent: accent,
            playing: playing,
            positionStream: _player.positionStream,
            duration: _player.duration ?? Duration.zero,
            onSeek: _player.seek,
            onPlayPause: () => playing ? _player.pause() : _player.play(),
            onVolume: _player.setVolume,
          );
        },
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final HistoryEntry entry;
  final Color accent;
  const _Artwork({required this.entry, required this.accent});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: accent.withValues(alpha: 0.14),
      child: Icon(Icons.music_note, color: accent, size: 64),
    );
    return Padding(
      padding: const EdgeInsets.all(32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: entry.thumbnail == null
              ? fallback
              : Image.network(
                  entry.thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ video

class _VideoPlayer extends StatefulWidget {
  final HistoryEntry entry;
  const _VideoPlayer({required this.entry});

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _fullscreen = false;
  bool _showControls = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.contentUri(Uri.parse(widget.entry.uri));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _ready = true);
          _controller.play();
        })
        .catchError((Object e) {
          if (!mounted) return;
          // Usually the file was deleted outside the app, or the codec is unsupported.
          setState(() => _error = true);
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
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _PlayerScaffold(
        entry: widget.entry,
        stage: _ErrorView(uri: widget.entry.uri),
        controls: const SizedBox.shrink(),
      );
    }
    if (!_ready) {
      return _PlayerScaffold(
        entry: widget.entry,
        stage: const CircularProgressIndicator(),
        controls: const SizedBox.shrink(),
      );
    }
    final accent = accentFor(context, audio: false);
    final v = _controller.value;
    return _PlayerScaffold(
      entry: widget.entry,
      fullscreen: _fullscreen,
      stage: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: AspectRatio(
          aspectRatio: v.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
      controls: !_showControls
          ? const SizedBox.shrink()
          : _Controls(
              accent: accent,
              playing: v.isPlaying,
              position: v.position,
              duration: v.duration,
              onSeek: _controller.seekTo,
              onPlayPause: () => setState(
                () => v.isPlaying ? _controller.pause() : _controller.play(),
              ),
              onVolume: _controller.setVolume,
              onFullscreen: _toggleFullscreen,
              fullscreen: _fullscreen,
            ),
    );
  }
}

// --------------------------------------------------------------- controls

/// One control bar for both engines. Takes either a live [positionStream]
/// (just_audio) or a polled [position] (video_player).
class _Controls extends StatefulWidget {
  final Color accent;
  final bool playing;
  final Stream<Duration>? positionStream;
  final Duration? position;
  final Duration duration;
  final void Function(Duration) onSeek;
  final VoidCallback onPlayPause;
  final void Function(double) onVolume;
  final VoidCallback? onFullscreen;
  final bool fullscreen;

  const _Controls({
    required this.accent,
    required this.playing,
    required this.duration,
    required this.onSeek,
    required this.onPlayPause,
    required this.onVolume,
    this.positionStream,
    this.position,
    this.onFullscreen,
    this.fullscreen = false,
  });

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  double _volume = 1;
  // While dragging, the slider follows the finger rather than the player clock.
  double? _scrubbing;

  void _setVolume(double v) {
    setState(() => _volume = v);
    widget.onVolume(v);
  }

  @override
  Widget build(BuildContext context) => widget.positionStream == null
      ? _bar(widget.position ?? Duration.zero)
      : StreamBuilder<Duration>(
          stream: widget.positionStream,
          builder: (context, snap) => _bar(snap.data ?? Duration.zero),
        );

  Widget _bar(Duration position) {
    final total = widget.duration.inMilliseconds;
    final current = _scrubbing ?? position.inMilliseconds.toDouble();
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Slider(
            value: total == 0 ? 0 : current.clamp(0, total.toDouble()),
            max: total == 0 ? 1 : total.toDouble(),
            activeColor: widget.accent,
            onChanged: (v) => setState(() => _scrubbing = v),
            onChangeEnd: (v) {
              widget.onSeek(Duration(milliseconds: v.round()));
              setState(() => _scrubbing = null);
            },
          ),
          Row(
            children: [
              Text(
                formatDuration(Duration(milliseconds: current.round())),
                style: kNumericStyle.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              Text(
                formatDuration(widget.duration),
                style: kNumericStyle.copyWith(color: Colors.white70),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                iconSize: 44,
                color: widget.accent,
                icon: Icon(
                  widget.playing ? Icons.pause_circle : Icons.play_circle,
                ),
                tooltip: widget.playing ? 'Pause' : 'Play',
                onPressed: widget.onPlayPause,
              ),
              IconButton(
                color: Colors.white70,
                icon: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up),
                tooltip: _volume == 0 ? 'Unmute' : 'Mute',
                onPressed: () => _setVolume(_volume == 0 ? 1 : 0),
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  activeColor: widget.accent,
                  onChanged: _setVolume,
                ),
              ),
              if (widget.onFullscreen != null)
                IconButton(
                  color: Colors.white70,
                  icon: Icon(
                    widget.fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                  ),
                  tooltip: widget.fullscreen
                      ? 'Exit fullscreen'
                      : 'Fullscreen',
                  onPressed: widget.onFullscreen,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
