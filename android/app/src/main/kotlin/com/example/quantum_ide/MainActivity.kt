package com.example.quantum_ide

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.quantum_ide/native"
    private lateinit var bootstrapManager: BootstrapManager
    private lateinit var processManager: ProcessManager

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
    }
}
