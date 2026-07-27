import 'package:flutter/material.dart';

import 'downloads.dart';
import 'theme.dart';
import 'ytdlp.dart';

class SearchScreen extends StatefulWidget {
  final bool autofocus;
  const SearchScreen({super.key, this.autofocus = false});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Future<List<SearchResult>>? _results;
  String _query = '';

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
              _results = search(q);
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
          return _Error('${snap.error}',
              onRetry: () => setState(() => _results = search(_query)));
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return _Message('Nothing matched "$_query". Try different words.');
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => _ResultTile(items[i]),
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
                : Image.network(r.thumbnail!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: Theme.of(context).cardColor)),
          ),
        ),
        title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [r.uploader, formatDuration(r.duration)]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          style: kNumericStyle.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DetailsScreen(url: r.url, title: r.title))),
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
  bool _asMp3 = false;

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
              return _Error('${snap.error}',
                  onRetry: () => setState(() => _info = mediaInfo(widget.url)));
            }
            final info = snap.data!;
            return ListView(children: [
              if (info.thumbnail != null)
                Image.network(info.thumbnail!,
                    errorBuilder: (_, _, _) => const SizedBox()),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(info.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    [info.uploader ?? '', formatDuration(info.duration)]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: kNumericStyle.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ]),
              ),
              ..._section(context, info, 'Video', info.video),
              ..._section(context, info, 'Audio', info.audio),
              const SizedBox(height: 24),
            ]);
          },
        ),
      );

  List<Widget> _section(
      BuildContext context, MediaInfo info, String label, List<MediaFormat> formats) {
    if (formats.isEmpty) return const [];
    final audio = label == 'Audio';
    final accent = accentFor(audio: audio);
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
            f.size == null ? '' : formatBytes(f.size!),
            style: kNumericStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => _start(context, info, f, audio),
        ),
    ];
  }

  void _start(BuildContext context, MediaInfo info, MediaFormat f, bool audio) {
    DownloadStore.instance.start(DownloadRequest(
      url: info.url.isEmpty ? widget.url : info.url,
      title: info.title,
      formatId: f.id,
      audioFormat: audio ? (_asMp3 ? 'mp3' : 'best') : null,
      thumbnail: info.thumbnail,
      quality: audio && _asMp3 ? '${f.label} → MP3' : f.label,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to downloads')),
    );
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ),
          ]),
        ),
      );
}
