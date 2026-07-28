import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'history.dart';
import 'theme.dart';
import 'ytdlp.dart';

/// App preferences. Same pattern as History: one small JSON file, read once at
/// launch — no database needed for a dozen scalar values.
class Settings extends ChangeNotifier {
  static final instance = Settings._();
  Settings._();

  ThemeMode themeMode = ThemeMode.dark;
  // yt-dlp format selector height, or "best" for uncapped.
  String defaultVideoQuality = 'best';
  String defaultAudioQuality = 'original'; // 'original' | 'mp3'
  bool wifiOnly = false;
  int concurrentDownloads = 1; // 1..3, enforced by the native download queue
  bool autoRetry = true;
  bool notifyOnComplete = true;

  File? _file;

  Future<void> load() async {
    final dir = await dataDir();
    if (dir.isEmpty) return;
    final file = File('$dir/settings.json');
    _file = file;
    if (!file.existsSync()) return;
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == j['themeMode'],
        orElse: () => ThemeMode.dark,
      );
      defaultVideoQuality = j['defaultVideoQuality'] as String? ?? 'best';
      defaultAudioQuality = j['defaultAudioQuality'] as String? ?? 'original';
      wifiOnly = j['wifiOnly'] as bool? ?? false;
      concurrentDownloads = ((j['concurrentDownloads'] as num?) ?? 1)
          .toInt()
          .clamp(1, 3);
      autoRetry = j['autoRetry'] as bool? ?? true;
      notifyOnComplete = j['notifyOnComplete'] as bool? ?? true;
    } on FormatException {
      // A truncated write should not brick startup; fall back to defaults.
    }
  }

  Future<void> _save() async {
    notifyListeners();
    final file = _file;
    if (file == null) return;
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'themeMode': themeMode.name,
        'defaultVideoQuality': defaultVideoQuality,
        'defaultAudioQuality': defaultAudioQuality,
        'wifiOnly': wifiOnly,
        'concurrentDownloads': concurrentDownloads,
        'autoRetry': autoRetry,
        'notifyOnComplete': notifyOnComplete,
      }),
    );
    tmp.renameSync(file.path);
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _save();
  }

  void setDefaultVideoQuality(String v) {
    defaultVideoQuality = v;
    _save();
  }

  void setDefaultAudioQuality(String v) {
    defaultAudioQuality = v;
    _save();
  }

  void setWifiOnly(bool v) {
    wifiOnly = v;
    _save();
  }

  void setConcurrentDownloads(int v) {
    concurrentDownloads = v.clamp(1, 3);
    _save();
  }

  void setAutoRetry(bool v) {
    autoRetry = v;
    _save();
  }

  void setNotifyOnComplete(bool v) {
    notifyOnComplete = v;
    _save();
  }

  /// Picks the row closest to the saved default without exceeding it, or the
  /// first (highest) row if nothing is small enough — never invents a quality.
  MediaFormat? pickDefaultVideo(List<MediaFormat> formats) {
    if (formats.isEmpty) return null;
    if (defaultVideoQuality == 'best') return formats.first;
    final cap = int.tryParse(defaultVideoQuality);
    if (cap == null) return formats.first;
    return formats.firstWhere(
      (f) => (f.height ?? 0) <= cap,
      orElse: () => formats.last,
    );
  }
}

