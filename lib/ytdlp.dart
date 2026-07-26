import 'dart:convert';
import 'package:flutter/services.dart';

const _channel = MethodChannel('fetchtube/ytdlp');

/// Thrown when yt-dlp fails. [message] is already user-facing.
class YtDlpException implements Exception {
  final String message;
  YtDlpException(this.message);
  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _call(String method, [Map<String, dynamic>? args]) async {
  try {
    final out = await _channel.invokeMethod<String>(method, args);
    return jsonDecode(out!) as Map<String, dynamic>;
  } on PlatformException catch (e) {
    throw YtDlpException(_humanize(e.message ?? ''));
  }
}

/// yt-dlp writes the real reason to stderr; surface it instead of "Error".
String _humanize(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('unable to download') || lower.contains('failed to resolve')) {
    return 'No internet connection.';
  }
  if (lower.contains('private video')) return 'This video is private.';
  if (lower.contains('video unavailable')) return 'This video is unavailable.';
  if (lower.contains('not available in your country')) {
    return 'This video is blocked in your region.';
  }
  if (lower.contains('unsupported url')) return 'That link is not supported.';
  // Both observed on-device: YouTube rate-limits an IP, then demands sign-in.
  if (lower.contains('429') || lower.contains('too many requests')) {
    return 'The source is rate-limiting this network. Try again in a few minutes.';
  }
  if (lower.contains("confirm you're not a bot") ||
      lower.contains('confirm you’re not a bot')) {
    return 'The source blocked this request as automated. '
        'This often happens on VPNs and shared networks.';
  }
  // Keep yt-dlp's own last line — it is usually the most specific thing we have.
  final line = raw.trim().split('\n').lastWhere((l) => l.trim().isNotEmpty, orElse: () => raw);
  return line.replaceFirst(RegExp(r'^ERROR:\s*'), '');
}

Future<String> ytDlpVersion() async {
  try {
    return await _channel.invokeMethod<String>('version') ?? 'unknown';
  } on PlatformException catch (e) {
    throw YtDlpException(_humanize(e.message ?? ''));
  }
}

class SearchResult {
  final String id, title, uploader, url;
  final Duration? duration;
  final String? thumbnail;

  SearchResult.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        title = j['title'] as String? ?? 'Untitled',
        uploader = (j['channel'] ?? j['uploader'] ?? '') as String,
        url = (j['url'] ?? 'https://www.youtube.com/watch?v=${j['id']}') as String,
        duration = j['duration'] == null
            ? null
            : Duration(seconds: (j['duration'] as num).round()),
        thumbnail = _pickThumb(j);

  static String? _pickThumb(Map<String, dynamic> j) {
    final thumbs = j['thumbnails'] as List?;
    if (thumbs != null && thumbs.isNotEmpty) {
      return (thumbs.first as Map)['url'] as String?;
    }
    final id = j['id'];
    return id == null ? null : 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }
}

Future<List<SearchResult>> search(String query, {int limit = 20}) async {
  final json = await _call('search', {'query': query, 'limit': limit});
  final entries = json['entries'] as List? ?? const [];
  return entries
      .cast<Map<String, dynamic>>()
      .map(SearchResult.fromJson)
      .toList();
}

/// One downloadable stream as yt-dlp actually reports it. No invented qualities.
class MediaFormat {
  final String id, ext;
  final String? note;
  final int? height, bitrate, size;
  final bool hasVideo, hasAudio;

  MediaFormat.fromJson(Map<String, dynamic> j)
      : id = j['format_id'] as String? ?? '',
        ext = j['ext'] as String? ?? '',
        note = j['format_note'] as String?,
        height = (j['height'] as num?)?.round(),
        bitrate = (j['abr'] ?? j['tbr'] as num?) == null
            ? null
            : ((j['abr'] ?? j['tbr']) as num).round(),
        size = (j['filesize'] ?? j['filesize_approx'] as num?) == null
            ? null
            : ((j['filesize'] ?? j['filesize_approx']) as num).round(),
        hasVideo = j['vcodec'] != 'none' && j['vcodec'] != null,
        hasAudio = j['acodec'] != 'none' && j['acodec'] != null;

  String get label => hasVideo
      ? '${height != null ? "${height}p" : note ?? id} · ${ext.toUpperCase()}'
      : '${bitrate != null ? "${bitrate}kbps" : note ?? id} · ${ext.toUpperCase()}';
}

class MediaInfo {
  final String title, url;
  final String? uploader, thumbnail;
  final Duration? duration;
  final List<MediaFormat> video, audio;

