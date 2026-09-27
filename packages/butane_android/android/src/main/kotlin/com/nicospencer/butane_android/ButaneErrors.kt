package com.nicospencer.butane_android

import ButaneErrorCode
import FlutterError
import android.bluetooth.BluetoothGatt
import no.nordicsemi.android.ble.exception.DeviceDisconnectedException
import no.nordicsemi.android.ble.exception.RequestFailedException

private fun ButaneErrorCode.wireName(): String = when (this) {
    ButaneErrorCode.UNSUPPORTED -> "unsupported"
    ButaneErrorCode.UNAVAILABLE -> "unavailable"
    ButaneErrorCode.POWERED_OFF -> "poweredOff"
    ButaneErrorCode.NOT_FOUND -> "notFound"
    ButaneErrorCode.NOT_CONNECTED -> "notConnected"
    ButaneErrorCode.CONNECT_FAILED -> "connectFailed"
    ButaneErrorCode.DISCONNECTED -> "disconnected"
    ButaneErrorCode.TIMEOUT -> "timeout"
    ButaneErrorCode.INVALID_ARGUMENT -> "invalidArgument"
    ButaneErrorCode.OPERATION_FAILED -> "operationFailed"
}

fun butaneFlutterError(
    fallback: ButaneErrorCode,
    message: String,
    error: Throwable? = null,
    nativeCode: String? = null,
): FlutterError {
    val code = when (error) {
        is DeviceDisconnectedException -> ButaneErrorCode.DISCONNECTED
        is RequestFailedException -> when (error.status) {
            BluetoothGatt.GATT_SUCCESS -> ButaneErrorCode.OPERATION_FAILED
            BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED -> ButaneErrorCode.UNSUPPORTED
            BluetoothGatt.GATT_INVALID_OFFSET,
            BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH,
            -> ButaneErrorCode.INVALID_ARGUMENT
            else -> fallback
        }
        else -> fallback
    }
    val resolvedNativeCode = nativeCode ?: when (error) {
        is RequestFailedException -> error.status.toString()
        null -> null
        else -> error.javaClass.name
    }
    val details = mutableMapOf<String, Any>("platform" to "android")
    resolvedNativeCode?.let { details["nativeCode"] = it }
    return FlutterError(
        code.wireName(),
        error?.message ?: message,
        details,
    )
}
