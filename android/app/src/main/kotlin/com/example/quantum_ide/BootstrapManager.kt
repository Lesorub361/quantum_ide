package com.example.quantum_ide

import android.content.Context
import android.system.Os
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.util.zip.GZIPInputStream
import org.apache.commons.compress.archivers.ar.ArArchiveInputStream
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import org.apache.commons.compress.compressors.zstandard.ZstdCompressorInputStream

class BootstrapManager(
    private val context: Context,
    private val filesDir: String,
    private val nativeLibDir: String
) {
    private val rootfsDir get() = "$filesDir/rootfs/ubuntu"
    private val tmpDir get() = "$filesDir/tmp"
    private val homeDir get() = "$filesDir/home"
    private val configDir get() = "$filesDir/config"
    private val libDir get() = "$filesDir/lib"

    fun setupDirectories() {
        listOf(rootfsDir, tmpDir, homeDir, configDir, libDir).forEach {
            File(it).mkdirs()
        }
        setupLibtalloc()
        setupFakeSysdata()
    }

    private fun setupLibtalloc() {
        val source = File("$nativeLibDir/libtalloc.so")
        val target = File("$libDir/libtalloc.so.2")
        if (source.exists() && !target.exists()) {
            source.copyTo(target)
            target.setExecutable(true)
        }
    }

    fun isBootstrapComplete(): Boolean {
        val rootfs = File(rootfsDir)
        val binBash = File("$rootfsDir/bin/bash")
        val usrBinBash = File("$rootfsDir/usr/bin/bash")
        return rootfs.exists() && (binBash.exists() || usrBinBash.exists())
    }

    fun getBootstrapStatus(): Map<String, Any> {
        val rootfsExists = File(rootfsDir).exists()
        val binBashExists = File("$rootfsDir/bin/bash").exists() || File("$rootfsDir/usr/bin/bash").exists()

        return mapOf(
            "rootfsExists" to rootfsExists,
            "binBashExists" to binBashExists,
            "rootfsPath" to rootfsDir,
            "complete" to (rootfsExists && binBashExists)
        )
    }

    fun ensureRootfsCompatibilityLinks(): Boolean {
        val rootfs = File(rootfsDir)
        if (!rootfs.isDirectory) return false
        val links = mapOf(
            "bin" to "usr/bin",
            "lib" to "usr/lib",
            "sbin" to "usr/sbin",
        )
        return runCatching {
            links.forEach { (name, destination) ->
                val link = File(rootfs, name)
                val path = link.toPath()
                if (java.nio.file.Files.isSymbolicLink(path)) {
                    if (java.nio.file.Files.readSymbolicLink(path).toString() != destination) {
                        java.nio.file.Files.delete(path)
                        Os.symlink(destination, link.absolutePath)
                    }
                } else if (link.exists()) {
                    if (!link.isDirectory) {
                        link.delete()
                        Os.symlink(destination, link.absolutePath)
                    }
                } else {
                    Os.symlink(destination, link.absolutePath)
                }
            }
            val bash = File(rootfs, "usr/bin/bash")
            if (bash.exists()) bash.setExecutable(true, false)
            val binBash = File(rootfs, "bin/bash")
            if (binBash.exists()) binBash.setExecutable(true, false)
            true
        }.onFailure {
            android.util.Log.e("BootstrapManager", "Could not repair compatibility links", it)
        }.getOrDefault(false)
    }

    fun extractRootfs(tarPath: String) {
        val archive = File(tarPath)
        val rootfs = File(rootfsDir)
        val staging = File("$rootfsDir.installing")
        if (staging.exists()) deleteRecursively(staging)
        staging.mkdirs()

        val deferredLinks = mutableListOf<Pair<File, File>>()
        val isZstd = tarPath.endsWith(".zst") || tarPath.endsWith(".zstandard")

        try {
            val fileStream = BufferedInputStream(FileInputStream(archive), 256 * 1024)
            val compressorStream: InputStream = if (isZstd) {
                ZstdCompressorInputStream(fileStream)
            } else {
                GZIPInputStream(fileStream)
            }

            TarArchiveInputStream(compressorStream).use { tar ->
                var entry: TarArchiveEntry? = tar.nextEntry
                while (entry != null) {
                    val cleanName = entry.name.removePrefix("./").trimStart('/')
                    if (cleanName.isNotBlank() && !cleanName.startsWith("dev/") && cleanName != "dev") {
                        val target = File(staging, cleanName)
                        when {
                            entry.isDirectory -> target.mkdirs()
                            entry.isSymbolicLink -> {
                                target.parentFile?.mkdirs()
                                if (target.exists() || java.nio.file.Files.isSymbolicLink(target.toPath())) {
                                    target.delete()
                                }
                                try {
                                    Os.symlink(entry.linkName, target.absolutePath)
                                } catch (_: Exception) {}
                            }
                            entry.isLink -> {
                                target.parentFile?.mkdirs()
                                val linkTarget = File(staging, entry.linkName.removePrefix("./").trimStart('/'))
                                if (linkTarget.exists()) {
                                    linkTarget.inputStream().use { input -> FileOutputStream(target).use { input.copyTo(it) } }
                                    if (linkTarget.canExecute()) target.setExecutable(true, false)
                                } else {
                                    deferredLinks.add(target to linkTarget)
                                }
                            }
                            entry.isFile -> {
                                target.parentFile?.mkdirs()
                                FileOutputStream(target).use { output ->
                                    val buf = ByteArray(65536)
                                    var len: Int
                                    while (tar.read(buf).also { len = it } != -1) {
                                        output.write(buf, 0, len)
                                    }
                                }
                                target.setReadable(true, false)
                                target.setWritable(true, false)
                                if (entry.mode == 0 || entry.mode and 0b001_001_001 != 0 ||
                                    cleanName.contains("/bin/") || cleanName.contains("/sbin/") ||
                                    cleanName.endsWith("/bash") || cleanName.endsWith("/sh") ||
                                    cleanName.endsWith("/node") || cleanName.endsWith("/git")) {
                                    target.setExecutable(true, false)
                                }
                            }
                        }
                    }
                    entry = tar.nextEntry
                }
            }

            deferredLinks.forEach { (target, linkTarget) ->
                if (linkTarget.exists()) {
                    target.parentFile?.mkdirs()
                    linkTarget.inputStream().use { input -> FileOutputStream(target).use { input.copyTo(it) } }
                    if (linkTarget.canExecute()) target.setExecutable(true, false)
                }
            }

            if (rootfs.exists()) deleteRecursively(rootfs)
            if (!staging.renameTo(rootfs)) {
                staging.copyRecursively(rootfs, overwrite = true)
                deleteRecursively(staging)
            }
        } catch (e: Throwable) {
            deleteRecursively(staging)
            throw RuntimeException("Extraction error: ${e.message}")
        }

        ensureRootfsCompatibilityLinks()
        configureRootfs()
        archive.delete()
    }

    private fun configureRootfs() {
        val aptConfDir = File("$rootfsDir/etc/apt/apt.conf.d")
        aptConfDir.mkdirs()
        File(aptConfDir, "01-proot").writeText(
            "APT::Sandbox::User \"root\";\nDpkg::Use-Pty \"0\";\n" +
            "Dpkg::Options { \"--force-confnew\"; \"--force-overwrite\"; };\n"
        )

        val dpkgConfDir = File("$rootfsDir/etc/dpkg/dpkg.cfg.d")
        dpkgConfDir.mkdirs()
        File(dpkgConfDir, "01-proot").writeText("force-unsafe-io\nno-debsig\nforce-overwrite\nforce-depends\n")

        listOf(
            "$rootfsDir/etc/ssl/certs", "$rootfsDir/usr/share/keyrings", "$rootfsDir/var/lib/dpkg/updates",
            "$rootfsDir/tmp/npm-cache", "$rootfsDir/usr/local/bin",
            "$rootfsDir/var/tmp", "$rootfsDir/run/lock", "$rootfsDir/dev/shm"
        ).forEach { File(it).mkdirs() }

        val machineId = File("$rootfsDir/etc/machine-id")
        if (!machineId.exists()) {
            machineId.parentFile?.mkdirs()
            machineId.writeText("10000000000000000000000000000000\n")
        }

        val policyRc = File("$rootfsDir/usr/sbin/policy-rc.d")
        policyRc.parentFile?.mkdirs()
        policyRc.writeText("#!/bin/sh\nexit 101\n")
        policyRc.setExecutable(true, false)

        registerAndroidUsers()
        fixBinPermissions()
    }

    private fun fixBinPermissions() {
        listOf("$rootfsDir/usr/bin", "$rootfsDir/usr/sbin", "$rootfsDir/bin", "$rootfsDir/sbin", "$rootfsDir/usr/local/bin")
            .forEach { path ->
                val dir = File(path)
                if (dir.exists() && dir.isDirectory) fixExecRecursive(dir)
            }
    }

    private fun fixExecRecursive(dir: File) {
        dir.listFiles()?.forEach { file ->
            if (file.isDirectory) fixExecRecursive(file)
            else if (file.isFile) {
                file.setReadable(true, false)
                file.setExecutable(true, false)
            }
        }
    }

    private fun registerAndroidUsers() {
        val uid = android.os.Process.myUid()
        val gid = uid
        val passwd = File("$rootfsDir/etc/passwd")
        if (passwd.exists()) {
            val content = passwd.readText()
            if (!content.contains("aid_android")) {
                passwd.appendText("aid_android:x:$uid:$gid:Android:/:/sbin/nologin\n")
            }
        }
    }

    fun writeResolvConf() {
        val configDir = File(this.configDir)
        configDir.mkdirs()
        File("$configDir/resolv.conf").writeText("nameserver 8.8.8.8\nnameserver 8.8.4.4\n")
    }

    fun setupFakeSysdata() {
        val procDir = File("$configDir/proc_fakes")
        procDir.mkdirs()
        File(procDir, "loadavg").writeText("0.12 0.07 0.02 2/165 765\n")
        File(procDir, "stat").writeText("cpu  1957 0 2877 93280 262 342 254 87 0 0\n")
        File(procDir, "uptime").writeText("124.08 932.80\n")
        File(procDir, "version").writeText("Linux version ${ProcessManager.FAKE_KERNEL_RELEASE} (proot@termux) ${ProcessManager.FAKE_KERNEL_VERSION}\n")
        File(procDir, "vmstat").writeText("nr_free_pages 1743136\n")
        File(procDir, "cap_last_cap").writeText("40\n")
        File(procDir, "max_user_watches").writeText("524288\n")
        File(procDir, "fips_enabled").writeText("0\n")

        val sysDir = File("$configDir/sys_fakes")
        sysDir.mkdirs()
        File(sysDir, "empty").writeText("")
    }

    private fun deleteRecursively(file: File) {
        if (file.isDirectory) file.listFiles()?.forEach { deleteRecursively(it) }
        file.delete()
    }
}
