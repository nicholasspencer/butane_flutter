package com.nicospencer.butane_android

import ButaneFlutterApi
import ButaneHostApi
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult as AndroidScanResult
import android.bluetooth.le.ScanSettings
import android.os.ParcelUuid
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
import java.util.UUID

class ButaneAndroidPlugin : FlutterPlugin, ButaneHostApi, ActivityAware {
    private var flutterApi: ButaneFlutterApi? = null
    private var scope: CoroutineScope? = null

    private var applicationContext: Context? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private val stateReceivers = mutableMapOf<String?, BroadcastReceiver>()

    private var scanCallback: ScanCallback? = null
    private val discoveredPeripherals = mutableMapOf<String, BluetoothDevice>()

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
        // Stop any active scan
        scanCallback?.let { cb ->
            bluetoothAdapter?.bluetoothLeScanner?.stopScan(cb)
            scanCallback = null
        }
        discoveredPeripherals.clear()
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
    ) {
        val scanner = bluetoothAdapter?.bluetoothLeScanner
        if (scanner == null) {
            callback(Result.failure(FlutterError("unavailable", "BLE scanner not available", null)))
            return
        }

        // Stop any existing scan
        scanCallback?.let { scanner.stopScan(it) }

        val scanCb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: AndroidScanResult) {
                val device = result.device
                val address = device.address
                discoveredPeripherals[address] = device

                val peripheralSession = PeripheralSession(
                    peripheralIdentifier = address,
                    clientIdentifier = session?.clientIdentifier,
                )
                val peripheral = Peripheral(
                    session = peripheralSession,
                    name = result.scanRecord?.deviceName,
                    rssi = result.rssi.toLong(),
                    state = ConnectionState.DISCONNECTED,
                )
                val advertisementData = AdvertisementData(
                    localName = result.scanRecord?.deviceName,
                    manufacturerData = result.scanRecord?.let { record ->
                        val sparseArray = record.manufacturerSpecificData
                        if (sparseArray != null && sparseArray.size() > 0) {
                            val manufacturerId = sparseArray.keyAt(0)
                            val data = sparseArray.valueAt(0)
                            // Combine manufacturer ID (2 bytes LE) + data
                            val combined = ByteArray(2 + data.size)
                            combined[0] = (manufacturerId and 0xFF).toByte()
                            combined[1] = ((manufacturerId shr 8) and 0xFF).toByte()
                            data.copyInto(combined, 2)
                            combined
                        } else {
                            null
                        }
                    },
                    serviceUuids = result.scanRecord?.serviceUuids
                        ?.map { it.uuid.toString() },
                    serviceData = result.scanRecord?.serviceData
                        ?.mapKeys { it.key.uuid.toString() },
                    txPowerLevel = result.scanRecord?.txPowerLevel?.toLong(),
                    isConnectable = result.isConnectable,
                )

                val scanResult = ScanResult(
                    peripheral = peripheral,
                    advertisementData = advertisementData,
                )
                flutterApi?.onScanResult(scanResult) {}
            }

            override fun onScanFailed(errorCode: Int) {
                // Log scan failure — no way to propagate after scan() has returned
            }
        }
        scanCallback = scanCb

        val filters = forServices?.map { uuid ->
            ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(uuid)))
                .build()
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        scanner.startScan(filters, settings, scanCb)
        callback(Result.success(Unit))
    }

    override fun cancelScan(session: ClientSession?, callback: (Result<Unit>) -> Unit) {
        val scanner = bluetoothAdapter?.bluetoothLeScanner
        scanCallback?.let { cb ->
            scanner?.stopScan(cb)
            scanCallback = null
        }
        callback(Result.success(Unit))
    }

    override fun peripherals(
        session: ClientSession?,
        peripheralIdentifiers: List<String>,
        callback: (Result<List<Peripheral>>) -> Unit,
    ) {
        val result = peripheralIdentifiers.mapNotNull { address ->
            discoveredPeripherals[address]?.let { device ->
                Peripheral(
                    session = PeripheralSession(
                        peripheralIdentifier = address,
                        clientIdentifier = session?.clientIdentifier,
                    ),
                    name = device.name,
                    rssi = null,
                    state = ConnectionState.DISCONNECTED,
                )
            }
        }
        callback(Result.success(result))
    }

    override fun connectedPeripherals(
        session: ClientSession?,
        serviceUuids: List<String>,
        callback: (Result<List<Peripheral>>) -> Unit,
    ) {
        val bluetoothManager =
            applicationContext?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        if (bluetoothManager == null) {
            callback(Result.success(emptyList()))
            return
        }
        val connectedDevices = bluetoothManager.getConnectedDevices(android.bluetooth.BluetoothProfile.GATT)
        val result = connectedDevices.map { device ->
            Peripheral(
                session = PeripheralSession(
                    peripheralIdentifier = device.address,
                    clientIdentifier = session?.clientIdentifier,
                ),
                name = device.name,
                rssi = null,
                state = ConnectionState.CONNECTED,
            )
        }
        callback(Result.success(result))
    }

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
