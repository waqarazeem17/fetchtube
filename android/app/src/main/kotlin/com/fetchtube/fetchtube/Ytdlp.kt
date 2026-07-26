package com.fetchtube.fetchtube

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import java.io.File

/**
 * Single owner of the yt-dlp engine. Both the activity (metadata) and the download
 * service (transfers) go through here so tool paths and init happen exactly one way.
 */
object Ytdlp {
    private var ready = false

    @Synchronized
    fun ensureInit(context: Context) {
        if (!ready) {
            // Unpacking python/ffmpeg is mandatory; if this throws there is nothing to run.
            YoutubeDL.getInstance().init(context)
            FFmpeg.getInstance().init(context)
            ready = true
        }
        // Retried on later calls so a failed first update heals itself.
        updateIfStale(context)
    }

    /**
     * The yt-dlp bundled in the AAR is ~2 years old and YouTube rejects its format
     * requests, so a first-run update matters. It is still best-effort: a failed update
     * must not brick the app, because the unpacked copy can already search and often
     * download. version() is null until an update lands, so it doubles as the flag.
     *
     * ponytail: updates once, on first success. yt-dlp rots in weeks — add a periodic
     * and manual re-check once Settings exists.
     */
    private fun updateIfStale(context: Context) {
        if (YoutubeDL.getInstance().version(context) != null) return
        runCatching {
            YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
        }
    }

    fun version(context: Context): String =
        YoutubeDL.getInstance().version(context) ?: "unknown"

    private fun nativeLib(context: Context, name: String): String? =
        File(context.applicationInfo.nativeLibraryDir, name).takeIf { it.exists() }?.absolutePath

    /**
     * YouTube's player challenge needs a JS runtime or formats come back empty, and
     * without ffmpeg yt-dlp silently degrades to the best muxed stream (360p).
     * Both are passed explicitly rather than trusting undocumented library defaults.
     */
    private fun YoutubeDLRequest.withTools(context: Context) = apply {
        nativeLib(context, "libqjs.so")?.let { addOption("--js-runtimes", "quickjs:$it") }
        nativeLib(context, "libffmpeg.so")?.let { addOption("--ffmpeg-location", it) }
    }

    /** Metadata query. Returns yt-dlp's JSON stdout verbatim; Dart owns the schema. */
    fun json(context: Context, target: String, vararg options: String): String {
        ensureInit(context)
        val request = YoutubeDLRequest(target).withTools(context)
        request.addOption("--dump-single-json")
        options.forEach { request.addOption(it) }
        return YoutubeDL.getInstance().execute(request).out
    }

    /**
     * Downloads into [dir]. Blocks until finished; throws on failure.
     * Partial files are left in place so a re-run with the same [dir] resumes.
     */
    fun download(
        context: Context,
        url: String,
        dir: File,
        formatId: String?,
        audioFormat: String?,
        processId: String,
        onProgress: (Float, Long, String) -> Unit,
    ) {
        ensureInit(context)
        dir.mkdirs()
        val request = YoutubeDLRequest(url).withTools(context)
        request.addOption("-o", "${dir.absolutePath}/%(title)s.%(ext)s")
        request.addOption("--no-playlist")
        request.addOption("--newline") // one progress line per update, not \r overwrites
        request.addOption("--continue") // resume a paused download's .part file
        if (audioFormat != null) {
            request.addOption("-x")
            // "best" keeps the source codec instead of re-encoding; "mp3" transcodes.
            request.addOption("--audio-format", audioFormat)
            if (formatId != null) request.addOption("-f", formatId)
            request.addOption("--audio-quality", "0")
            // Deliberately no --embed-thumbnail: it fetches and converts a separate
            // image after the audio is already done, and any failure there fails the
            // whole download. Title/artist tags are local and cannot fail that way.
            request.addOption("--add-metadata")
        } else {
            // Pair the chosen video stream with the best audio, then mux to mp4.
            request.addOption("-f", if (formatId != null) "$formatId+ba/$formatId/b" else "bv+ba/b")
            request.addOption("--merge-output-format", "mp4")
        }
        YoutubeDL.getInstance().execute(request, processId, onProgress)
    }

    fun cancel(processId: String): Boolean =
        runCatching { YoutubeDL.getInstance().destroyProcessById(processId) }.getOrDefault(false)
}
