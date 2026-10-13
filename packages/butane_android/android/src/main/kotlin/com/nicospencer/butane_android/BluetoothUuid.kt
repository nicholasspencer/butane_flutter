package com.nicospencer.butane_android

import java.util.UUID

private const val BLUETOOTH_BASE_UUID_SUFFIX = "-0000-1000-8000-00805f9b34fb"

/**
 * Parses a Bluetooth UUID string. Accepts the 128-bit form and the 16- and
 * 32-bit short forms ("2901", "0000180f"), which expand onto the Bluetooth
 * base UUID as CoreBluetooth and BlueZ already accept them.
 */
fun bluetoothUuid(value: String): UUID {
    val hex = value.trim()
    return when (hex.length) {
        4 -> UUID.fromString("0000$hex$BLUETOOTH_BASE_UUID_SUFFIX")
        8 -> UUID.fromString("$hex$BLUETOOTH_BASE_UUID_SUFFIX")
        else -> UUID.fromString(hex)
    }
}
