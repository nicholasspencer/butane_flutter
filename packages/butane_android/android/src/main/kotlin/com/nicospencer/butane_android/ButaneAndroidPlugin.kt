package com.nicospencer.butane_android

import AdvertisementData
import AttResult
import ButaneFlutterApi
import ButaneHostApi
import Characteristic
import ClientSession
import ClientState
import ConnectionState
import FlutterError
import MutableService
import Peripheral
import PeripheralManagerSession
import PeripheralSession
import ScanResult
import Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
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
import kotlinx.coroutines.launch
import java.util.UUID

class ButaneAndroidPlugin : FlutterPlugin, ButaneHostApi, ActivityAware {
    private var flutterApi: ButaneFlutterApi? = null
    private var scope: CoroutineScope? = null

    private var applicationContext: Context? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private val stateReceivers = mutableMapOf<String?, BroadcastReceiver>()

    private var scanCallback: ScanCallback? = null
    private val discoveredPeripherals = mutableMapOf<String, BluetoothDevice>()

    private val connections = mutableMapOf<String, PeripheralConnection>()

    private var advertiseCallback: AdvertiseCallback? = null

    private var gattServer: GattServerManager? = null

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
        // Close all connections
        connections.values.forEach { it.close() }
        connections.clear()
        // Stop advertising
        advertiseCallback?.let { cb ->
            bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
            advertiseCallback = null
        }
        // Stop any active scan
        scanCallback?.let { cb ->
            bluetoothAdapter?.bluetoothLeScanner?.stopScan(cb)
            scanCallback = null
        }
        discoveredPeripherals.clear()
        // Close GATT server
        gattServer?.close()
        gattServer = null
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

