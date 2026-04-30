package com.nicospencer.butane_android

import ConnectionState
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import no.nordicsemi.android.ble.BleManager
import no.nordicsemi.android.ble.ktx.suspend
import no.nordicsemi.android.ble.observer.ConnectionObserver
import java.util.UUID

class PeripheralConnection(
    context: Context,
    private val onConnectionStateChanged: (BluetoothDevice, ConnectionState) -> Unit,
) : BleManager(context) {

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState

    /** The underlying BluetoothGatt, available after connection. */
    private var gatt: BluetoothGatt? = null

    init {
        setConnectionObserver(object : ConnectionObserver {
            override fun onDeviceConnecting(device: BluetoothDevice) {}
            override fun onDeviceConnected(device: BluetoothDevice) {}
            override fun onDeviceFailedToConnect(device: BluetoothDevice, reason: Int) {}
            override fun onDeviceReady(device: BluetoothDevice) {}
            override fun onDeviceDisconnecting(device: BluetoothDevice) {}
            override fun onDeviceDisconnected(device: BluetoothDevice, reason: Int) {
                _connectionState.value = ConnectionState.DISCONNECTED
                onConnectionStateChanged(device, ConnectionState.DISCONNECTED)
                gatt = null
            }
        })
    }

    override fun initialize() {
        // Called after services are discovered. No-op for now.
    }

    override fun isRequiredServiceSupported(gatt: BluetoothGatt): Boolean {
        this.gatt = gatt
        // Accept any peripheral — service validation is done at the Dart layer.
        return true
    }

    override fun onServicesInvalidated() {
        gatt = null
    }

    override fun onDeviceReady() {
        bluetoothDevice?.let { device ->
            _connectionState.value = ConnectionState.CONNECTED
            onConnectionStateChanged(device, ConnectionState.CONNECTED)
        }
    }

    /**
     * Connect to the device with GATT error 133 retry.
     *
     * Status 133 is an Android-specific catch-all GATT error that occurs
     * sporadically on many devices. Retrying 3 times with a 100ms delay
     * is the standard workaround.
     */
    suspend fun connectDevice(device: BluetoothDevice) {
        _connectionState.value = ConnectionState.CONNECTING
        onConnectionStateChanged(device, ConnectionState.CONNECTING)
        connect(device)
            .retry(3, 100)
            .useAutoConnect(false)
            .suspend()
    }

    suspend fun disconnectDevice() {
        bluetoothDevice?.let { device ->
            _connectionState.value = ConnectionState.DISCONNECTING
            onConnectionStateChanged(device, ConnectionState.DISCONNECTING)
        }
        disconnect().suspend()
    }

    /** Returns discovered services from the GATT cache. */
    fun getDiscoveredServices(): List<BluetoothGattService> {
        return gatt?.services ?: emptyList()
    }

    fun findCharacteristic(serviceUuid: String, characteristicUuid: String): BluetoothGattCharacteristic? {
        return gatt?.getService(UUID.fromString(serviceUuid))
            ?.getCharacteristic(UUID.fromString(characteristicUuid))
    }

    fun findDescriptor(
        serviceUuid: String,
        characteristicUuid: String,
        descriptorUuid: String,
    ): BluetoothGattDescriptor? {
        return findCharacteristic(serviceUuid, characteristicUuid)
            ?.getDescriptor(UUID.fromString(descriptorUuid))
    }
}