const _videoQualities = ['best', '2160', '1440', '1080', '720', '480', '360'];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings', style: kWordmarkStyle)),
    body: ListenableBuilder(
      listenable: Listenable.merge([Settings.instance, History.instance]),
      builder: (context, _) => ListView(
        children: [
          const Eyebrow('Downloads'),
          const ListTile(
            title: Text('Download location'),
            subtitle: Text('Download/FetchTube'),
          ),
          _qualityTile(context),
          _audioQualityTile(context),
          SwitchListTile(
            title: const Text('Wi-Fi only'),
            subtitle: const Text("Don't start downloads on mobile data"),
            value: Settings.instance.wifiOnly,
            onChanged: Settings.instance.setWifiOnly,
          ),
          const Eyebrow('Queue'),
          _concurrencyTile(context),
          SwitchListTile(
            title: const Text('Auto retry'),
            subtitle: const Text('Try once more if a download fails'),
            value: Settings.instance.autoRetry,
            onChanged: Settings.instance.setAutoRetry,
          ),
          SwitchListTile(
            title: const Text('Notifications'),
            subtitle: const Text('Notify when a download finishes'),
            value: Settings.instance.notifyOnComplete,
            onChanged: Settings.instance.setNotifyOnComplete,
          ),
          const Eyebrow('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {Settings.instance.themeMode},
              onSelectionChanged: (s) =>
                  Settings.instance.setThemeMode(s.first),
            ),
          ),
          const Eyebrow('Storage'),
          const _StorageTile(),
          ListTile(
            title: const Text('Clear history'),
            subtitle: const Text(
              'Forgets the list below — files on disk stay put',
            ),
            onTap: () => _confirmClearHistory(context),
          ),
          const Eyebrow('About'),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Searching, extracting and converting all happen on this device. '
              'Nothing you download is sent anywhere.',
            ),
          ),
          FutureBuilder<String>(
            future: appVersion(),
            builder: (context, snap) => ListTile(
              title: const Text('FetchTube version'),
              subtitle: Text(snap.data ?? '…'),
            ),
          ),
          FutureBuilder<String>(
            future: ytDlpVersion(),
            builder: (context, snap) => ListTile(
              title: const Text('Extractor'),
              subtitle: Text(snap.hasData ? 'yt-dlp ${snap.data}' : '…'),
            ),
          ),
          ListTile(
            title: const Text('Open-source licenses'),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'FetchTube'),
          ),
          ListTile(
            title: const Text('Made by Waqar Azeem'),
            subtitle: const Text('github.com/waqarazeem17'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openUrl('https://github.com/waqarazeem17'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  Widget _qualityTile(BuildContext context) => ListTile(
    title: const Text('Default video quality'),
    subtitle: Text(_qualityLabel(Settings.instance.defaultVideoQuality)),
    onTap: () => _pickQuality(context),
  );

  static String _qualityLabel(String v) =>
      v == 'best' ? 'Best available' : '${v}p';

  Future<void> _pickQuality(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final q in _videoQualities)
              ListTile(
                title: Text(_qualityLabel(q)),
                trailing: q == Settings.instance.defaultVideoQuality
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, q),
              ),
          ],
        ),
      ),
    );
    if (picked != null) Settings.instance.setDefaultVideoQuality(picked);
  }

  Widget _audioQualityTile(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Row(
      children: [
        const Expanded(child: Text('Default audio quality')),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'original', label: Text('Original')),
            ButtonSegment(value: 'mp3', label: Text('MP3')),
          ],
          selected: {Settings.instance.defaultAudioQuality},
          onSelectionChanged: (s) =>
              Settings.instance.setDefaultAudioQuality(s.first),
        ),
      ],
    ),
  );

  Widget _concurrencyTile(BuildContext context) => ListTile(
    title: const Text('Concurrent downloads'),
    subtitle: Text('${Settings.instance.concurrentDownloads} at a time'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: Settings.instance.concurrentDownloads > 1
              ? () => Settings.instance.setConcurrentDownloads(
                  Settings.instance.concurrentDownloads - 1,
                )
              : null,
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: Settings.instance.concurrentDownloads < 3
              ? () => Settings.instance.setConcurrentDownloads(
                  Settings.instance.concurrentDownloads + 1,
                )
              : null,
        ),
      ],
    ),
  );

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This forgets your download history. It does not delete any files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await History.instance.clear();
  }
}

class _StorageTile extends StatelessWidget {
  const _StorageTile();

  @override
  Widget build(BuildContext context) {
    final videoBytes = History.instance.bytesOf(audio: false);
    final audioBytes = History.instance.bytesOf(audio: true);
    return ListTile(
      title: const Text('Used space'),
      subtitle: Text(
        '${formatBytes(videoBytes)} videos · ${formatBytes(audioBytes)} music',
      ),
      trailing: Text(
        formatBytes(videoBytes + audioBytes),
        style: kNumericStyle,
      ),
    );
  }
}