  MediaInfo.fromJson(Map<String, dynamic> j)
      : title = j['title'] as String? ?? 'Untitled',
        url = j['webpage_url'] as String? ?? '',
        uploader = (j['channel'] ?? j['uploader']) as String?,
        thumbnail = j['thumbnail'] as String?,
        duration = j['duration'] == null
            ? null
            : Duration(seconds: (j['duration'] as num).round()),
        video = _formats(j, video: true),
        audio = _formats(j, video: false);

  static List<MediaFormat> _formats(Map<String, dynamic> j, {required bool video}) {
    final all = (j['formats'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MediaFormat.fromJson);
    final picked = video
        ? all.where((f) => f.hasVideo && f.height != null)
        : all.where((f) => f.hasAudio && !f.hasVideo);
    // One row per resolution/bitrate — yt-dlp lists many codec variants of each.
    final seen = <int>{};
    final out = <MediaFormat>[];
    for (final f in picked) {
      final key = (video ? f.height : f.bitrate) ?? -1;
      if (seen.add(key)) out.add(f);
    }
    out.sort((a, b) => ((video ? b.height : b.bitrate) ?? 0)
        .compareTo((video ? a.height : a.bitrate) ?? 0));
    return out;
  }
}

Future<MediaInfo> mediaInfo(String url) async =>
    MediaInfo.fromJson(await _call('info', {'url': url}));

// ---------------------------------------------------------------- downloads

const _events = EventChannel('fetchtube/downloads');

/// What was asked for, kept so retry/resume can re-issue the same request.
class DownloadRequest {
  final String url, title;
  final String? formatId, audioFormat, thumbnail, quality;
  const DownloadRequest({
    required this.url,
    required this.title,
    this.formatId,
    this.audioFormat,
    this.thumbnail,
    this.quality,
  });

  // Only the fields the native side understands; thumbnail/quality are display-only.
  Map<String, dynamic> toArgs() => {
        'url': url,
        'title': title,
        'formatId': formatId,
        'audioFormat': audioFormat,
      };
}

class Download {
  final String id, title, status, speed;
  final bool audio;
  final double progress;
  final int eta, total;
  final String? uri, error;

  Download.fromEvent(Map<dynamic, dynamic> e)
      : id = e['id'] as String,
        title = e['title'] as String,
        status = e['status'] as String,
        speed = (e['speed'] ?? '') as String,
        audio = (e['audio'] ?? false) as bool,
        progress = ((e['progress'] ?? 0) as num).toDouble(),
        eta = ((e['eta'] ?? -1) as num).round(),
        total = ((e['total'] ?? -1) as num).round(),
        uri = e['uri'] as String?,
        error = e['error'] as String?,
        bytes = ((e['bytes'] ?? -1) as num).round(),
        filename = e['filename'] as String?;

  /// Size of the finished file. Differs from [total] whenever ffmpeg converted.
  final int bytes;
  final String? filename;

  bool get active => status == 'running' || status == 'queued' || status == 'converting';
  bool get finished => status == 'done';

  /// Bytes transferred so far. yt-dlp reports a percentage and a total, not a count.
  int get received => total <= 0 ? -1 : (total * progress / 100).round();
}

/// One subscription for the whole app. Each `receiveBroadcastStream()` call opens its
/// own native subscription, and the native side keeps a single sink — so a second
/// listener's `onCancel` can null out a live listener and events are lost silently.
final Stream<Download> _downloads = _events
    .receiveBroadcastStream()
    .map((e) => Download.fromEvent(e as Map))
    // Empty onCancel keeps the native subscription open when the last listener
    // leaves, so progress arriving between listeners is not dropped.
    .asBroadcastStream(onCancel: (_) {});

Stream<Download> downloadEvents() => _downloads;

Future<String> startDownload(DownloadRequest r) async =>
    await _channel.invokeMethod<String>('download', r.toArgs()) ?? '';

Future<void> pauseDownload(String id) => _channel.invokeMethod('pause', {'id': id});

Future<void> cancelDownload(String id) => _channel.invokeMethod('cancel', {'id': id});

/// Resume and retry are the same operation: re-run yt-dlp, which continues any
/// partial file left in the download's directory.
Future<void> resumeDownload(String id, DownloadRequest r) =>
    _channel.invokeMethod('resume', {'id': id, ...r.toArgs()});

Future<String> dataDir() async =>
    await _channel.invokeMethod<String>('dataDir') ?? '';

Future<void> openFile(String uri) => _channel.invokeMethod('open', {'uri': uri});

Future<void> shareFile(String uri) => _channel.invokeMethod('share', {'uri': uri});

Future<bool> deleteFile(String uri) async =>
    await _channel.invokeMethod<bool>('delete', {'uri': uri}) ?? false;

String formatBytes(int bytes) {
  if (bytes < 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}

String formatDuration(Duration? d) {
  if (d == null) return '';
  final m = d.inMinutes, s = d.inSeconds % 60;
  return m >= 60
      ? '${d.inHours}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}
