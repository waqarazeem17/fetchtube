package com.fetchtube.fetchtube

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import androidx.core.net.toUri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

private const val CHANNEL = "fetchtube/ytdlp"
private const val EVENTS = "fetchtube/downloads"

class MainActivity : FlutterActivity() {
    // yt-dlp calls block on a child process, so they never touch the main thread.
    private val io = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        requestNotificationPermission()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                // Queue mutations are cheap and must not be reordered behind a metadata
                // fetch, so they answer on the main thread.
                when (call.method) {
                    "download", "retry", "resume" -> {
                        val id = call.argument<String>("id") ?: System.nanoTime().toString()
                        val failure = DownloadService.send(
                            this, DownloadService.ACTION_ENQUEUE,
                            mapOf(
                                "id" to id,
                                "url" to call.argument<String>("url"),
                                "title" to call.argument<String>("title"),
                                "formatId" to call.argument<String>("formatId"),
                                "audioFormat" to call.argument<String>("audioFormat"),
                                // Settings values, re-read every call so a mid-queue
                                // change (e.g. turning off Wi-Fi only) takes effect.
                                "wifiOnly" to call.argument<Boolean>("wifiOnly").toString(),
                                "maxConcurrent" to
                                    (call.argument<Int>("maxConcurrent") ?: 1).toString(),
                                "autoRetry" to call.argument<Boolean>("autoRetry").toString(),
                                "notifyOnComplete" to
                                    call.argument<Boolean>("notifyOnComplete").toString(),
                            ),
                        )
                        if (failure == null) result.success(id)
                        else result.error("service", failure, null)
                        return@setMethodCallHandler
                    }
                    // Where Dart keeps its history/settings files. Avoids a path_provider
                    // dependency for the one path we need.
                    "dataDir" -> {
                        result.success(filesDir.absolutePath)
                        return@setMethodCallHandler
                    }
                    "appVersion" -> {
                        val name = packageManager.getPackageInfo(packageName, 0).versionName
                        result.success(name ?: "unknown")
                        return@setMethodCallHandler
                    }
                    "open", "share" -> {
                        val uri = call.argument<String>("uri")!!.toUri()
                        val type = contentResolver.getType(uri) ?: "*/*"
                        val intent = if (call.method == "open") {
                            Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
                        } else {
                            Intent(Intent.ACTION_SEND).setType(type)
                                .putExtra(Intent.EXTRA_STREAM, uri)
                        }
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        try {
                            startActivity(
                                if (call.method == "share") Intent.createChooser(intent, null)
                                else intent
                            )
                            result.success(null)
                        } catch (e: ActivityNotFoundException) {
                            result.error("noapp", "No app can open this file", null)
                        }
                        return@setMethodCallHandler
                    }
                    "delete" -> {
                        val uri = call.argument<String>("uri")!!.toUri()
                        val rows = runCatching { contentResolver.delete(uri, null, null) }
                            .getOrDefault(0)
                        result.success(rows > 0)
                        return@setMethodCallHandler
                    }
                    "rename" -> {
                        val uri = call.argument<String>("uri")!!.toUri()
                        val name = call.argument<String>("name")!!
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                        }
                        val rows = runCatching {
                            contentResolver.update(uri, values, null, null)
                        }.getOrDefault(0)
                        result.success(rows > 0)
                        return@setMethodCallHandler
                    }
                    "pause", "cancel" -> {
                        val id = call.argument<String>("id")!!
                        val action = if (call.method == "pause") DownloadService.ACTION_PAUSE
                        else DownloadService.ACTION_CANCEL
                        val failure = DownloadService.send(this, action, mapOf("id" to id))
                        if (call.method == "cancel") Downloads.remove(id)
                        // Do not swallow this: a rejected service start used to make Pause
                        // silently do nothing, leaving the UI stuck on "running".
                        if (failure == null) result.success(null)
                        else result.error("service", failure, null)
                        return@setMethodCallHandler
                    }
                }

                io.execute {
                    try {
                        // Unpacking python/ffmpeg must happen before anything reads them;
                        // the first call after install pays the cost.
                        Ytdlp.ensureInit(this)
                        val out = when (call.method) {
                            "version" -> Ytdlp.version(this)
                            "search" -> Ytdlp.json(
                                this,
                                "ytsearch${call.argument<Int>("limit") ?: 20}:${call.argument<String>("query")}",
                                "--flat-playlist",
                            )
                            "info" -> Ytdlp.json(this, call.argument<String>("url")!!)
                            else -> {
                                runOnUiThread { result.notImplemented() }
                                return@execute
                            }
                        }
                        runOnUiThread { result.success(out) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("ytdlp", e.message, null) }
                    }
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    // Replay so a reopened UI shows downloads that ran while it was gone.
                    Downloads.snapshot().forEach { runOnUiThread { sink?.success(it) } }
                    Downloads.listener = { runOnUiThread { sink?.success(it) } }
                }

                override fun onCancel(arguments: Any?) {
                    Downloads.listener = null
                }
            },
        )
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    override fun onDestroy() {
        Downloads.listener = null
        io.shutdown()
        super.onDestroy()
    }
}
