import 'package:flutter/material.dart';

import 'downloads.dart';
import 'history.dart';
import 'player.dart';
import 'search.dart';
import 'settings.dart';
import 'theme.dart';
import 'ytdlp.dart';

class HomeScreen extends StatelessWidget {
  /// Opens the library on the Music or Videos tab.
  final void Function({required bool audio}) onOpenLibrary;
  final VoidCallback onOpenDownloads;

  const HomeScreen({
    super.key,
    required this.onOpenLibrary,
    required this.onOpenDownloads,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('FetchTube', style: kWordmarkStyle),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    ),
    body: ListenableBuilder(
      // History changes when a download finishes, which changes the tile counts.
      listenable: DownloadStore.instance,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SearchEntry(),
          const Eyebrow('Quick access'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _LibraryTile(
                    audio: false,
                    onTap: () => onOpenLibrary(audio: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LibraryTile(
                    audio: true,
                    onTap: () => onOpenLibrary(audio: true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _DownloadsRow(onTap: onOpenDownloads),
          ),
          const Eyebrow('Recent downloads'),
          // Built here, not as a const child: a const widget reading History would
          // never rebuild when a download finishes.
          _Recent(entries: History.instance.all.take(4).toList()),
        ],
      ),
    ),
  );
}

/// Tapping anywhere here opens the search screen with the keyboard already up.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SearchScreen(autofocus: true),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(
                  'Search videos and music',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows what is actually on the device for one media type — the one thing a local
/// downloader can say that a web tool cannot.
class _LibraryTile extends StatelessWidget {
  final bool audio;
  final VoidCallback onTap;
  const _LibraryTile({required this.audio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(context, audio: audio);
    final count = History.instance.countOf(audio: audio);
    final bytes = History.instance.bytesOf(audio: audio);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  audio ? Icons.music_note : Icons.movie_outlined,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                audio ? 'Music' : 'Videos',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                count == 0
                    ? 'Nothing yet'
                    : '$count file${count == 1 ? "" : "s"} · ${formatBytes(bytes)}',
                style: kNumericStyle.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Activity rather than library, so it gets a row instead of a tile.
class _DownloadsRow extends StatelessWidget {
  final VoidCallback onTap;
  const _DownloadsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = DownloadStore.instance.activeCount;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(
                Icons.download_outlined,
                size: 22,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Downloads',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                active == 0 ? 'Idle' : '$active in progress',
                style: kNumericStyle.copyWith(
                  color: active == 0 ? scheme.onSurfaceVariant : kVideoAccent,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  final List<HistoryEntry> entries;
  const _Recent({required this.entries});

  @override
  Widget build(BuildContext context) {
    final recent = entries;
    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(
          'Nothing saved yet. Search for something to download.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(children: [for (final e in recent) _RecentTile(e)]);
  }
}

class _RecentTile extends StatelessWidget {
  final HistoryEntry e;
  const _RecentTile(this.e);

  @override
  Widget build(BuildContext context) {
    final accent = accentFor(context, audio: e.audio);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 44,
          child: e.thumbnail == null
              ? Container(
                  color: accent.withValues(alpha: 0.14),
                  child: Icon(
                    e.audio ? Icons.music_note : Icons.movie_outlined,
                    color: accent,
                    size: 18,
                  ),
                )
              : Image.network(
                  e.thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: accent.withValues(alpha: 0.14),
                    child: Icon(
                      e.audio ? Icons.music_note : Icons.movie_outlined,
                      color: accent,
                      size: 18,
                    ),
                  ),
                ),
        ),
      ),
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        e.subtitle,
        style: kNumericStyle.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PlayerScreen(entry: e)),
      ),
    );
  }
}
