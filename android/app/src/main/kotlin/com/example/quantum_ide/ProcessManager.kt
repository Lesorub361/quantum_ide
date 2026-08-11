package com.example.quantum_ide

import java.io.BufferedReader
import java.io.InputStreamReader

class ProcessManager(
    private val filesDir: String,
    private val nativeLibDir: String
) {
    private val rootfsDir get() = "$filesDir/rootfs/ubuntu"
    private val tmpDir get() = "$filesDir/tmp"
    private val homeDir get() = "$filesDir/home"
    private val configDir get() = "$filesDir/config"
    private val libDir get() = "$filesDir/lib"

    companion object {
        const val FAKE_KERNEL_RELEASE = "6.17.0-PRoot-Distro"
        const val FAKE_KERNEL_VERSION =
            "#1 SMP PREEMPT_DYNAMIC Fri, 10 Oct 2025 00:00:00 +0000"
    }

    fun getProotPath(): String = "$nativeLibDir/libproot.so"

    private fun prootEnv(): Map<String, String> = mapOf(
        "PROOT_TMP_DIR" to tmpDir,
        "PROOT_LOADER" to "$nativeLibDir/libprootloader.so",
        "PROOT_LOADER_32" to "$nativeLibDir/libprootloader32.so",
        "LD_LIBRARY_PATH" to "$libDir:$nativeLibDir",
    )

    private fun commonProotFlags(): List<String> {
        val prootPath = getProotPath()
        val procFakes = "$configDir/proc_fakes"
        val sysFakes = "$configDir/sys_fakes"

        return listOf(
            prootPath,
            "--link2symlink",
            "-L",
            "--kill-on-exit",
            "--rootfs=$rootfsDir",
            "--cwd=/root",
            "--bind=/dev",
            "--bind=/dev/urandom:/dev/random",
            "--bind=/proc",
            "--bind=/proc/self/fd:/dev/fd",
            "--bind=/proc/self/fd/0:/dev/stdin",
            "--bind=/proc/self/fd/1:/dev/stdout",
            "--bind=/proc/self/fd/2:/dev/stderr",
            "--bind=/sys",
            "--bind=$procFakes/loadavg:/proc/loadavg",
            "--bind=$procFakes/stat:/proc/stat",
            "--bind=$procFakes/uptime:/proc/uptime",
            "--bind=$procFakes/version:/proc/version",
            "--bind=$procFakes/vmstat:/proc/vmstat",
            "--bind=$procFakes/cap_last_cap:/proc/sys/kernel/cap_last_cap",
            "--bind=$procFakes/max_user_watches:/proc/sys/fs/inotify/max_user_watches",
            "--bind=$procFakes/fips_enabled:/proc/sys/crypto/fips_enabled",
            "--bind=$rootfsDir/tmp:/dev/shm",
            "--bind=$sysFakes/empty:/sys/fs/selinux",
            "--bind=$configDir/resolv.conf:/etc/resolv.conf",
            "--bind=$homeDir:/root/home",
            "--bind=$filesDir/projects:/root/projects",
            "--bind=/storage/emulated/0:/sdcard",
            "--bind=/storage/emulated/0/QuantumIDE:/root/projects/external",
        )
    }

    fun buildInstallCommand(command: String): List<String> {
        val flags = commonProotFlags().toMutableList()
        flags.add(1, "--root-id")
        flags.add(2, "--kernel-release=$FAKE_KERNEL_RELEASE")

        flags.addAll(listOf(
            "/usr/bin/env", "-i",
            "HOME=/root",
            "LANG=C.UTF-8",
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/flutter/bin",
            "TERM=xterm-256color",
            "TMPDIR=/tmp",
            "FLUTTER_ALLOW_SU_ROOT=true",
            "DEBIAN_FRONTEND=noninteractive",
            "npm_config_cache=/tmp/npm-cache",
            "/bin/bash", "-c",
            command,
        ))

        return flags
    }

    fun buildGatewayCommand(command: String): List<String> {
        val flags = commonProotFlags().toMutableList()
        val arch = ArchUtils.getArch()
        val machine = when (arch) {
            "arm" -> "armv7l"
            else -> arch
        }

        flags.add(1, "--change-id=0:0")
        flags.add(2, "--sysvipc")
        val kernelRelease = "\\Linux\\localhost\\$FAKE_KERNEL_RELEASE" +
            "\\$FAKE_KERNEL_VERSION\\$machine\\localdomain\\-1\\"
        flags.add(3, "--kernel-release=$kernelRelease")

        flags.addAll(listOf(
            "/usr/bin/env", "-i",
            "HOME=/root",
            "USER=root",
            "LANG=C.UTF-8",
            "FLUTTER_ALLOW_SU_ROOT=true",
            "PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=xterm-256color",
            "TMPDIR=/tmp",
            "CHOKIDAR_USEPOLLING=true",
            "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt",
            "UV_USE_IO_URING=0",
            "/bin/bash", "-c",
            command,
        ))

        return flags
    }

    fun runInProotSync(command: String, timeoutSeconds: Long = 900): String {
        val cmd = buildInstallCommand(command)
        val env = prootEnv()

        val pb = ProcessBuilder(cmd)
        pb.environment().clear()
        pb.environment().putAll(env)
        pb.redirectErrorStream(true)

        val process = pb.start()
        val output = StringBuilder()
        val reader = BufferedReader(InputStreamReader(process.inputStream))

        var line: String?
        while (reader.readLine().also { line = it } != null) {
            val l = line ?: continue
            if (l.contains("proot warning") || l.contains("can't sanitize")) {
                continue
            }
            output.appendLine(l)
        }

        val exited = process.waitFor(timeoutSeconds, java.util.concurrent.TimeUnit.SECONDS)
        if (!exited) {
            process.destroyForcibly()
            throw RuntimeException("Command timed out after ${timeoutSeconds}s")
        }

        val exitCode = process.exitValue()
        if (exitCode != 0) {
            throw RuntimeException("Command failed (exit code $exitCode): ${output.toString().takeLast(1000)}")
        }

        return output.toString()
    }

    fun startProotProcess(command: String): Process {
        val cmd = buildGatewayCommand(command)
        val env = prootEnv()

        val pb = ProcessBuilder(cmd)
        pb.environment().clear()
        pb.environment().putAll(env)
        pb.redirectErrorStream(false)

        return pb.start()
    }
}