    private fun getGattServer(): GattServerManager? {
        if (gattServer != null) return gattServer
        val ctx = applicationContext ?: return null
        val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return null
        val server = GattServerManager(
            context = ctx,
            bluetoothManager = mgr,
            onReadRequest = { request ->
                flutterApi?.onReadRequest(request) {}
            },
            onWriteRequests = { requests ->
                flutterApi?.onWriteRequests(requests) {}
            },
            onServiceAdded = { uuid, error ->
                flutterApi?.onServiceAdded(uuid, error) {}
            },
            onCentralSubscribed = { clientId, centralId, serviceUuid, charUuid ->
                flutterApi?.onCentralSubscribed(clientId, centralId, serviceUuid, charUuid) {}
            },
            onCentralUnsubscribed = { clientId, centralId, serviceUuid, charUuid ->
                flutterApi?.onCentralUnsubscribed(clientId, centralId, serviceUuid, charUuid) {}
            },
            onReadyToUpdateSubscribers = { clientId ->
                flutterApi?.onReadyToUpdateSubscribers(clientId) {}
            },
        )
        server.open()
        gattServer = server
        return server
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

    private fun buildPeripheral(
        device: BluetoothDevice,
        session: PeripheralSession,
        state: ConnectionState,
    ): Peripheral {
        return Peripheral(
            session = session,
            name = device.name,
            rssi = null,
            state = state,
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

    override fun connect(session: PeripheralSession, callback: (Result<Unit>) -> Unit) {
        val context = applicationContext
        if (context == null) {
            callback(Result.failure(FlutterError("unavailable", "Context not available", null)))
            return
        }

        val address = session.peripheralIdentifier
        val device = discoveredPeripherals[address]
            ?: bluetoothAdapter?.getRemoteDevice(address)
        if (device == null) {
            callback(Result.failure(FlutterError("not-found", "Peripheral $address not found", null)))
            return
        }

        // Get or create connection
        val connection = connections.getOrPut(address) {
            PeripheralConnection(context) { changedDevice, newState ->
                val peripheral = buildPeripheral(changedDevice, session, newState)
                flutterApi?.onConnectionState(peripheral, newState) {}
            }
        }

        scope?.launch {
            try {
                connection.connectDevice(device)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(FlutterError("connect-failed", e.message, null)))
            }
        } ?: callback(Result.failure(FlutterError("unavailable", "Plugin not attached", null)))
    }

    override fun cancelConnection(
        session: PeripheralSession,
        callback: (Result<Unit>) -> Unit,
    ) {
        val address = session.peripheralIdentifier
        val connection = connections[address]
        if (connection == null) {
            callback(Result.success(Unit))
            return
        }

        scope?.launch {
            try {
                connection.disconnectDevice()
                connections.remove(address)
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(FlutterError("disconnect-failed", e.message, null)))
            }
        } ?: callback(Result.failure(FlutterError("unavailable", "Plugin not attached", null)))
    }

    override fun connectionState(
        session: PeripheralSession,
        callback: (Result<ConnectionState>) -> Unit,
    ) {
        val address = session.peripheralIdentifier
        val connection = connections[address]
        val state = connection?.connectionState?.value ?: ConnectionState.DISCONNECTED
        callback(Result.success(state))
    }

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
    ) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            callback(Result.success(ClientState.UNSUPPORTED))
            return
        }

        val clientId = session.clientIdentifier

        // Register state receiver for peripheral manager if not already registered.
        // Use a prefixed key to avoid collision with central state receivers.
        val receiverKey = "pm:$clientId"
        if (!stateReceivers.containsKey(receiverKey)) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                        val newState = intent.getIntExtra(
                            BluetoothAdapter.EXTRA_STATE,
                            BluetoothAdapter.ERROR,
                        )
                        val clientState = mapAdapterState(newState)
                        flutterApi?.onPeripheralManagerState(clientId, clientState) {}
                    }
                }
            }
            val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
            applicationContext?.registerReceiver(receiver, filter)
            stateReceivers[receiverKey] = receiver
        }

        callback(Result.success(mapAdapterState(adapter.state)))
    }

    override fun startAdvertising(
        session: PeripheralManagerSession,
        localName: String?,
        serviceUuids: List<String>?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (advertiser == null) {
            callback(Result.failure(FlutterError("unavailable", "BLE advertiser not available", null)))
            return
        }

        // Stop any existing advertising
        advertiseCallback?.let { advertiser.stopAdvertising(it) }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(localName != null)
        serviceUuids?.forEach { uuid ->
            dataBuilder.addServiceUuid(ParcelUuid(UUID.fromString(uuid)))
        }
        val data = dataBuilder.build()

        val cb = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                callback(Result.success(Unit))
            }

            override fun onStartFailure(errorCode: Int) {
                val message = when (errorCode) {
                    AdvertiseCallback.ADVERTISE_FAILED_ALREADY_STARTED -> "Already advertising"
                    AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE -> "Advertise data too large"
                    AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Advertising not supported"
                    AdvertiseCallback.ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                    AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                    else -> "Unknown error: $errorCode"
                }
                callback(Result.failure(FlutterError("advertise-failed", message, null)))
            }
        }
        advertiseCallback = cb

        // If localName is set, update the adapter name before advertising.
        if (localName != null) {
            bluetoothAdapter?.name = localName
        }

        advertiser.startAdvertising(settings, data, cb)
    }

    override fun stopAdvertising(
        session: PeripheralManagerSession,
        callback: (Result<Unit>) -> Unit,
    ) {
        val advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        advertiseCallback?.let { cb ->
            advertiser?.stopAdvertising(cb)
            advertiseCallback = null
        }
        callback(Result.success(Unit))
    }

    override fun addService(
        session: PeripheralManagerSession,
        service: MutableService,
        callback: (Result<Unit>) -> Unit,
    ) {
        val server = getGattServer()
        if (server == null) {
            callback(Result.failure(FlutterError("unavailable", "GATT server not available", null)))
            return
        }
        try {
            server.addService(service)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(FlutterError("add-service-failed", e.message, null)))
        }
    }

    override fun removeService(
        session: PeripheralManagerSession,
        serviceUuid: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        val server = getGattServer()
        if (server == null) {
            callback(Result.failure(FlutterError("unavailable", "GATT server not available", null)))
            return
        }
        if (!server.removeService(serviceUuid)) {
            callback(Result.failure(FlutterError("not-found", "Service $serviceUuid not found", null)))
            return
        }
        callback(Result.success(Unit))
    }

    override fun removeAllServices(
        session: PeripheralManagerSession,
        callback: (Result<Unit>) -> Unit,
    ) {
        gattServer?.removeAllServices()
        callback(Result.success(Unit))
    }

    override fun respondToRequest(
        session: PeripheralManagerSession,
        requestId: Long,
        result: AttResult,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val server = getGattServer()
        if (server == null) {
            callback(Result.failure(FlutterError("unavailable", "GATT server not available", null)))
            return
        }
        server.respondToRequest(requestId, result, value)
        callback(Result.success(Unit))
    }

    override fun updateValue(
        session: PeripheralManagerSession,
        serviceUuid: String,
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Boolean>) -> Unit,
    ) {
        val server = getGattServer()
        if (server == null) {
            callback(Result.failure(FlutterError("unavailable", "GATT server not available", null)))
            return
        }
        val sent = server.updateValue(serviceUuid, characteristicUuid, value)
        callback(Result.success(sent))
    }
}
