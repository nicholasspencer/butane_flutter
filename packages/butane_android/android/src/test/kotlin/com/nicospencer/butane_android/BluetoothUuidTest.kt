package com.nicospencer.butane_android

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class BluetoothUuidTest {
    @Test
    fun expands16BitUuidOntoTheBaseUuid() {
        assertEquals(
            UUID.fromString("00002901-0000-1000-8000-00805f9b34fb"),
            bluetoothUuid("2901"),
        )
    }

    @Test
    fun expands32BitUuidOntoTheBaseUuid() {
        assertEquals(
            UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb"),
            bluetoothUuid("0000180f"),
        )
    }

    @Test
    fun parses128BitUuidUnchanged() {
        val uuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"

        assertEquals(UUID.fromString(uuid), bluetoothUuid(uuid))
    }

    @Test
    fun ignoresSurroundingWhitespace() {
        assertEquals(bluetoothUuid("2901"), bluetoothUuid(" 2901 "))
    }

    @Test
    fun rejectsMalformedUuid() {
        assertFailsWith<IllegalArgumentException> { bluetoothUuid("not-a-uuid") }
    }
}
