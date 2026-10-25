package com.example.quantum_ide

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.EOFException
import java.io.File
import java.io.InputStream
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Native Android USB Host (OTG) <-> ADB TCP Bridge.
 *
 * Allows Quantum IDE (running unrooted in PRoot) to detect, authorize, and debug
 * a second physical Android phone connected via a USB Type-C OTG cable, identical to a PC.
 *
 * How it works:
 * 1. Enumerates connected USB devices via Android's [UsbManager].
 * 2. Detects the ADB USB interface (Class 0xFF / 255, Subclass 0x42 / 66, Protocol 0x01 / 1).
 * 3. Requests Android system USB permission from the user ([UsbManager.requestPermission]).
 * 4. Opens [UsbDeviceConnection], claims the ADB interface, and starts a local TCP bridge on
 *    `127.0.0.1:5556` (and subsequent ports for multiple phones).
 * 5. Translates ADB TCP stream framing (24-byte header + payload) into discrete USB Bulk OUT / IN
 *    transfers expected by the target phone's `adbd` daemon.
 * 6. Automatically executes `adb connect 127.0.0.1:5556` inside PRoot and exposes a local control
 *    HTTP endpoint on `127.0.0.1:5038` so `quantum-device` CLI and AI tools can inspect & trigger OTG.
 */
