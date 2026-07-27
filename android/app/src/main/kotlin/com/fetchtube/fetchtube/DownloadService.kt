package com.fetchtube.fetchtube

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.IBinder
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** One queued or active download, as mirrored to Flutter. */
data class DownloadState(
    val id: String,
    val title: String,
    val audio: Boolean,
    var status: String = "queued", // queued running paused done failed canceled
    var progress: Float = 0f,
    var etaSeconds: Long = -1,
    var speed: String = "",
    var totalBytes: Long = -1,
    var uri: String? = null,
    var error: String? = null,
    /** Size of the finished file, which differs from totalBytes after a conversion. */
    var bytes: Long = -1,
    var filename: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id, "title" to title, "audio" to audio, "status" to status,
        "progress" to progress, "eta" to etaSeconds, "speed" to speed,
        "total" to totalBytes, "uri" to uri, "error" to error,
        "bytes" to bytes, "filename" to filename,
    )
}

/**
 * Holds download state outside the Activity so downloads survive the UI being closed.
 * The Activity attaches a listener when it exists and replays current state on attach.
 */
object Downloads {
    val states = ConcurrentHashMap<String, DownloadState>()
    private val order = mutableListOf<String>()

    @Volatile
    var listener: ((Map<String, Any?>) -> Unit)? = null

    fun put(state: DownloadState) {
        if (states.put(state.id, state) == null) synchronized(order) { order.add(state.id) }
        emit(state)
    }

    fun emit(state: DownloadState) {
        listener?.invoke(state.toMap())
    }

    fun snapshot(): List<Map<String, Any?>> =
        synchronized(order) { order.mapNotNull { states[it]?.toMap() } }

    fun remove(id: String) {
        states.remove(id)
        synchronized(order) { order.remove(id) }
    }
}

class DownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val mgr = getSystemService(NotificationManager::class.java)
        mgr.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
        )
        startForeground(
            NOTIF_ID,
            notification("FetchTube", "Preparing…", 0),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> intent.getStringExtra("id")?.let { stop(it, "canceled") }
            ACTION_PAUSE -> intent.getStringExtra("id")?.let { stop(it, "paused") }
            ACTION_ENQUEUE -> enqueue(intent)
        }
        return START_NOT_STICKY
    }

    private fun enqueue(intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val url = intent.getStringExtra("url") ?: return
        val title = intent.getStringExtra("title") ?: "Download"
        val formatId = intent.getStringExtra("formatId")
        val audioFormat = intent.getStringExtra("audioFormat")
        val wifiOnly = intent.getStringExtra("wifiOnly") == "true"
        val autoRetry = intent.getStringExtra("autoRetry") == "true"
        val notifyOnComplete = intent.getStringExtra("notifyOnComplete") != "false"
        setConcurrency(intent.getStringExtra("maxConcurrent")?.toIntOrNull() ?: 1)

        // Identifies this attempt. Pausing or cancelling drops the token, so a task that
        // is still unwinding cannot report "failed" over a newer attempt's state.
        val token = Any()
        tokens[id] = token
        val state = Downloads.states[id] ?: DownloadState(id, title, audioFormat != null)
        state.status = "queued"
        state.error = null
        Downloads.put(state)

        queue.execute {
            if (tokens[id] !== token) return@execute
            // Checked at dequeue time, not enqueue time: a queued item can sit for a
            // while, and the network may have changed by the time its turn comes.
            if (wifiOnly && !isOnWifi()) {
                state.status = "failed"
                state.error = "Wi-Fi only is turned on and this connection isn't Wi-Fi."
                Downloads.emit(state)
                tokens.remove(id)
                stopIfIdle()
                return@execute
            }
            val dir = File(cacheDir, "dl/$id")
            var error: Exception? = null
            val attempts = if (autoRetry) 2 else 1
            for (attempt in 1..attempts) {
                if (tokens[id] !== token) return@execute
                try {
                    state.status = "running"
                    state.error = null
                    Downloads.emit(state)
                    Ytdlp.download(this, url, dir, formatId, audioFormat, id) { pct, eta, line ->
                        state.progress = pct
                        state.etaSeconds = eta
                        parseSpeed(line)?.let { state.speed = it }
                        parseTotal(line)?.let { state.totalBytes = it }
                        // Converting/merging reports no percentage; surface it so the UI
                        // does not look stalled at 100%.
                        if (line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]")) {
                            state.status = "converting"
                        }
                        Downloads.emit(state)
                        notify(state)
                    }
                    if (tokens[id] !== token) return@execute
                    val file =
                        dir.listFiles()?.firstOrNull { it.isFile && !it.name.endsWith(".part") }
                            ?: throw IllegalStateException("yt-dlp produced no output file")
                    state.bytes = file.length()
                    state.filename = file.name
                    state.uri = publish(file, state.audio).toString()
                    state.progress = 100f
                    state.status = "done"
                    dir.deleteRecursively()
                    if (notifyOnComplete) notifyDone(state)
                    error = null
                    break
                } catch (e: Exception) {
                    // Pause/cancel kills the process, which surfaces here as an exception.
                    // Only treat it as a real failure if this attempt is still current.
                    if (tokens[id] !== token) return@execute
                    error = e
                    if (attempt < attempts) {
                        state.status = "queued"
                        Downloads.emit(state)
                        Thread.sleep(3000)
                    }
                }
            }
            if (error != null) {
                state.status = "failed"
                state.error = error.message ?: error.toString()
            }
            if (tokens[id] === token) {
                tokens.remove(id)
                Downloads.emit(state)
            }
            stopIfIdle()
        }
    }

    private fun stopIfIdle() {
        if (Downloads.states.values.none { it.status == "running" || it.status == "queued" }) {
            stopSelf()
        }
    }

    private fun isOnWifi(): Boolean {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    /** Kills the yt-dlp process. Partial files stay on disk so "paused" can resume. */
    private fun stop(id: String, status: String) {
        // Drop the token first: the task is about to throw, and this is what tells it
        // the failure was deliberate rather than a real error.
        tokens.remove(id)
        Ytdlp.cancel(id)
        Downloads.states[id]?.let {
            it.status = status
            it.speed = ""
            if (status == "canceled") File(cacheDir, "dl/$id").deleteRecursively()
            Downloads.emit(it)
        }
    }

    /**
     * Copies the finished file into Download/FetchTube/{Videos,Music} via MediaStore.
     * yt-dlp writes through raw paths, which scoped storage forbids in shared folders,
     * so it downloads to cache first and we hand the bytes to MediaStore here.
     */
    private fun publish(file: File, audio: Boolean): android.net.Uri {
        val sub = if (audio) "Music" else "Videos"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeOf(file.name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/FetchTube/$sub")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create the output file")
        resolver.openOutputStream(uri).use { out ->
            requireNotNull(out) { "Could not open the output file" }
            file.inputStream().use { it.copyTo(out) }
        }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri
    }

    private fun notification(title: String, text: String, progress: Int?) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(progress != null)
            .setOnlyAlertOnce(true)
            .apply { if (progress != null) setProgress(100, progress, false) }
            .build()

    private fun notify(state: DownloadState) {
        val pct = state.progress.toInt()
        getSystemService(NotificationManager::class.java).notify(
            NOTIF_ID,
            notification("Downloading ${state.title}", "$pct%", pct),
        )
    }

    private fun notifyDone(state: DownloadState) {
        getSystemService(NotificationManager::class.java).notify(
            state.id.hashCode(),
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Download complete")
                .setContentText(state.title)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setAutoCancel(true)
                .build(),
        )
    }

    companion object {
        // Process-scoped on purpose. Tying it to the Service instance meant a stopSelf()
        // from a finished download could shutdownNow() and interrupt work that the next
        // enqueue had already submitted, killing it with InterruptedException.
        //
        // Sized by Settings > Concurrent downloads (1-3) via setConcurrency below.
        private val queue =
            ThreadPoolExecutor(1, 1, 60, TimeUnit.SECONDS, LinkedBlockingQueue())

        /** Current attempt per download id. See [enqueue]. */
        private val tokens = ConcurrentHashMap<String, Any>()

        /** Resizes the pool. Order matters: max must never dip below core mid-update. */
        @Synchronized
        private fun setConcurrency(n: Int) {
            val size = n.coerceIn(1, 3)
            if (size > queue.maximumPoolSize) {
                queue.maximumPoolSize = size
                queue.corePoolSize = size
            } else {
                queue.corePoolSize = size
                queue.maximumPoolSize = size
            }
        }

        private const val CHANNEL_ID = "downloads"
        private const val NOTIF_ID = 1
        const val ACTION_ENQUEUE = "enqueue"
        const val ACTION_CANCEL = "cancel"
        const val ACTION_PAUSE = "pause"

        /**
         * Returns null on success, or a user-facing reason on failure.
         *
         * Android 12+ refuses startForegroundService() while the app is in the
         * background (screen off counts), and the exception is fatal if it escapes —
         * it used to take the whole app down. Pause/cancel only ever target a service
         * that is already running, so they use the plain start.
         */
        fun send(context: Context, action: String, extras: Map<String, String?>): String? {
            val intent = Intent(context, DownloadService::class.java).setAction(action)
            extras.forEach { (k, v) -> intent.putExtra(k, v) }
            return try {
                if (action == ACTION_ENQUEUE) context.startForegroundService(intent)
                else context.startService(intent)
                null
            } catch (e: Exception) {
                "Downloads can't start while FetchTube is in the background. " +
                    "Open the app and try again."
            }
        }

        private val SPEED = Regex("""at\s+([\d.]+\s*[KMG]?i?B/s)""")
        private val TOTAL = Regex("""of\s+~?\s*([\d.]+)\s*([KMG]?)i?B""")

        fun parseSpeed(line: String): String? = SPEED.find(line)?.groupValues?.get(1)?.trim()

        /** yt-dlp reports totals as "3.36MiB"; convert to bytes for the UI. */
        fun parseTotal(line: String): Long? {
            val m = TOTAL.find(line) ?: return null
            val value = m.groupValues[1].toDoubleOrNull() ?: return null
            val scale = when (m.groupValues[2]) {
                "K" -> 1L shl 10
                "M" -> 1L shl 20
                "G" -> 1L shl 30
                else -> 1L
            }
            return (value * scale).toLong()
        }

        fun mimeOf(name: String) = when (name.substringAfterLast('.', "").lowercase()) {
            "mp4", "m4v" -> "video/mp4"
            "webm" -> "video/webm"
            "mkv" -> "video/x-matroska"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "opus", "ogg" -> "audio/ogg"
            "wav" -> "audio/wav"
            "flac" -> "audio/flac"
            else -> "application/octet-stream"
        }
    }
}
