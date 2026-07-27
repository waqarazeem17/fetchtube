# FetchTube

A SnapTube-style video/music downloader for Android. Search, preview real
qualities, download, and play — entirely on the device. No backend, no
account, no analytics.

```
User URL → Phone → Local processing (yt-dlp + ffmpeg) → Phone storage
```

There is no server anywhere in this picture. See [Privacy](#privacy--security)
for exactly what that means in practice.

## Status

Development phases 0–13 are implemented; 14/16 are partly covered by the
automated test suites described below rather than a manual device matrix;
17 (release optimization) was attempted and reverted — see
[Known limitations](#known-limitations). Everything under
[Features](#features) has been exercised on a real Android emulator with
real YouTube searches and downloads, not just compiled.

## Features

### Search & discovery
- Search YouTube by typing a query — no API key, no quota (Phase 3)
- Infinite scroll: scrolling near the bottom fetches more results
- Real thumbnails, titles, channel names, durations

### Media details
- Tapping a result shows the **actual** formats yt-dlp found for that
  video — never an invented quality list. If the source only has 720p,
  that's all you'll see.
- One-tap "Download (quality)" button using your Settings default
- Per-format download for anything more specific (2160p → 144p, multiple
  audio bitrates)
- Audio can be saved as its original codec (fastest, no quality loss) or
  transcoded to MP3

### Downloads
- Foreground service — closing the app or locking the screen does not stop
  a download; you get a notification with live progress
- Pause / Resume / Cancel per download
- Retry (manual or automatic) on failure
- Multiple downloads: configurable **1–3 concurrent transfers**
  (Settings → Queue)
- Wi-Fi only mode
- Files land in `Download/FetchTube/Videos` or `Download/FetchTube/Music`,
  visible to any file manager or other app — not hidden in app-private
  storage

### Library & history
- Videos / Music tabs listing everything you've downloaded
- Play, Share, Rename, Delete, File information, Open with… per file
- A lightweight local history (title, thumbnail, quality, size, date, file
  path) that survives app restarts — see [History](#history--storage)

### Player
- Built-in playback for both video and audio (audio shows the thumbnail
  as artwork) — no need to leave the app or hand off to another player
- Play/pause, seek, volume, duration, fullscreen for video

### Settings
- Default video/audio quality, Wi-Fi only, concurrent downloads, auto
  retry, completion notifications
- Light / Dark / System theme
- Storage usage (videos vs. music) and "Clear history" (forgets the list,
  never touches the files)
- App version, extractor (yt-dlp) version, open-source licenses

### Errors, not crashes
Every failure mode below is mapped to a specific, actionable message
instead of a generic "Error":

| What happened | What you see |
|---|---|
| No network | "No internet connection." |
| Region-blocked video | "This video is blocked in your region." |
| Private/removed video | "This video is private." / "This video is unavailable." |
| Unsupported link | "That link is not supported." |
| Source rate-limits this IP | "The source is rate-limiting this network. Try again in a few minutes." |
| Source flags automated traffic | "The source blocked this request as automated…" |
| A download link went stale (HTTP 403) | "That download link expired. Tap retry to fetch a fresh one." |
| Wi-Fi only is on, you're on mobile data | "Wi-Fi only is turned on and this connection isn't Wi-Fi." |
| App can't start a download in the background | "Downloads can't start while FetchTube is in the background. Open the app and try again." |

## Getting started

### Prerequisites
- Flutter 3.41+ (Dart 3.11+)
- Android SDK with platform 29+ installed, NDK 27 or 28
- A device or emulator running **Android 10 (API 29) or newer**

### Run it
```bash
flutter pub get
flutter run
```

First launch takes noticeably longer than normal — see
[First-run behavior](#first-run-behavior).

### Build a release APK
```bash
flutter build apk --release --split-per-abi
```
Always use `--split-per-abi`. A universal APK bundles Python + ffmpeg for
every architecture and balloons to ~150 MB; a split APK is ~60 MB per
device.

### Run the test suites
```bash
flutter test                                          # unit tests, no device needed
flutter test integration_test/download_test.dart       # on a real device/emulator, needs network
```
See [Testing](#testing) for what each one actually covers.

## Architecture

```
Flutter UI  (search · details · downloads · player · settings)
     │  MethodChannel "fetchtube/ytdlp"  +  EventChannel "fetchtube/downloads"
     ▼
Kotlin  DownloadService (foreground)  ──▶  YoutubeDL.getInstance()
     │                                         └─ bundled python + yt-dlp + ffmpeg
     ▼
MediaStore  →  Download/FetchTube/{Videos,Music}
```

No FastAPI, no Node.js, no Firebase, no database server, no external
downloader API. `yt-dlp` and `ffmpeg` run as native binaries **on the
phone**, shipped inside the app via
[`io.github.junkfood02.youtubedl-android`](https://github.com/JunkFood02/youtubedl-android)
(a Python interpreter + the yt-dlp source, cross-compiled for Android).

| File | Responsibility |
|---|---|
| `lib/theme.dart` | Palette, type scale, video/audio accent colors |
| `lib/home.dart` | Home screen, quick access tiles, recent downloads |
| `lib/search.dart` | Search results + media details/format picker |
| `lib/downloads.dart` | Download queue UI, library tabs, file actions |
| `lib/player.dart` | In-app video/audio playback |
| `lib/settings.dart` | Settings screen + persisted preferences |
| `lib/history.dart` | Persisted download history (JSON file) |
| `lib/ytdlp.dart` | All native-channel calls, response parsing |
| `android/.../Ytdlp.kt` | Owns the yt-dlp engine: init, search/info, download |
| `android/.../DownloadService.kt` | Foreground service: queue, retry, Wi-Fi gate, MediaStore publish |
| `android/.../MainActivity.kt` | MethodChannel/EventChannel wiring only |

## First-run behavior

The yt-dlp build bundled in the AAR is roughly two years old and YouTube
already rejects its requests. On first launch (and on any launch where the
previous update failed), FetchTube runs a one-time background update to a
current yt-dlp release. This needs network access; if it fails, the app
still works with the bundled version rather than becoming unusable, and
retries automatically on the next call. Watch **Settings → About →
Extractor** to see which version is actually active.

## Privacy & security

- URLs you enter are never sent anywhere except the video source itself
  (YouTube, etc.) — there is no FetchTube server to send them to
- Download history is a local JSON file on the device; nothing is
  uploaded
- No analytics, no telemetry, no crash reporting SDK
- No unnecessary permissions: internet, network state, foreground
  service, and notifications — that's the whole list (see
  `AndroidManifest.xml`)
- No DRM or access-control bypass of any kind

### License note
The extraction engine (`youtubedl-android`) and its bundled ffmpeg build
are **GPLv3**. If you distribute a build of this app, it must be
distributed under GPLv3 with source available. yt-dlp itself is
Unlicense; the Android wrapper around it is not.

### Distribution note
Google Play's Device and Network Abuse policy prohibits apps that
facilitate unauthorized downloading of copyrighted content from streaming
services. This is the same reason apps like Seal aren't on Play — plan for
sideloading or F-Droid, not the Play Store.

## History & storage

Downloaded files are copied into `Download/FetchTube/Videos` or
`Download/FetchTube/Music` via `MediaStore`, so they're visible to any
other app on the device — not locked inside FetchTube's private storage.
A companion JSON file (`history.json`, in app-private storage) remembers
the title, thumbnail, quality, size, and original source URL for each
download, purely for the app's own UI. **Clear history** in Settings
erases that JSON file only; it never touches the actual files in
`Download/FetchTube`.

## Testing

### Unit tests (`flutter test`) — 21 tests, run on any machine, no device needed
- Format parsing against a **real captured yt-dlp response** (33 raw
  formats → deduplicated quality rows, storyboards excluded, fractional
  bitrates rendered cleanly)
- Error-message mapping, including the correct precedence order (a
  specific cause like "410 expired" must win over the generic "unable to
  download" wrapper text)
- Default-quality picker logic (nearest-at-or-below, falls back to
  lowest, never crashes on an empty list)
- History JSON round-trip and corruption recovery
- Download progress → byte/percentage math

### Integration tests (`integration_test/download_test.dart`) — real device, real network
- Metadata extraction returns actual formats
- A real video downloads, merges via ffmpeg, and lands in MediaStore
- Pause kills the transfer; resume continues the partial file
- MP3 extraction
- The full user journey: search → pick a result → download → verify it
  survives a history reload

### Manual checklist
Automated coverage stops at the native yt-dlp/ffmpeg boundary and at
platform-specific UI behavior (foreground-service lifecycle across screen
lock, MediaStore visibility in a real file manager, notification
tap-through). Before a release, walk through:

**Search**
- [ ] Search returns results for a common query
- [ ] Empty/nonsense query shows "Nothing matched…", not a blank screen
- [ ] Scrolling to the bottom loads more results

**Video**
- [ ] 360p / 720p / 1080p / highest-available all download correctly
- [ ] Output plays back (in-app and in another player)

**Audio**
- [ ] Original-codec download (no re-encode)
- [ ] MP3 transcode
- [ ] Different bitrates show up when the source has them

**Downloads**
- [ ] Progress, speed, and ETA update live
- [ ] Pause → Resume continues rather than restarting
- [ ] Cancel removes the partial file
- [ ] A forced failure (e.g. airplane mode mid-download) shows Retry, and
      Retry works
- [ ] Lock the screen mid-download — it keeps going and notifies on
      completion
- [ ] Start 2–3 downloads at once with concurrency set to match

**Android versions**
- [ ] 11 / 12 / 13 / 14 / 15 / 16 — minSdk is 29 (Android 10), so anything
      below that is out of scope by design

## Known limitations

- **Not verified on physical ARM64 hardware.** All testing in this
  repository ran on an x86_64 Android emulator. A release-mode
  `arm64-v8a` APK crashed reliably on that emulator
  (`class N2.a is not a concrete class` inside the bundled Chaquopy
  Python bridge) when run through the emulator's ARM-on-x86 binary
  translation layer; the same code, same steps, on the emulator's native
  multi-ABI debug build did not crash at all. That points at the
  translation layer rather than the app, since real ARM64 hardware runs
  the `arm64-v8a` binaries natively with no translation involved — but
  this has not been confirmed on an actual phone. **Test on a real
  ARM64 device before shipping.**
- **R8/ProGuard minification is disabled on purpose.** It was tried;
  it broke the same Python bridge at startup on every launch (not just
  under translation). Chaquopy's reflection surface inside the bundled
  library isn't documented well enough to write a safe keep-rule set
  quickly, and the size win was under 1% anyway — the APK is almost
  entirely native binaries R8 can't touch.
- **Background audio is not implemented.** Playback stops when the app
  is backgrounded; continuing needs a MediaSession and its own service.
  Marked with a `ponytail:` comment in `player.dart`.
- **16 KB page size (Android 15+)** and **MP3 encoder (`libmp3lame`)
  presence** were flagged as open questions in the original project
  audit; `libmp3lame` has since been confirmed present and working
  (verified by an actual MP3 download in this session). 16 KB page size
  alignment of the bundled native libraries has not been independently
  verified.
- Performance under sustained load (Phase 14: RAM/CPU/battery across a
  5 MB → 1 GB+ range) has not been benchmarked with profiling tools in
  this session; only functional correctness was confirmed at each size
  tested.

## Development order this project followed

Project audit → architecture/feasibility → UI skeleton → search → media
details/format detection → local downloader → ffmpeg conversion/merging
→ download manager → background downloads → storage/history → player →
settings → this README. Each step was verified against a running app
before moving to the next, not just written and assumed correct.
