package com.example.quantum_ide

import android.app.DownloadManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.quantum_ide/native"
    private val DOWNLOAD_CHANNEL = "com.example.quantum_ide/download"
    private lateinit var bootstrapManager: BootstrapManager
    private lateinit var processManager: ProcessManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val downloadIds = mutableMapOf<String, Long>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val filesDir = applicationContext.filesDir.absolutePath
        val nativeLibDir = applicationContext.applicationInfo.nativeLibraryDir

        bootstrapManager = BootstrapManager(applicationContext, filesDir, nativeLibDir)
        processManager = ProcessManager(filesDir, nativeLibDir)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getArch" -> result.success(ArchUtils.getArch())
                "getFilesDir" -> result.success(filesDir)
                "getNativeLibDir" -> result.success(nativeLibDir)
                "isBootstrapComplete" -> result.success(bootstrapManager.isBootstrapComplete())
                "getBootstrapStatus" -> result.success(bootstrapManager.getBootstrapStatus())
                "runCommand" -> {
                    val command = call.argument<String>("command")
                    if (command != null) {
                        Thread {
                            try {
                                val output = processManager.runInProotSync(command)
                                runOnUiThread { result.success(output) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("RUN_ERROR", e.message, null) }
                            }
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "Command is null", null)
                    }
                }
                "extractRootfs" -> {
                    val tarPath = call.argument<String>("tarPath")
                    if (tarPath != null) {
                        Thread {
                            try {
                                bootstrapManager.extractRootfs(tarPath)
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("EXTRACT_ERROR", e.message, null) }
                            }
                        }.start()
                    } else result.error("INVALID_ARGS", "tarPath required", null)
                }
                "setupDirs" -> {
                    Thread {
                        bootstrapManager.setupDirectories()
                        runOnUiThread { result.success(true) }
                    }.start()
                }
                "writeResolv" -> {
                    Thread {
                        bootstrapManager.writeResolvConf()
                        runOnUiThread { result.success(true) }
                    }.start()
                }
                "copyToClipboard" -> {
                    val text = call.argument<String>("text")
                    if (text != null) {
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("URL", text))
                        result.success(true)
                    } else result.error("INVALID_ARGS", "text required", null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadModel" -> {
                    val url = call.argument<String>("url")
                    val filename = call.argument<String>("filename")
                    val modelsDir = call.argument<String>("modelsDir")
                    if (url != null && filename != null && modelsDir != null) {
                        try {
                            val downloadId = startDownload(url, filename, modelsDir)
                            downloadIds[filename] = downloadId
                            result.success(mapOf("downloadId" to downloadId))
                        } catch (e: Exception) {
                            result.error("DOWNLOAD_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "url, filename, modelsDir required", null)
                    }
                }
                "cancelDownload" -> {
                    val filename = call.argument<String>("filename")
                    if (filename != null) {
                        val downloadId = downloadIds.remove(filename)
                        if (downloadId != null) {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            manager.remove(downloadId)
                        }
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "filename required", null)
                    }
                }
                "getDownloadStatus" -> {
                    val filename = call.argument<String>("filename")
                    if (filename != null) {
                        val downloadId = downloadIds[filename]
                        if (downloadId != null) {
                            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                            val query = DownloadManager.Query().setFilterById(downloadId)
                            manager.query(query)?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                                    val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                                    val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                                    result.success(mapOf(
                                        "status" to status,
                                        "downloaded" to downloaded,
                                        "total" to total
                                    ))
                                } else {
                                    result.success(null)
                                }
                            } ?: result.success(null)
                        } else {
                            result.success(null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "filename required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startDownload(url: String, filename: String, modelsDir: String): Long {
        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(filename)
            .setDescription("Downloading AI model...")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(null, "models", filename)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return manager.enqueue(request)
    }
}
