package com.nicospencer.butane_android

import ButaneFlutterApi
import ButaneHostApi
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class ButaneAndroidPlugin : FlutterPlugin, ButaneHostApi, ActivityAware {
    private var flutterApi: ButaneFlutterApi? = null
    private var scope: CoroutineScope? = null

    private var applicationContext: Context? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private val stateReceivers = mutableMapOf<String?, BroadcastReceiver>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ButaneHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = ButaneFlutterApi(binding.binaryMessenger)
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        applicationContext = binding.applicationContext
        val bluetoothManager =
            binding.applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ButaneHostApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
        scope?.cancel()
        scope = null
        // Unregister all state receivers
        stateReceivers.values.forEach { receiver ->
            try {
                applicationContext?.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // Already unregistered
            }
        }
        stateReceivers.clear()
        applicationContext = null
        bluetoothAdapter = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}
    override fun onDetachedFromActivity() {}

    companion object {
        fun mapAdapterState(adapterState: Int): ClientState {
            return when (adapterState) {
                BluetoothAdapter.STATE_OFF -> ClientState.POWERED_OFF
                BluetoothAdapter.STATE_TURNING_ON -> ClientState.POWERED_OFF
                BluetoothAdapter.STATE_ON -> ClientState.POWERED_ON
                BluetoothAdapter.STATE_TURNING_OFF -> ClientState.POWERED_ON
                else -> ClientState.UNKNOWN
            }
        }
    }

    private fun <T> notImplemented(callback: (Result<T>) -> Unit) {
        callback(
            Result.failure(
                FlutterError(
                    "not-implemented",
                    "Not yet implemented on Android",
                    null,
                ),
            ),
        )
    }

    // Central APIs

    override fun state(session: ClientSession?, callback: (Result<ClientState>) -> Unit) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            callback(Result.success(ClientState.UNSUPPORTED))
            return
        }

        val clientId = session?.clientIdentifier

        // Register state receiver if not already registered for this client
        if (!stateReceivers.containsKey(clientId)) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                        val newState = intent.getIntExtra(
                            BluetoothAdapter.EXTRA_STATE,
                            BluetoothAdapter.ERROR,
                        )
                        val clientState = mapAdapterState(newState)
                        flutterApi?.onClientState(clientId, clientState) {}
                    }
                }
            }
            val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
            applicationContext?.registerReceiver(receiver, filter)
            stateReceivers[clientId] = receiver
        }

        callback(Result.success(mapAdapterState(adapter.state)))
    }

    override fun scan(
        session: ClientSession?,
        forServices: List<String>?,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun cancelScan(session: ClientSession?, callback: (Result<Unit>) -> Unit) =
        notImplemented(callback)

    override fun peripherals(
        session: ClientSession?,
        peripheralIdentifiers: List<String>,
        callback: (Result<List<Peripheral>>) -> Unit,
    ) = notImplemented(callback)

    override fun connectedPeripherals(
        session: ClientSession?,
        serviceUuids: List<String>,
        callback: (Result<List<Peripheral>>) -> Unit,
    ) = notImplemented(callback)

    override fun connect(session: PeripheralSession, callback: (Result<Unit>) -> Unit) =
        notImplemented(callback)

    override fun cancelConnection(
        session: PeripheralSession,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun connectionState(
        session: PeripheralSession,
        callback: (Result<ConnectionState>) -> Unit,
    ) = notImplemented(callback)

    override fun discoverServices(
        session: PeripheralSession,
        serviceUuids: List<String>?,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun services(
        session: PeripheralSession,
        callback: (Result<List<Service>>) -> Unit,
    ) = notImplemented(callback)

    override fun discoverCharacteristics(
        session: PeripheralSession,
        serviceUuid: String,
        characteristicUuids: List<String>?,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun characteristics(
        session: PeripheralSession,
        serviceUuid: String,
        callback: (Result<List<Characteristic>>) -> Unit,
    ) = notImplemented(callback)

    override fun readCharacteristic(
        session: PeripheralSession,
        serviceUuid: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit,
    ) = notImplemented(callback)

    override fun writeCharacteristic(
        session: PeripheralSession,
        serviceUuid: String,
        characteristicUuid: String,
        value: ByteArray,
        withoutResponse: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun observeCharacteristic(
        observe: Boolean,
        session: PeripheralSession,
        serviceUuid: String,
        characteristicUuid: String,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun readDescriptor(
        session: PeripheralSession,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
        callback: (Result<ByteArray>) -> Unit,
    ) = notImplemented(callback)

    override fun writeDescriptor(
        session: PeripheralSession,
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun readRssi(session: PeripheralSession, callback: (Result<Long>) -> Unit) =
        notImplemented(callback)

    override fun requestMtu(
        session: PeripheralSession,
        mtu: Long,
        callback: (Result<Long>) -> Unit,
    ) = notImplemented(callback)

    // Peripheral Manager APIs

    override fun peripheralManagerState(
        session: PeripheralManagerSession,
        callback: (Result<ClientState>) -> Unit,
    ) = notImplemented(callback)

    override fun startAdvertising(
        session: PeripheralManagerSession,
        localName: String?,
        serviceUuids: List<String>?,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun stopAdvertising(
        session: PeripheralManagerSession,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun addService(
        session: PeripheralManagerSession,
        service: MutableService,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun removeService(
        session: PeripheralManagerSession,
        serviceUuid: String,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun removeAllServices(
        session: PeripheralManagerSession,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun respondToRequest(
        session: PeripheralManagerSession,
        requestId: Long,
        result: AttResult,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit,
    ) = notImplemented(callback)

    override fun updateValue(
        session: PeripheralManagerSession,
        serviceUuid: String,
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Boolean>) -> Unit,
    ) = notImplemented(callback)
}
