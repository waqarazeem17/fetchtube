import 'package:flutter/material.dart';
import 'downloads.dart';
import 'history.dart';
import 'ytdlp.dart';

void main() async {
  // The store opens an EventChannel, which needs the binding to exist first.
  WidgetsFlutterBinding.ensureInitialized();
  DownloadStore.instance; // subscribe to native events before any UI can start one.
  await History.instance.load();
  runApp(const FetchTubeApp());
}

class FetchTubeApp extends StatelessWidget {
  const FetchTubeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FetchTube',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFFE53935),
          brightness: Brightness.dark,
        ),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _tab == 0 ? const SearchScreen() : const DownloadsScreen(),
        bottomNavigationBar: ListenableBuilder(
          listenable: DownloadStore.instance,
          builder: (context, _) {
            final active = DownloadStore.instance.activeCount;
            return NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.search), label: 'Search'),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: active > 0,
                    label: Text('$active'),
                    child: const Icon(Icons.download),
                  ),
                  label: 'Downloads',
                ),
              ],
            );
          },
        ),
      );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Future<List<SearchResult>>? _results;
  String _version = '';

  @override
  void initState() {
    super.initState();
    // Doubles as the smoke test: a version here means python+yt-dlp unpacked and ran.
    ytDlpVersion()
        .then((v) => setState(() => _version = 'yt-dlp $v'))
        .catchError((Object e) => setState(() => _version = 'init failed: $e'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('FetchTube'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Text(_version, style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SearchBar(
              hintText: 'Search videos...',
              leading: const Icon(Icons.search),
              onSubmitted: (q) => setState(() => _results = search(q)),
            ),
          ),
          Expanded(child: _body()),
        ]),
      );

  Widget _body() {
    if (_results == null) return const Center(child: Text('Search for something.'));
    return FutureBuilder<List<SearchResult>>(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _Error('${snap.error}');
        final items = snap.data!;
        if (items.isEmpty) return const Center(child: Text('No results.'));
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: r.thumbnail == null
            ? const Icon(Icons.movie)
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(r.thumbnail!,
                    width: 96,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.movie)),
              ),
        title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([r.uploader, formatDuration(r.duration)]
            .where((s) => s.isNotEmpty)
            .join(' · ')),
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
              ListTile(
                title: Text(info.title),
                subtitle: Text([info.uploader ?? '', formatDuration(info.duration)]
                    .where((s) => s.isNotEmpty)
                    .join(' · ')),
              ),
              ..._section(context, info, 'VIDEO', info.video),
              ..._section(context, info, 'AUDIO', info.audio),
              const SizedBox(height: 24),
            ]);
          },
        ),
      );

  List<Widget> _section(
      BuildContext context, MediaInfo info, String label, List<MediaFormat> formats) {
    if (formats.isEmpty) return const [];
    final audio = label == 'AUDIO';
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
      // MP3 is a re-encode, so it is an explicit choice rather than a fake quality row.
      if (audio)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
          title: Text(f.label),
          trailing: Text(
              f.size == null ? '' : '${(f.size! / 1048576).toStringAsFixed(1)} MB'),
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
                padding: const EdgeInsets.only(top: 12),
                child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ),
          ]),
        ),
      );
}
