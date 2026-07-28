import 'package:flutter/material.dart';

import 'downloads.dart';
import 'settings.dart';
import 'theme.dart';
import 'ytdlp.dart';

class SearchScreen extends StatefulWidget {
  final bool autofocus;
  const SearchScreen({super.key, this.autofocus = false});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

// yt-dlp's ytsearchN has no offset — "more results" means re-querying with a
// bigger N. Each step doubles the ask so a long scroll doesn't turn into one
// request per few rows.
const _pageSize = 20;

class _SearchScreenState extends State<SearchScreen> {
  Future<List<SearchResult>>? _results;
  String _query = '';
  int _limit = _pageSize;
  bool _loadingMore = false;
  bool _hasMore = true;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || _query.isEmpty) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final next = _limit + _pageSize;
    try {
      final results = await search(_query, limit: next);
      if (!mounted) return;
      setState(() {
        _limit = next;
        _hasMore = results.length >= next; // fewer than asked means we hit the end
        _results = Future.value(results);
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: TextField(
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search videos and music',
          border: InputBorder.none,
        ),
        onSubmitted: (q) => setState(() {
          _query = q;
          _limit = _pageSize;
          _hasMore = true;
          _results = search(q, limit: _limit);
        }),
      ),
    ),
    body: _body(),
  );

  Widget _body() {
    if (_results == null) {
      return const _Message('Type what you are looking for.');
    }
    return FutureBuilder<List<SearchResult>>(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Error(
            '${snap.error}',
            onRetry: () => setState(() => _results = search(_query, limit: _limit)),
          );
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return _Message('Nothing matched "$_query". Try different words.');
        }
        return ListView.builder(
          controller: _scroll,
          itemCount: items.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= items.length) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _ResultTile(items[i]);
          },
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchResult r;
  const _ResultTile(this.r);

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        height: 56,
        child: r.thumbnail == null
            ? Container(color: Theme.of(context).cardColor)
            : Image.network(
                r.thumbnail!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Container(color: Theme.of(context).cardColor),
              ),
      ),
    ),
    title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        r.uploader,
        formatDuration(r.duration),
      ].where((s) => s.isNotEmpty).join(' · '),
      style: kNumericStyle.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(url: r.url, title: r.title),
      ),
    ),
  );
}

class DetailsScreen extends StatefulWidget {
  final String url, title;
  const DetailsScreen({super.key, required this.url, required this.title});
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late Future<MediaInfo> _info = mediaInfo(widget.url);
  // Settings > Default audio quality decides the starting position of the toggle;
  // the user can still switch it per-download.
  bool _asMp3 = Settings.instance.defaultAudioQuality == 'mp3';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title, maxLines: 1)),
    body: FutureBuilder<MediaInfo>(
      future: _info,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Error(
            '${snap.error}',
            onRetry: () => setState(() => _info = mediaInfo(widget.url)),
          );
        }
        final info = snap.data!;
        return ListView(
          children: [
            if (info.thumbnail != null)
              Image.network(
                info.thumbnail!,
                errorBuilder: (_, _, _) => const SizedBox(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      info.uploader ?? '',
                      formatDuration(info.duration),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: kNumericStyle.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (info.video.isNotEmpty) _quickDownload(context, info),
            ..._section(context, info, 'Video', info.video),
            ..._section(context, info, 'Audio', info.audio),
            const SizedBox(height: 24),
          ],
        );
      },
    ),
  );

  /// One tap using Settings > Default video quality, so that setting does something
  /// concrete rather than just existing on a page nobody revisits.
  Widget _quickDownload(BuildContext context, MediaInfo info) {
    final pick = Settings.instance.pickDefaultVideo(info.video);
    if (pick == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: FilledButton.icon(
        onPressed: () => _start(context, info, pick, false),
        icon: const Icon(Icons.download),
        label: Text('Download (${pick.label})'),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    MediaInfo info,
    String label,
    List<MediaFormat> formats,
  ) {
    if (formats.isEmpty) return const [];
    final audio = label == 'Audio';
    final accent = accentFor(context, audio: audio);
    return [
      Eyebrow(label),
      // MP3 is a re-encode, so it is an explicit choice rather than a fake quality row.
      if (audio)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Original')),
              ButtonSegment(value: true, label: Text('MP3')),
            ],
            selected: {_asMp3},
            onSelectionChanged: (s) => setState(() => _asMp3 = s.first),
          ),
        ),
      for (final f in formats)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          leading: Icon(Icons.download_outlined, size: 20, color: accent),
          title: Text(f.label),
          trailing: Text(
            // Includes the audio that gets merged in, so this matches the file
            // that actually lands on disk.
            info.mergedSize(f) == null ? '' : formatBytes(info.mergedSize(f)!),
            style: kNumericStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => _start(context, info, f, audio),
        ),
    ];
  }

  void _start(BuildContext context, MediaInfo info, MediaFormat f, bool audio) {
    DownloadStore.instance.start(
      DownloadRequest(
        url: info.url.isEmpty ? widget.url : info.url,
        title: info.title,
        formatId: f.id,
        audioFormat: audio ? (_asMp3 ? 'mp3' : 'best') : null,
        thumbnail: info.thumbnail,
        quality: audio && _asMp3 ? '${f.label} → MP3' : f.label,
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Added to downloads')));
  }
}

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _Error extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _Error(this.message, {this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ),
        ],
      ),
    ),
  );
}
