import 'dart:convert';
import 'dart:io';

import 'ytdlp.dart';

/// One finished download, as remembered across app restarts.
class HistoryEntry {
  final String id, title, uri, filename;
  final String? thumbnail, quality, source;
  final bool audio;
  final int bytes;
  final DateTime date;

  const HistoryEntry({
    required this.id,
    required this.title,
    required this.uri,
    required this.filename,
    required this.audio,
    required this.bytes,
    required this.date,
    this.thumbnail,
    this.quality,
    this.source,
  });

  HistoryEntry.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        title = j['title'] as String,
        uri = j['uri'] as String,
        filename = (j['filename'] ?? '') as String,
        thumbnail = j['thumbnail'] as String?,
        quality = j['quality'] as String?,
        source = j['source'] as String?,
        audio = (j['audio'] ?? false) as bool,
        bytes = ((j['bytes'] ?? -1) as num).round(),
        date = DateTime.fromMillisecondsSinceEpoch((j['date'] as num).round());

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'uri': uri,
        'filename': filename,
        'thumbnail': thumbnail,
        'quality': quality,
        'source': source,
        'audio': audio,
        'bytes': bytes,
        'date': date.millisecondsSinceEpoch,
      };

  String get subtitle => [
        if (quality != null && quality!.isNotEmpty) quality,
        if (bytes > 0) formatBytes(bytes),
      ].join(' • ');
}

/// Append-only local history in a single JSON file.
///
/// ponytail: a flat file, read once at launch and rewritten on change. Fine for the
/// hundreds of rows a downloader accumulates; move to sqflite if it ever needs
/// queries, paging, or partial writes.
class History {
  static final instance = History._();
  History._();

  final List<HistoryEntry> _entries = [];
  File? _file;

  List<HistoryEntry> get all => List.unmodifiable(_entries);

  List<HistoryEntry> where({required bool audio}) =>
      _entries.where((e) => e.audio == audio).toList();

  int countOf({required bool audio}) => where(audio: audio).length;

  /// Bytes held on this device for one media type. Drives the home tiles.
  int bytesOf({required bool audio}) => where(audio: audio)
      .fold(0, (sum, e) => sum + (e.bytes > 0 ? e.bytes : 0));

  Future<void> load() async {
    final dir = await dataDir();
    if (dir.isEmpty) return;
    final file = File('$dir/history.json');
    _file = file;
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(file.readAsStringSync()) as List;
      _entries
        ..clear()
        ..addAll(raw.cast<Map<String, dynamic>>().map(HistoryEntry.fromJson));
    } on FormatException {
      // A truncated write should not brick the app; start over rather than crash.
      _entries.clear();
    }
  }

  Future<void> add(HistoryEntry entry) async {
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.insert(0, entry);
    await _flush();
  }

  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id == id);
    await _flush();
  }

  Future<void> clear() async {
    _entries.clear();
    await _flush();
  }

  Future<void> _flush() async {
    final file = _file;
    if (file == null) return;
    // Write-then-rename so an interrupted write cannot leave a half-written file.
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(_entries.map((e) => e.toJson()).toList()));
    tmp.renameSync(file.path);
  }
}