class UsbAdbBridge(
    private val context: Context,
    private val filesDir: String,
    private val processManager: ProcessManager
) {
    companion object {
        private const val TAG = "UsbAdbBridge"
        private const val ADB_CLASS = 255
        private const val ADB_SUBCLASS = 66
        private const val ADB_PROTOCOL = 1
        private const val FASTBOOT_PROTOCOL = 3

        const val BASE_BRIDGE_PORT = 5556
        const val CONTROL_PORT = 5038
        private const val MAX_ADB_PAYLOAD = 4 * 1024 * 1024 // 4 MB safety cap
        private const val MAX_BULK_CHUNK = 16384 // 16 KB (multiple of 512 and 1024 wMaxPacketSize)
    }

    private val actionUsbPermission = "${context.packageName}.USB_PERMISSION"
    private val usbManager: UsbManager? =
        context.getSystemService(Context.USB_SERVICE) as? UsbManager

    private val activeBridges = ConcurrentHashMap<String, DeviceBridgeSession>()
    private val pendingPermissions = ConcurrentHashMap.newKeySet<String>()
    private val running = AtomicBoolean(false)
    private var controlServer: ServerSocket? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            when (action) {
                actionUsbPermission -> {
                    val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (device != null) {
                        pendingPermissions.remove(device.deviceName)
                        Log.i(TAG, "USB permission result for ${device.deviceName}: granted=$granted")
                        if (granted || usbManager?.hasPermission(device) == true) {
                            startBridgeForDevice(device)
                        }
                    }
                    syncStatusFile()
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }
                    Log.i(TAG, "USB device attached: ${device?.deviceName}")
                    if (device != null) {
                        handleAttachedDevice(device, autoRequestPermission = true)
                    }
                    syncStatusFile()
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device: UsbDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    }
                    Log.i(TAG, "USB device detached: ${device?.deviceName}")
                    if (device != null) {
                        pendingPermissions.remove(device.deviceName)
                        stopBridgeForDevice(device.deviceName)
                    }
                    syncStatusFile()
                }
            }
        }
    }

    fun start() {
        if (!running.compareAndSet(false, true)) return

        try {
            val filter = IntentFilter().apply {
                addAction(actionUsbPermission)
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                context.registerReceiver(usbReceiver, filter)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register USB receiver: ${e.message}")
        }

        startControlServer()

        // Initial scan for already attached OTG devices
        Thread {
            try {
                scanAndConnectUsbDevices(autoRequestPermission = true)
            } catch (e: Exception) {
                Log.e(TAG, "Initial USB scan error: ${e.message}")
            }
        }.start()
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (_: Exception) {}
        try {
            controlServer?.close()
        } catch (_: Exception) {}
        for (key in activeBridges.keys().toList()) {
            stopBridgeForDevice(key)
        }
    }

    fun isUsbHostSupported(): Boolean {
        return try {
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Scans all connected USB devices, optionally requests permission & starts ADB TCP bridge.
     * Returns structured list of physical USB devices and their ADB bridge status.
     */
    fun scanAndConnectUsbDevices(autoRequestPermission: Boolean = true): List<Map<String, Any?>> {
        val manager = usbManager ?: return emptyList()
        val rawMap = try {
            manager.deviceList ?: emptyMap()
        } catch (_: Exception) {
            emptyMap()
        }

        // Clean up bridges for disconnected devices
        for (activeKey in activeBridges.keys().toList()) {
            if (!rawMap.containsKey(activeKey)) {
                stopBridgeForDevice(activeKey)
            }
        }

        val results = mutableListOf<Map<String, Any?>>()

        for (dev in rawMap.values) {
            val adbIntf = findAdbInterface(dev)
            val fastbootIntf = findFastbootInterface(dev)
            val hasAdb = adbIntf != null
            val hasFastboot = fastbootIntf != null
            var hasPerm = try { manager.hasPermission(dev) } catch (_: Exception) { false }

            if (autoRequestPermission && !hasPerm && (hasAdb || dev.deviceClass != UsbConstants.USB_CLASS_HUB)) {
                requestUsbPermission(dev)
                hasPerm = try { manager.hasPermission(dev) } catch (_: Exception) { false }
            }

            if (hasPerm && hasAdb) {
                startBridgeForDevice(dev)
            }

            val session = activeBridges[dev.deviceName]
            val manufacturer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try { dev.manufacturerName ?: "" } catch (_: Exception) { "" }
            } else ""
            val product = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try { dev.productName ?: "" } catch (_: Exception) { "" }
            } else ""
            val serial = if (hasPerm && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                try { dev.serialNumber ?: "" } catch (_: Exception) { "" }
            } else ""

            val modeDescription = when {
                hasAdb && session != null -> "ADB (Отладка по USB активна • Мост 127.0.0.1:${session.port})"
                hasAdb && !hasPerm -> "ADB (Ожидание разрешения USB на экране)"
                hasAdb -> "ADB (Отладка по USB включена)"
                hasFastboot -> "Fastboot Mode"
                else -> "Зарядка / MTP (Включите «Отладку по USB» на втором телефоне)"
            }

            results.add(
                mapOf(
                    "deviceName" to dev.deviceName,
                    "vendorId" to dev.vendorId,
                    "productId" to dev.productId,
                    "vendorHex" to String.format("%04x", dev.vendorId),
                    "productHex" to String.format("%04x", dev.productId),
                    "manufacturer" to manufacturer,
                    "product" to product,
                    "serial" to serial,
                    "deviceClass" to dev.deviceClass,
                    "interfaceCount" to dev.interfaceCount,
                    "hasAdbInterface" to hasAdb,
                    "hasFastbootInterface" to hasFastboot,
                    "hasPermission" to hasPerm,
                    "bridgeActive" to (session != null && session.isRunning()),
                    "bridgePort" to (session?.port ?: 0),
                    "bridgeAddress" to (if (session != null) "127.0.0.1:${session.port}" else ""),
                    "modeDescription" to modeDescription
                )
            )
        }

        syncStatusFile(results)
        return results
    }

    private fun handleAttachedDevice(device: UsbDevice, autoRequestPermission: Boolean) {
        val manager = usbManager ?: return
        val hasPerm = try { manager.hasPermission(device) } catch (_: Exception) { false }
        val hasAdb = findAdbInterface(device) != null
        if (hasPerm && hasAdb) {
            startBridgeForDevice(device)
        } else if (autoRequestPermission && !hasPerm) {
            requestUsbPermission(device)
        }
    }

    private fun requestUsbPermission(device: UsbDevice) {
        val manager = usbManager ?: return
        if (!pendingPermissions.add(device.deviceName)) {
            return
        }
        try {
            val intent = Intent(actionUsbPermission).apply {
                setPackage(context.packageName)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(context, device.deviceId, intent, flags)
            manager.requestPermission(device, pendingIntent)
        } catch (e: Exception) {
            pendingPermissions.remove(device.deviceName)
            Log.e(TAG, "Error requesting USB permission: ${e.message}")
        }
    }

    private fun findAdbInterface(device: UsbDevice): UsbInterface? {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == ADB_CLASS &&
                intf.interfaceSubclass == ADB_SUBCLASS &&
                intf.interfaceProtocol == ADB_PROTOCOL
            ) {
                return intf
            }
        }
        return null
    }

    private fun findFastbootInterface(device: UsbDevice): UsbInterface? {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass == ADB_CLASS &&
                intf.interfaceSubclass == ADB_SUBCLASS &&
                intf.interfaceProtocol == FASTBOOT_PROTOCOL
            ) {
                return intf
            }
        }
        return null
    }

    @Synchronized
    private fun startBridgeForDevice(device: UsbDevice) {
        val existing = activeBridges[device.deviceName]
        if (existing != null && existing.isRunning()) {
            return
        }
        existing?.stop()

        val manager = usbManager ?: return
        val adbIntf = findAdbInterface(device) ?: return

        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        for (i in 0 until adbIntf.endpointCount) {
            val ep = adbIntf.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_IN) {
                    inEp = ep
                } else if (ep.direction == UsbConstants.USB_DIR_OUT) {
                    outEp = ep
                }
            }
        }

        if (inEp == null || outEp == null) {
            Log.e(TAG, "ADB interface on ${device.deviceName} missing bulk IN/OUT endpoints")
            return
        }

        val usedPorts = activeBridges.values.map { it.port }.toSet()
        var sessionStarted = false

        // Try ports starting from BASE_BRIDGE_PORT up to BASE_BRIDGE_PORT + 20
        for (portOffset in 0..20) {
            val candidatePort = BASE_BRIDGE_PORT + portOffset
            if (usedPorts.contains(candidatePort)) continue

            val session = DeviceBridgeSession(
                device = device,
                usbManager = manager,
                adbInterface = adbIntf,
                inEndpoint = inEp,
                outEndpoint = outEp,
                port = candidatePort,
                onDisconnected = {
                    activeBridges.remove(device.deviceName)
                    syncStatusFile()
                }
            )

            if (session.start()) {
                activeBridges[device.deviceName] = session
                Log.i(TAG, "Started USB-ADB bridge for ${device.deviceName} on 127.0.0.1:$candidatePort")
                syncStatusFile()

                // Auto-connect PRoot ADB server to the newly opened USB bridge
                Thread {
                    try {
                        Thread.sleep(250)
                        processManager.runInProotSync(
                            "adb start-server >/dev/null 2>&1 || true; adb connect 127.0.0.1:$candidatePort >/dev/null 2>&1 || true",
                            timeoutSeconds = 15
                        )
                    } catch (e: Exception) {
                        Log.w(TAG, "Auto adb connect warning: ${e.message}")
                    }
                }.start()

                sessionStarted = true
                break
            } else {
                Log.w(TAG, "Port $candidatePort unavailable or failed for ${device.deviceName}, trying next port...")
            }
        }

        if (!sessionStarted) {
            Log.e(TAG, "Could not start USB-ADB bridge for ${device.deviceName} on any port")
        }
    }

    private fun stopBridgeForDevice(deviceName: String) {
        val session = activeBridges.remove(deviceName) ?: return
        val port = session.port
        session.stop()
        Thread {
            try {
                processManager.runInProotSync("adb disconnect 127.0.0.1:$port >/dev/null 2>&1 || true", timeoutSeconds = 10)
            } catch (_: Exception) {}
        }.start()
    }

    /**
     * Writes current USB OTG status to `/tmp/quantum_usb_otg.json` inside PRoot so CLI tools
     * (`quantum-device`) and AI agents can read live hardware state immediately.
     */
    fun syncStatusFile(cachedDevices: List<Map<String, Any?>>? = null) {
        try {
            val json = buildStatusJson(cachedDevices)
            val targets = listOf(
                File("$filesDir/rootfs/ubuntu/tmp/quantum_usb_otg.json"),
                File("$filesDir/tmp/quantum_usb_otg.json")
            )
            for (f in targets) {
                f.parentFile?.mkdirs()
                f.writeText(json.toString(2))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write quantum_usb_otg.json: ${e.message}")
        }
    }

    fun buildStatusJson(cachedDevices: List<Map<String, Any?>>? = null): JSONObject {
        val devices = cachedDevices ?: scanAndConnectUsbDevices(autoRequestPermission = false)
        val devArray = JSONArray()
        var adbCapableCount = 0
        val bridgePorts = mutableListOf<String>()

        for (d in devices) {
            if (d["hasAdbInterface"] == true) adbCapableCount++
            val addr = d["bridgeAddress"] as? String ?: ""
            if (addr.isNotEmpty()) bridgePorts.add(addr)
            devArray.put(JSONObject(d))
        }

        return JSONObject().apply {
            put("isUsbHostSupported", isUsbHostSupported())
            put("usbDeviceCount", devices.size)
            put("adbUsbDeviceCount", adbCapableCount)
            put("activeBridgeAddresses", JSONArray(bridgePorts))
            put("devices", devArray)
            put("timestamp", System.currentTimeMillis())
        }
    }

    /**
     * Lightweight HTTP control server on `127.0.0.1:5038` for `quantum-device` CLI inside PRoot.
     */
    private fun startControlServer() {
        Thread({
            try {
                val server = ServerSocket(CONTROL_PORT, 8, InetAddress.getByName("127.0.0.1"))
                controlServer = server
                while (running.get() && !server.isClosed) {
                    val client = try {
                        server.accept()
                    } catch (_: Exception) {
                        break
                    }
                    Thread { handleControlClient(client) }.start()
                }
            } catch (e: Exception) {
                Log.w(TAG, "Control server stopped: ${e.message}")
            }
        }, "UsbAdbControlServer").start()
    }

    private fun handleControlClient(client: Socket) {
        client.use { sock ->
            sock.soTimeout = 5000
            val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
            val reqLine = reader.readLine() ?: return
            val path = reqLine.split(" ").getOrNull(1) ?: "/status"

            val responseJson = when {
                path.startsWith("/connect") -> {
                    val list = scanAndConnectUsbDevices(autoRequestPermission = true)
                    buildStatusJson(list)
                }
                path.startsWith("/disconnect") -> {
                    for (k in activeBridges.keys().toList()) {
                        stopBridgeForDevice(k)
                    }
                    buildStatusJson()
                }
                else -> {
                    val list = scanAndConnectUsbDevices(autoRequestPermission = true)
                    buildStatusJson(list)
                }
            }

            val body = responseJson.toString(2).toByteArray(Charsets.UTF_8)
            val header = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: application/json; charset=utf-8\r\n" +
                "Content-Length: ${body.size}\r\n" +
                "Connection: close\r\n\r\n"
            val out = sock.getOutputStream()
            out.write(header.toByteArray(Charsets.UTF_8))
            out.write(body)
            out.flush()
        }
    }

    /**
     * Manages a single USB OTG phone's ADB bulk endpoints and proxies them to `127.0.0.1:<port>`.
     */
    private inner class DeviceBridgeSession(
        val device: UsbDevice,
        private val usbManager: UsbManager,
        private val adbInterface: UsbInterface,
        private val inEndpoint: UsbEndpoint,
        private val outEndpoint: UsbEndpoint,
        val port: Int,
        private val onDisconnected: () -> Unit
    ) {
        private val active = AtomicBoolean(false)
        private var serverSocket: ServerSocket? = null
        private var currentClient: Socket? = null
        private var usbConnection: UsbDeviceConnection? = null
        private val writeLock = Any()

        fun isRunning(): Boolean = active.get() && serverSocket?.isClosed == false

        fun start(): Boolean {
            return try {
                val conn = usbManager.openDevice(device)
                if (conn == null) {
                    Log.e(TAG, "usbManager.openDevice returned null for ${device.deviceName}")
                    return false
                }
                if (!conn.claimInterface(adbInterface, true)) {
                    Log.e(TAG, "Failed to claim ADB interface on ${device.deviceName}")
                    conn.close()
                    return false
                }
                usbConnection = conn
                val s = ServerSocket()
                s.reuseAddress = true
                s.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 4)
                serverSocket = s
                active.set(true)

                Thread({ acceptLoop() }, "UsbAdbAccept-$port").start()
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start DeviceBridgeSession on port $port: ${e.message}")
                stop()
                false
            }
        }

        private fun acceptLoop() {
            while (active.get()) {
                val client = try {
                    serverSocket?.accept() ?: break
                } catch (_: Exception) {
                    break
                }

                try {
                    currentClient?.close()
                } catch (_: Exception) {}
                currentClient = client

                try {
                    client.tcpNoDelay = true
                    client.keepAlive = true
                } catch (_: Exception) {}

                val sessionActive = AtomicBoolean(true)

                // Thread 1: TCP (ADB Server) -> USB Bulk OUT (Target Phone adbd)
                val tcpToUsb = Thread({
                    try {
                        pumpTcpToUsb(client, sessionActive)
                    } catch (e: Exception) {
                        Log.d(TAG, "TCP->USB ended: ${e.message}")
                    } finally {
                        sessionActive.set(false)
                        try { client.close() } catch (_: Exception) {}
                    }
                }, "TcpToUsb-$port")

                // Thread 2: USB Bulk IN (Target Phone adbd) -> TCP (ADB Server)
                val usbToTcp = Thread({
                    try {
                        pumpUsbToTcp(client, sessionActive)
                    } catch (e: Exception) {
                        Log.d(TAG, "USB->TCP ended: ${e.message}")
                    } finally {
                        sessionActive.set(false)
                        try { client.close() } catch (_: Exception) {}
                    }
                }, "UsbToTcp-$port")

                tcpToUsb.start()
                usbToTcp.start()
            }
        }

        /**
         * Reads 24-byte ADB headers + payloads from TCP socket and sends them as discrete
         * USB Bulk OUT transfers (1st transfer = 24-byte header, 2nd transfer = payload).
         */
        private fun pumpTcpToUsb(socket: Socket, sessionActive: AtomicBoolean) {
            val input = socket.getInputStream()
            val header = ByteArray(24)

            while (active.get() && sessionActive.get() && !socket.isClosed) {
                readFully(input, header, 0, 24)

                val bb = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                val command = bb.getInt(0)
                val dataLength = bb.getInt(12)
                val magic = bb.getInt(20)

                if (magic != command.inv() || dataLength < 0 || dataLength > MAX_ADB_PAYLOAD) {
                    throw IllegalStateException("Invalid ADB header from TCP: cmd=0x${Integer.toHexString(command)} len=$dataLength")
                }

                val payload = if (dataLength > 0) {
                    ByteArray(dataLength).also { readFully(input, it, 0, dataLength) }
                } else {
                    null
                }

                val conn = usbConnection ?: throw IllegalStateException("USB connection closed")
                synchronized(writeLock) {
                    // Transfer 1: 24-byte header
                    if (!writeBulkAll(conn, outEndpoint, header, 24)) {
                        throw IllegalStateException("USB bulk write failed for 24-byte ADB header")
                    }
                    // Transfer 2: Payload (if data_length > 0)
                    if (payload != null && payload.isNotEmpty()) {
                        if (!writeBulkAll(conn, outEndpoint, payload, payload.size)) {
                            throw IllegalStateException("USB bulk write failed for ADB payload (${payload.size} bytes)")
                        }
                    }
                }
            }
        }

        /**
         * Reads 24-byte ADB headers + payloads from USB Bulk IN endpoint and writes them to TCP socket.
         */
        private fun pumpUsbToTcp(socket: Socket, sessionActive: AtomicBoolean) {
            val output = socket.getOutputStream()
            val maxPacket = inEndpoint.maxPacketSize.coerceAtLeast(512)
            val headerTransferBuf = ByteArray(maxPacket)

            while (active.get() && sessionActive.get() && !socket.isClosed) {
                val conn = usbConnection ?: break
                val n = conn.bulkTransfer(inEndpoint, headerTransferBuf, maxPacket, 1000)
                if (n < 0) {
                    // Verify device is still attached on timeout/error
                    if (usbManager.deviceList?.containsKey(device.deviceName) != true) {
                        stop()
                        onDisconnected()
                        break
                    }
                    continue
                }
                if (n < 24) {
                    continue
                }

                val bb = ByteBuffer.wrap(headerTransferBuf, 0, 24).order(ByteOrder.LITTLE_ENDIAN)
                val command = bb.getInt(0)
                val dataLength = bb.getInt(12)
                val magic = bb.getInt(20)

                if (magic != command.inv() || dataLength < 0 || dataLength > MAX_ADB_PAYLOAD) {
                    continue
                }

                // Write 24-byte header to TCP
                output.write(headerTransferBuf, 0, 24)

                if (dataLength > 0) {
                    var remaining = dataLength
                    // If the initial bulk transfer already included some payload bytes beyond 24
                    if (n > 24) {
                        val extra = (n - 24).coerceAtMost(remaining)
                        output.write(headerTransferBuf, 24, extra)
                        remaining -= extra
                    }

                    val chunkBuf = ByteArray(MAX_BULK_CHUNK)
                    while (remaining > 0 && active.get() && sessionActive.get()) {
                        val aligned = ((remaining + maxPacket - 1) / maxPacket) * maxPacket
                        val reqLen = aligned.coerceAtMost(MAX_BULK_CHUNK)
                        val r = conn.bulkTransfer(inEndpoint, chunkBuf, reqLen, 5000)
                        if (r <= 0) {
                            throw EOFException("USB bulk read failed while reading ADB payload (remaining=$remaining)")
                        }
                        val toWrite = r.coerceAtMost(remaining)
                        output.write(chunkBuf, 0, toWrite)
                        remaining -= toWrite
                    }
                }
                output.flush()
            }
        }

        private fun writeBulkAll(
            conn: UsbDeviceConnection,
            ep: UsbEndpoint,
            data: ByteArray,
            length: Int
        ): Boolean {
            var offset = 0
            while (offset < length) {
                val chunk = (length - offset).coerceAtMost(MAX_BULK_CHUNK)
                val sent = if (offset == 0 && chunk == length) {
                    conn.bulkTransfer(ep, data, length, 5000)
                } else {
                    val slice = data.copyOfRange(offset, offset + chunk)
                    conn.bulkTransfer(ep, slice, chunk, 5000)
                }
                if (sent <= 0) {
                    return false
                }
                offset += sent
            }
            return true
        }

        private fun readFully(input: InputStream, buf: ByteArray, offset: Int, length: Int) {
            var total = 0
            while (total < length) {
                val r = input.read(buf, offset + total, length - total)
                if (r < 0) throw EOFException("TCP stream closed")
                total += r
            }
        }

        fun stop() {
            active.set(false)
            try { currentClient?.close() } catch (_: Exception) {}
            try { serverSocket?.close() } catch (_: Exception) {}
            try {
                usbConnection?.releaseInterface(adbInterface)
            } catch (_: Exception) {}
            try {
                usbConnection?.close()
            } catch (_: Exception) {}
            serverSocket = null
            currentClient = null
            usbConnection = null
        }
    }
}
