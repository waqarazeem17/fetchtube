import 'package:flutter/material.dart';
import 'history.dart';
import 'player.dart';
import 'theme.dart';
import 'ytdlp.dart';

/// Holds download state for the whole app. The native side is the source of truth;
/// this just mirrors its events so the list survives navigating away from the screen.
class DownloadStore extends ChangeNotifier {
  static final instance = DownloadStore._();

  DownloadStore._() {
    downloadEvents().listen((d) {
      _order.remove(d.id);
      _order.insert(0, d.id);
      _items[d.id] = d;
      if (d.finished && d.uri != null) _record(d);
      notifyListeners();
    });
  }

  /// Completed downloads move into history so they survive a restart.
  Future<void> _record(Download d) async {
    final request = _requests[d.id];
    await History.instance.add(HistoryEntry(
      id: d.id,
      title: d.title,
      uri: d.uri!,
      filename: d.filename ?? d.title,
      thumbnail: request?.thumbnail,
      quality: request?.quality,
      source: request?.url,
      audio: d.audio,
      bytes: d.bytes,
      date: DateTime.now(),
    ));
    notifyListeners();
  }

  final _items = <String, Download>{};
  final _order = <String>[];
  // Kept Dart-side so retry/resume can re-issue the original request.
  final _requests = <String, DownloadRequest>{};

  List<Download> get all => [
        for (final id in _order)
          if (_items[id] != null) _items[id]!,
      ];

  int get activeCount => _items.values.where((d) => d.active).length;

  Future<void> start(DownloadRequest request) async {
    final id = await startDownload(request);
    _requests[id] = request;
  }

  Future<void> retry(Download d) async {
    final request = _requests[d.id];
    if (request != null) await resumeDownload(d.id, request);
  }

  Future<void> cancel(Download d) async {
    await cancelDownload(d.id);
    _items.remove(d.id);
    _order.remove(d.id);
    _requests.remove(d.id);
    notifyListeners();
  }

  /// Removes the file and its history row. Returns false if the file was already gone.
  Future<bool> deleteSaved(HistoryEntry entry) async {
    final ok = await deleteFile(entry.uri);
    await History.instance.remove(entry.id);
    _items.remove(entry.id);
    _order.remove(entry.id);
    notifyListeners();
    return ok;
  }
}

class DownloadsScreen extends StatelessWidget {
  /// Which tab to land on — set by the home screen's quick access tiles.
  final bool initialAudio;
  const DownloadsScreen({super.key, this.initialAudio = false});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: initialAudio ? 1 : 0,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Library', style: kWordmarkStyle),
            bottom: const TabBar(
              tabs: [Tab(text: 'Videos'), Tab(text: 'Music')],
              indicatorSize: TabBarIndicatorSize.tab,
            ),
          ),
          body: ListenableBuilder(
            listenable: DownloadStore.instance,
            builder: (context, _) => TabBarView(
              children: [_tab(audio: false), _tab(audio: true)],
            ),
          ),
        ),
      );

  Widget _tab({required bool audio}) {
    // In-flight transfers first, then what is already on disk.
    final active =
        DownloadStore.instance.all.where((d) => d.audio == audio && !d.finished);
    final saved = History.instance.where(audio: audio);
    if (active.isEmpty && saved.isEmpty) {
      return Center(child: Text('No ${audio ? "music" : "videos"} yet.'));
    }
    return ListView(children: [
      for (final d in active) _DownloadTile(d),
      if (active.isNotEmpty && saved.isNotEmpty) const Divider(height: 1),
      for (final e in saved) _SavedTile(e),
    ]);
  }
}

/// A file already saved to Download/FetchTube.
class _SavedTile extends StatelessWidget {
  final HistoryEntry e;
  const _SavedTile(this.e);

  @override
  Widget build(BuildContext context) => ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 44,
            child: e.thumbnail == null
                ? _placeholder(e)
                : Image.network(e.thumbnail!,
                    fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(e)),
          ),
        ),
        title: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          e.subtitle,
          style: kNumericStyle.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => _play(context),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'play' => _play(context),
            'open' => _open(context),
            'share' => shareFile(e.uri),
            'info' => _info(context),
            _ => _delete(context),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'play', child: Text('Play')),
            PopupMenuItem(value: 'open', child: Text('Open with…')),
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'info', child: Text('File information')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      );

  Widget _placeholder(HistoryEntry e) {
    final accent = accentFor(audio: e.audio);
    return Container(
      color: accent.withValues(alpha: 0.14),
      child: Icon(e.audio ? Icons.music_note : Icons.movie_outlined,
          color: accent, size: 18),
    );
  }

  void _play(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerScreen(entry: e)),
      );

  /// Hand off to whatever the user already uses for media.
  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await openFile(e.uri);
    } on YtDlpException catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  void _info(BuildContext context) => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('File information'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _row('Name', e.filename),
            _row('Type', e.audio ? 'Audio' : 'Video'),
            if (e.quality != null) _row('Quality', e.quality!),
            if (e.bytes > 0) _row('Size', formatBytes(e.bytes)),
            _row('Saved', '${e.date}'.split('.').first),
            _row('Folder', 'Download/FetchTube/${e.audio ? "Music" : "Videos"}'),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  static Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ]),
      );

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(e.filename),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await DownloadStore.instance.deleteSaved(e);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('File was already removed.')),
      );
    }
  }
}

class _DownloadTile extends StatelessWidget {
  final Download d;
  const _DownloadTile(this.d);

  @override
  Widget build(BuildContext context) {
    final store = DownloadStore.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(d.audio ? Icons.music_note : Icons.movie, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ..._actions(context, store),
        ]),
        const SizedBox(height: 8),
        if (d.active) ...[
          LinearProgressIndicator(value: d.progress <= 0 ? null : d.progress / 100),
          const SizedBox(height: 6),
          Text(_subtitle(), style: Theme.of(context).textTheme.bodySmall),
        ] else
          Text(_subtitle(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: d.status == 'failed'
                        ? Theme.of(context).colorScheme.error
                        : null,
                  )),
      ]),
    );
  }

  String _subtitle() {
    switch (d.status) {
      case 'converting':
        return 'Converting…';
      case 'queued':
        return 'Queued';
      case 'paused':
        return 'Paused · ${d.progress.toStringAsFixed(0)}%';
      case 'done':
        return 'Saved${d.total > 0 ? " · ${formatBytes(d.total)}" : ""}';
      case 'failed':
        return d.error ?? 'Download failed';
      default:
        final size = d.total > 0
            ? '${formatBytes(d.received)} / ${formatBytes(d.total)}'
            : '${d.progress.toStringAsFixed(0)}%';
        final eta = d.eta > 0 ? ' · ETA ${formatDuration(Duration(seconds: d.eta))}' : '';
        return '$size${d.speed.isEmpty ? "" : " · ${d.speed}"}$eta';
    }
  }

  List<Widget> _actions(BuildContext context, DownloadStore store) => switch (d.status) {
        'running' || 'queued' => [
            IconButton(
              icon: const Icon(Icons.pause),
              tooltip: 'Pause',
              onPressed: () => pauseDownload(d.id),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onPressed: () => store.cancel(d),
            ),
          ],
        'paused' || 'failed' => [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: d.status == 'paused' ? 'Resume' : 'Retry',
              onPressed: () => store.retry(d),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
              onPressed: () => store.cancel(d),
            ),
          ],
        _ => const [],
      };
}
