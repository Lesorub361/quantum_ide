package com.example.quantum_ide

import android.app.DownloadManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.Process
import androidx.core.content.FileProvider
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
                            } catch (e: Throwable) {
                                runOnUiThread { result.error("EXTRACT_ERROR", e.message ?: e.toString(), null) }
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
                "getDeviceModel" -> {
                    try {
                        val model = android.os.Build.MODEL ?: ""
                        val manufacturer = android.os.Build.MANUFACTURER ?: ""
                        result.success("$manufacturer $model")
                    } catch (e: Exception) {
                        result.success("")
                    }
                }
                "startForegroundSession" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Quantum IDE"
                        val content = call.argument<String>("content") ?: "Терминал и сессия активны в фоне"
                        IdeSessionService.start(applicationContext, title, content)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "stopForegroundSession" -> {
                    try {
                        IdeSessionService.stop(applicationContext)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    val launchAfter = call.argument<Boolean>("launchAfterInstall") ?: true
                    if (apkPath != null) {
                        Thread {
                            installApk(apkPath, launchAfter, result)
                        }.start()
                    } else {
                        result.error("INVALID_ARGS", "apkPath is required", null)
                    }
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.error("LAUNCH_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "packageName is required", null)
                    }
                }
                "isUsbHostSupported" -> {
                    try {
                        val hasHost = packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
                        result.success(hasHost)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getConnectedUsbDevices" -> {
                    try {
                        val usbManager = getSystemService(Context.USB_SERVICE) as? android.hardware.usb.UsbManager
                        val deviceList = usbManager?.deviceList?.values?.map { dev ->
                            val manufacturer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                try { dev.manufacturerName ?: "" } catch (_: Exception) { "" }
                            } else ""
                            val product = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                try { dev.productName ?: "" } catch (_: Exception) { "" }
                            } else ""
                            mapOf(
                                "deviceName" to dev.deviceName,
                                "vendorId" to dev.vendorId,
                                "productId" to dev.productId,
                                "manufacturer" to manufacturer,
                                "product" to product,
                                "deviceClass" to dev.deviceClass
                            )
                        } ?: emptyList<Map<String, Any?>>()
                        result.success(deviceList)
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any?>>())
                    }
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
        // Use the modelsDir passed from Dart to ensure same path
        val modelsDirFile = File(modelsDir)
        if (!modelsDirFile.exists()) modelsDirFile.mkdirs()
        val destFile = File(modelsDirFile, filename)

        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle(filename)
            .setDescription("Downloading AI model...")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationUri(Uri.fromFile(destFile))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)

        val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return manager.enqueue(request)
    }

    private fun installApk(apkPath: String, launchAfterInstall: Boolean, result: MethodChannel.Result) {
        val apk = File(apkPath)
        if (!apk.exists() || !apk.name.endsWith(".apk", ignoreCase = true) || apk.length() == 0L) {
            runOnUiThread { result.error("INVALID_APK", "APK file does not exist or is empty: $apkPath", null) }
            return
        }

        try {
            // Check MIUI or older Android: use FileProvider
            if (isMiui() || Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", apk)
                val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                runOnUiThread {
                    result.success(mapOf("status" to "intent_launched", "method" to "file_provider"))
                }
                return
            }

            // Modern PackageInstaller API: Direct stream, no ADB needed, silent updates on Android 12+
            val packageInstaller = packageManager.packageInstaller
            val archiveInfo = packageManager.getPackageArchiveInfo(apk.absolutePath, 0)
            val apkPackageName = archiveInfo?.packageName
            val isUpdate = apkPackageName?.let { isPackageInstalled(it) } == true

            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setSize(apk.length())
                setInstallLocation(PackageInfo.INSTALL_LOCATION_AUTO)
                setInstallReason(PackageManager.INSTALL_REASON_USER)
                setOriginatingUid(Process.myUid())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setRequireUserAction(
                        if (isUpdate) PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
                        else PackageInstaller.SessionParams.USER_ACTION_REQUIRED
                    )
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    setPackageSource(PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE)
                }
            }

            val sessionId = packageInstaller.createSession(params)
            packageInstaller.openSession(sessionId).use { session ->
                apk.inputStream().use { input ->
                    session.openWrite(apk.name, 0, apk.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }

                val intent = Intent(this, MainActivity::class.java).apply {
                    action = "com.example.quantum_ide.INSTALL_COMPLETE"
                    putExtra("package_name", apkPackageName)
                    putExtra("launch_after", launchAfterInstall)
                }
                val mutability = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val pendingIntent = PendingIntent.getActivity(this, sessionId, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutability)
                session.commit(pendingIntent.intentSender)
            }

            runOnUiThread {
                result.success(mapOf(
                    "status" to "session_committed",
                    "sessionId" to sessionId,
                    "packageName" to apkPackageName,
                    "isUpdate" to isUpdate,
                    "method" to "package_installer"
                ))
            }
        } catch (e: Exception) {
            runOnUiThread {
                result.error("INSTALL_ERROR", e.message ?: e.toString(), null)
            }
        }
    }

    private fun isMiui(): Boolean {
        return !Build.MANUFACTURER.isNullOrEmpty() &&
            Build.MANUFACTURER.contains("Xiaomi", ignoreCase = true)
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (_: Exception) {
            false
        }
    }
}
