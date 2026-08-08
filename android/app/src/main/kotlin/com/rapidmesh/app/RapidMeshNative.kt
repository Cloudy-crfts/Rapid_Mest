package com.rapidmesh.app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Native Bluetooth layer for Rapid Mesh.
 *
 * flutter_blue_plus is central-only (no advertising / no GATT server) and
 * flutter_bluetooth_serial_plus is client-only (no RFCOMM server), so the
 * pieces needed for phone-to-phone discovery + connection are implemented
 * here natively:
 *
 *  - BLE advertising of the Rapid Mesh service UUID (so other Rapid Mesh
 *    phones see us in their filtered scan, and ONLY phones with the app).
 *  - An RFCOMM server socket (accepts incoming connection requests).
 *  - An RFCOMM client (dials out to discovered phones).
 *  - Raw byte streaming in both directions, pushed to the Dart side.
 *
 * Dart talks to this class over:
 *   MethodChannel "com.rapidmesh/native"  (start / stop / connect / send / reject)
 *   EventChannel  "com.rapidmesh/native/events" (incoming / connected / data / disconnected / error)
 */
@SuppressLint("MissingPermission")
class RapidMeshNative(private val context: Context, private val engine: FlutterEngine) {

    companion object {
        const val CHANNEL = "com.rapidmesh/native"
        const val EVENTS = "com.rapidmesh/native/events"
        // Must match AppConstants.bleServiceUuid in Dart.
        const val SERVICE_UUID = "a5f0c9e1-2b3d-4e5f-8a9b-0c1d2e3f4a5b"
        const val SERVICE_NAME = "Rapid Mesh"
    }

    private val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    private val eventChannel = EventChannel(engine.dartExecutor.binaryMessenger, EVENTS)
    private val handler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null

    private var started = false
    private var serverSocket: BluetoothServerSocket? = null
    private var accepting = false
    private val connections = ConcurrentHashMap<Int, BluetoothSocket>()
    private var nextConnectionId = 1
    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            emit("error", message = "advertising failed (code $errorCode)")
        }
    }

    fun register() {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        methodChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "start" -> result.success(start())
                "stop" -> {
                    stop()
                    result.success(true)
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.error("bad_args", "address missing", null)
                    } else {
                        connect(address)
                        result.success(true)
                    }
                }
                "send" -> {
                    val id = call.argument<Int>("id")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (id == null || bytes == null) {
                        result.error("bad_args", "id/bytes missing", null)
                    } else {
                        send(id, bytes)
                        result.success(true)
                    }
                }
                "reject" -> {
                    val id = call.argument<Int>("id")
                    if (id != null) reject(id)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getAdapter(): BluetoothAdapter? {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return null
        return manager.adapter
    }

    /** Starts the RFCOMM server + BLE advertising. Safe to call more than once. */
    private fun start(): Boolean {
        if (started) return true
        return try {
            val adapter = getAdapter() ?: return false
            if (!adapter.isEnabled) return false
            startServer(adapter)
            startAdvertising(adapter)
            started = true
            true
        } catch (e: Exception) {
            emit("error", message = "start failed: ${e.message}")
            false
        }
    }

    private fun startServer(adapter: BluetoothAdapter) {
        val uuid = UUID.fromString(SERVICE_UUID)
        serverSocket = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            adapter.listenUsingInsecureRfcommWithServiceRecord(SERVICE_NAME, uuid)
        } else {
            adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, uuid)
        }
        accepting = true
        Thread {
            while (accepting) {
                val socket = try {
                    serverSocket?.accept()
                } catch (e: Exception) {
                    null
                } ?: break
                val id = nextConnectionId++
                connections[id] = socket
                val remote = runCatching { socket.remoteDevice }.getOrNull()
                val name = remote?.name ?: remote?.address ?: "Device"
                val address = remote?.address ?: ""
                emit("incoming", id = id, name = name, address = address)
                startReadLoop(id, socket)
            }
        }.start()
    }

    private fun startAdvertising(adapter: BluetoothAdapter) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val advertiser: BluetoothLeAdvertiser = adapter.bluetoothLeAdvertiser ?: return
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid.fromString(SERVICE_UUID))
            .setIncludeDeviceName(true)
            .build()
        advertiser.startAdvertising(settings, data, advertiseCallback)
    }

    /** Dials an outgoing connection to a discovered Rapid Mesh phone. */
    private fun connect(address: String) {
        Thread {
            try {
                val adapter = getAdapter() ?: throw IllegalStateException("no adapter")
                val device = adapter.getRemoteDevice(address)
                val socket = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    device.createInsecureRfcommSocketToServiceRecord(UUID.fromString(SERVICE_UUID))
                } else {
                    device.createRfcommSocketToServiceRecord(UUID.fromString(SERVICE_UUID))
                }
                socket.connect()
                val id = nextConnectionId++
                connections[id] = socket
                emit("connected", id = id, address = address)
                startReadLoop(id, socket)
            } catch (e: Exception) {
                emit("error", message = "connect failed: ${e.message}")
            }
        }.start()
    }

    private fun startReadLoop(id: Int, socket: BluetoothSocket) {
        Thread {
            try {
                val input: InputStream = socket.inputStream
                val buffer = ByteArray(4096)
                while (accepting && socket.isConnected) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    emit("data", id = id, bytes = buffer.copyOf(read))
                }
            } catch (e: Exception) {
                // stream closed - handled below
            } finally {
                connections.remove(id)
                emit("disconnected", id = id)
            }
        }.start()
    }

    private fun send(id: Int, bytes: ByteArray) {
        try {
            val socket = connections[id] ?: return
            val out: OutputStream = socket.outputStream
            out.write(bytes)
            out.flush()
        } catch (e: Exception) {
            emit("error", message = "send failed: ${e.message}")
        }
    }

    private fun reject(id: Int) {
        try {
            connections.remove(id)?.close()
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun stop() {
        accepting = false
        started = false
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            // ignore
        }
        serverSocket = null
        for (socket in connections.values) {
            try {
                socket.close()
            } catch (e: Exception) {
                // ignore
            }
        }
        connections.clear()
        try {
            getAdapter()?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun emit(
        type: String,
        id: Int? = null,
        name: String? = null,
        address: String? = null,
        bytes: ByteArray? = null,
        message: String? = null
    ) {
        handler.post {
            val map = HashMap<String, Any?>()
            map["event"] = type
            if (id != null) map["id"] = id
            if (name != null) map["name"] = name
            if (address != null) map["address"] = address
            if (bytes != null) map["bytes"] = bytes
            if (message != null) map["message"] = message
            eventSink?.success(map)
        }
    }
}
