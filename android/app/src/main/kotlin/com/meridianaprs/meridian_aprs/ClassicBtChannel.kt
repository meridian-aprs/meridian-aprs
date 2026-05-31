package com.meridianaprs.meridian_aprs

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Classic Bluetooth SPP (RFCOMM) bridge for Meridian's KISS TNC transport.
 *
 * Phase 1 spike (ADR-069): a deliberately thin native surface. The OS owns
 * pairing/bonding — this only lists already-bonded devices, opens an RFCOMM
 * socket to one of them over the standard SPP UUID, and pumps a raw byte stream
 * in both directions. KISS framing, AX.25, and reconnect all live in Dart.
 *
 * Contract:
 *   MethodChannel `meridian/classic_bt`:
 *     isSupported  -> Bool
 *     listPaired   -> List<Map{address,name}>
 *     connect      {address: String} -> null (outcome arrives via the rx event)
 *     disconnect   -> null
 *     write        {bytes: ByteArray} -> null
 *   EventChannel `meridian/classic_bt/rx` emits Map envelopes:
 *     {event:"data",  bytes: ByteArray}
 *     {event:"state", state:"connecting"|"connected"|"disconnected"|"error",
 *                     message: String?}
 */
class ClassicBtChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "meridian/classic_bt"
        const val EVENT_CHANNEL = "meridian/classic_bt/rx"

        // Standard Serial Port Profile UUID (RFCOMM).
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    // Active session state. `@Volatile` because the read/connect/write worker
    // threads and the platform thread all touch these.
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var readThread: Thread? = null

    // Bumped on every teardown. A connect worker captures the epoch when it
    // starts and bails if it changed by the time its blocking connect() returns,
    // so a stale worker can't resurrect a torn-down session or leak a socket.
    @Volatile private var connectEpoch = 0

    // Serializes writes so concurrent KISS frames cannot interleave on the
    // output stream. Single-threaded → FIFO ordering.
    private val writeExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    private fun adapter(): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // ---------------------------------------------------------------------------
    // MethodChannel
    // ---------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(adapter() != null)
            "listPaired" -> handleListPaired(result)
            "connect" -> handleConnect(call.argument<String>("address"), result)
            "disconnect" -> {
                teardown(emitState = true, reason = null)
                result.success(null)
            }
            "write" -> handleWrite(call.argument<ByteArray>("bytes"), result)
            else -> result.notImplemented()
        }
    }

    private fun handleListPaired(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            result.error("unsupported", "No Bluetooth adapter", null)
            return
        }
        try {
            val devices = adapter.bondedDevices.orEmpty().map {
                mapOf("address" to it.address, "name" to (it.name ?: it.address))
            }
            result.success(devices)
        } catch (e: SecurityException) {
            result.error("permission", "BLUETOOTH_CONNECT not granted", e.message)
        }
    }

    private fun handleConnect(address: String?, result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            result.error("unsupported", "No Bluetooth adapter", null)
            return
        }
        if (address.isNullOrEmpty()) {
            result.error("bad_args", "address required", null)
            return
        }
        // Tear down any prior session, then connect off the platform thread —
        // RFCOMM connect() blocks for seconds. The outcome is reported through
        // the rx event stream, not this Result (which returns immediately).
        teardown(emitState = false, reason = null)
        emitState("connecting", null)
        val myEpoch = connectEpoch

        Thread({
            // Discovery is heavy and slows/breaks an RFCOMM connect.
            try {
                adapter.cancelDiscovery()
            } catch (_: SecurityException) {
            }
            val sock: BluetoothSocket = try {
                adapter.getRemoteDevice(address)
                    .createRfcommSocketToServiceRecord(SPP_UUID)
            } catch (e: Exception) {
                emitState("error", e.message ?: "socket create failed")
                return@Thread
            }
            try {
                sock.connect()
            } catch (e: IOException) {
                try { sock.close() } catch (_: IOException) {}
                emitState("error", e.message ?: "connect failed")
                return@Thread
            } catch (e: SecurityException) {
                try { sock.close() } catch (_: IOException) {}
                emitState("error", "BLUETOOTH_CONNECT not granted")
                return@Thread
            }
            // A teardown (or newer connect) happened while we blocked in
            // connect() — this worker is stale. Close and bail without touching
            // shared state, so we neither resurrect a dead session nor leak the
            // socket.
            if (myEpoch != connectEpoch) {
                try { sock.close() } catch (_: IOException) {}
                return@Thread
            }
            socket = sock
            emitState("connected", null)
            startReadLoop(sock)
        }, "classic-bt-connect").start()

        result.success(null)
    }

    private fun handleWrite(bytes: ByteArray?, result: MethodChannel.Result) {
        val sock = socket
        if (sock == null || bytes == null) {
            result.error("not_connected", "No active SPP socket", null)
            return
        }
        // Enqueue on the single write worker so concurrent frames serialize and
        // cannot interleave on the output stream. The Result is completed only
        // after write+flush finishes, and always back on the platform thread.
        writeExecutor.execute {
            if (socket !== sock) {
                mainHandler.post {
                    result.error("not_connected", "Socket no longer active", null)
                }
                return@execute
            }
            try {
                sock.outputStream.write(bytes)
                sock.outputStream.flush()
                mainHandler.post { result.success(null) }
            } catch (e: IOException) {
                teardown(emitState = true, reason = e.message ?: "write failed")
                mainHandler.post {
                    result.error("write_failed", e.message ?: "write failed", null)
                }
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Read loop
    // ---------------------------------------------------------------------------

    private fun startReadLoop(sock: BluetoothSocket) {
        val t = Thread({
            val buffer = ByteArray(1024)
            val input = try {
                sock.inputStream
            } catch (e: IOException) {
                teardown(emitState = true, reason = e.message ?: "stream open failed")
                return@Thread
            }
            while (!Thread.currentThread().isInterrupted && socket === sock) {
                val n = try {
                    input.read(buffer)
                } catch (e: IOException) {
                    if (socket === sock) {
                        teardown(emitState = true, reason = e.message ?: "read failed")
                    }
                    return@Thread
                }
                if (n < 0) {
                    teardown(emitState = true, reason = "stream closed")
                    return@Thread
                }
                if (n > 0) {
                    emitData(buffer.copyOf(n))
                }
            }
        }, "classic-bt-read")
        readThread = t
        t.start()
    }

    // ---------------------------------------------------------------------------
    // Teardown
    // ---------------------------------------------------------------------------

    private fun teardown(emitState: Boolean, reason: String?) {
        connectEpoch++
        val sock = socket
        socket = null
        readThread?.interrupt()
        readThread = null
        if (sock != null) {
            try { sock.close() } catch (_: IOException) {}
        }
        if (emitState) {
            emitState(if (reason != null) "error" else "disconnected", reason)
        }
    }

    // ---------------------------------------------------------------------------
    // EventChannel — sink lives on the main thread
    // ---------------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emitData(bytes: ByteArray) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(mapOf("event" to "data", "bytes" to bytes)) }
    }

    private fun emitState(state: String, message: String?) {
        val sink = eventSink ?: return
        mainHandler.post {
            sink.success(mapOf("event" to "state", "state" to state, "message" to message))
        }
    }
}
