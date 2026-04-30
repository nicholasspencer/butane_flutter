package com.nicospencer.butane_android

import AttRequest
import AttResult
import MutableService
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import java.util.UUID

class GattServerManager(
    private val context: Context,
    private val bluetoothManager: BluetoothManager,
    private val onReadRequest: (AttRequest) -> Unit,
    private val onWriteRequests: (List<AttRequest>) -> Unit,
    private val onServiceAdded: (String, String?) -> Unit,
    private val onCentralSubscribed: (String?, String, String, String) -> Unit,
    private val onCentralUnsubscribed: (String?, String, String, String) -> Unit,
    private val onReadyToUpdateSubscribers: (String?) -> Unit,
) {
    private var gattServer: BluetoothGattServer? = null
    private val services = mutableMapOf<String, BluetoothGattService>()
    private val pendingRequests = mutableMapOf<Long, PendingRequest>()
    private var nextRequestId: Long = 1

    data class PendingRequest(
        val device: BluetoothDevice,
        val requestId: Int,
        val offset: Int,
    )

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            val error = if (status != BluetoothGatt.GATT_SUCCESS) "Failed with status $status" else null
            onServiceAdded(service.uuid.toString(), error)
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            val id = nextRequestId++
            pendingRequests[id] = PendingRequest(device, requestId, offset)

            val serviceUuid = characteristic.service?.uuid?.toString() ?: ""
            val request = AttRequest(
                requestId = id,
                centralIdentifier = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                serviceUuid = serviceUuid,
                offset = offset.toLong(),
                value = null,
            )
            onReadRequest(request)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            val id = nextRequestId++
            if (responseNeeded) {
                pendingRequests[id] = PendingRequest(device, requestId, offset)
            }

            val serviceUuid = characteristic.service?.uuid?.toString() ?: ""
            val request = AttRequest(
                requestId = id,
                centralIdentifier = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                serviceUuid = serviceUuid,
                offset = offset.toLong(),
                value = value,
            )
            onWriteRequests(listOf(request))

            if (!responseNeeded) {
                // No response needed — auto-respond success
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            // CCCD (0x2902) writes indicate subscription changes
            if (descriptor.uuid == UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")) {
                val characteristic = descriptor.characteristic
                val serviceUuid = characteristic?.service?.uuid?.toString() ?: ""
                val charUuid = characteristic?.uuid?.toString() ?: ""

                if (value != null && (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ||
                            value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE))) {
                    onCentralSubscribed(null, device.address, serviceUuid, charUuid)
                } else {
                    onCentralUnsubscribed(null, device.address, serviceUuid, charUuid)
                }
            }

            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            onReadyToUpdateSubscribers(null)
        }
    }

    fun open() {
        gattServer = bluetoothManager.openGattServer(context, serverCallback)
    }

    fun close() {
        gattServer?.close()
        gattServer = null
        services.clear()
        pendingRequests.clear()
    }

    @Suppress("DEPRECATION")
    fun addService(service: MutableService) {
        val gattService = BluetoothGattService(
            UUID.fromString(service.uuid),
            if (service.isPrimary) BluetoothGattService.SERVICE_TYPE_PRIMARY
            else BluetoothGattService.SERVICE_TYPE_SECONDARY,
        )
        for (mutableChar in service.characteristics) {
            if (mutableChar == null) continue
            val properties = mutableChar.properties?.let { props ->
                var p = 0
                if (props.broadcast) p = p or BluetoothGattCharacteristic.PROPERTY_BROADCAST
                if (props.read) p = p or BluetoothGattCharacteristic.PROPERTY_READ
                if (props.writeWithoutResponse) p = p or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
                if (props.write) p = p or BluetoothGattCharacteristic.PROPERTY_WRITE
                if (props.notify) p = p or BluetoothGattCharacteristic.PROPERTY_NOTIFY
                if (props.indicate) p = p or BluetoothGattCharacteristic.PROPERTY_INDICATE
                if (props.authenticatedSignedWrites) p = p or BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE
                if (props.extendedProperties) p = p or BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS
                p
            } ?: 0
            val permissions = mutableChar.permissions?.let { perms ->
                var p = 0
                if (perms.readable) p = p or BluetoothGattCharacteristic.PERMISSION_READ
                if (perms.writeable) p = p or BluetoothGattCharacteristic.PERMISSION_WRITE
                if (perms.readEncryptionRequired) p = p or BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
                if (perms.writeEncryptionRequired) p = p or BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
                p
            } ?: 0
            val gattChar = BluetoothGattCharacteristic(
                UUID.fromString(mutableChar.uuid),
                properties,
                permissions,
            )
            mutableChar.value?.let { gattChar.value = it }

            // Add CCCD descriptor if notify or indicate property is set
            if ((properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0 ||
                (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) {
                val cccd = BluetoothGattDescriptor(
                    UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
                    BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
                )
                gattChar.addDescriptor(cccd)
            }

            mutableChar.descriptors?.forEach { mutableDesc ->
                if (mutableDesc == null) return@forEach
                val desc = BluetoothGattDescriptor(
                    UUID.fromString(mutableDesc.uuid),
                    BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
                )
                mutableDesc.value?.let { desc.value = it }
                gattChar.addDescriptor(desc)
            }
            gattService.addCharacteristic(gattChar)
        }
        services[service.uuid] = gattService
        gattServer?.addService(gattService)
    }

    fun removeService(serviceUuid: String): Boolean {
        val service = services.remove(serviceUuid) ?: return false
        gattServer?.removeService(service)
        return true
    }

    fun removeAllServices() {
        gattServer?.clearServices()
        services.clear()
    }

    fun respondToRequest(requestId: Long, result: AttResult, value: ByteArray?) {
        val pending = pendingRequests.remove(requestId) ?: return
        val status = when (result) {
            AttResult.SUCCESS -> BluetoothGatt.GATT_SUCCESS
            AttResult.INVALID_HANDLE -> BluetoothGatt.GATT_FAILURE  // BluetoothGatt has no GATT_INVALID_HANDLE constant
            AttResult.READ_NOT_PERMITTED -> BluetoothGatt.GATT_READ_NOT_PERMITTED
            AttResult.WRITE_NOT_PERMITTED -> BluetoothGatt.GATT_WRITE_NOT_PERMITTED
            AttResult.INVALID_OFFSET -> BluetoothGatt.GATT_INVALID_OFFSET
            AttResult.ATTRIBUTE_NOT_FOUND -> BluetoothGatt.GATT_FAILURE
            AttResult.UNLIKELY_ERROR -> BluetoothGatt.GATT_FAILURE
        }
        gattServer?.sendResponse(pending.device, pending.requestId, status, pending.offset, value)
    }

    @Suppress("DEPRECATION")
    fun updateValue(
        serviceUuid: String,
        characteristicUuid: String,
        value: ByteArray,
    ): Boolean {
        val service = services[serviceUuid] ?: return false
        val characteristic = service.getCharacteristic(UUID.fromString(characteristicUuid)) ?: return false
        characteristic.value = value

        // Send notification to all connected devices
        val connectedDevices = bluetoothManager.getConnectedDevices(BluetoothProfile.GATT_SERVER)
        var allSent = true
        val confirm = (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
        for (device in connectedDevices) {
            val sent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gattServer?.notifyCharacteristicChanged(device, characteristic, confirm, value) ==
                    BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                gattServer?.notifyCharacteristicChanged(device, characteristic, confirm) ?: false
            }
            if (!sent) allSent = false
        }
        return allSent
    }
}
