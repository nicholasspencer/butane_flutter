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
import android.content.Context
import android.os.ParcelUuid
import androidx.annotation.NonNull
import java.util.UUID

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** ButaneAndroidPlugin */
class ButaneAndroidPlugin: FlutterPlugin, ButaneHostApi {
  private var flutterApi: ButaneFlutterApi? = null

  private var bluetoothAdapter: BluetoothAdapter? = null
  private var applicationContext: Context? = null

  private var scanCallback: ScanCallback? = null
  private val discoveredPeripherals = mutableMapOf<String, BluetoothDevice>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    val bluetoothManager = flutterPluginBinding.applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    bluetoothAdapter = bluetoothManager.adapter
    applicationContext = flutterPluginBinding.applicationContext
    ButaneHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
    flutterApi = ButaneFlutterApi(flutterPluginBinding.binaryMessenger)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { }

  /// Host API

  override fun state(session: Session?, callback: (kotlin.Result<ClientState>) -> Unit) {
    TODO("Not yet implemented")
  }

  override fun scan(
    session: Session?,
    forServices: List<String>?,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun cancelScan(session: Session?, callback: (kotlin.Result<Unit>) -> Unit) {
    TODO("Not yet implemented")
  }

  override fun peripherals(
    session: Session?,
    peripheralIdentifiers: List<String>,
    callback: (kotlin.Result<List<Peripheral>>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun connectedPeripherals(
    session: Session?,
    serviceUuids: List<String>,
    callback: (kotlin.Result<List<Peripheral>>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun connect(session: PeripheralSession, callback: (kotlin.Result<Unit>) -> Unit) {
    TODO("Not yet implemented")
  }

  override fun cancelConnection(
    session: PeripheralSession,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun connectionState(
    session: PeripheralSession,
    callback: (kotlin.Result<ConnectionState>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun discoverServices(
    session: PeripheralSession,
    serviceUuids: List<String>?,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun services(
    session: PeripheralSession,
    callback: (kotlin.Result<List<Service>>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun discoverCharacteristics(
    session: PeripheralSession,
    serviceUuid: String,
    characteristicUuids: List<String>?,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun characteristics(
    session: PeripheralSession,
    serviceUuid: String,
    callback: (kotlin.Result<List<Characteristic>>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun readCharacteristic(
    session: PeripheralSession,
    serviceUuid: String,
    characteristicUuid: String,
    callback: (kotlin.Result<ByteArray>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun writeCharacteristic(
    session: PeripheralSession,
    serviceUuid: String,
    characteristicUuid: String,
    value: ByteArray,
    withoutResponse: Boolean,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun observeCharacteristic(
    observe: Boolean,
    session: PeripheralSession,
    serviceUuid: String,
    characteristicUuid: String,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun readDescriptor(
    session: PeripheralSession,
    serviceUuid: String,
    characteristicUuid: String,
    descriptorUuid: String,
    callback: (kotlin.Result<ByteArray>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun writeDescriptor(
    session: PeripheralSession,
    serviceUuid: String,
    characteristicUuid: String,
    descriptorUuid: String,
    value: ByteArray,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    TODO("Not yet implemented")
  }

  override fun readRssi(session: PeripheralSession, callback: (kotlin.Result<Long>) -> Unit) {
    TODO("Not yet implemented")
  }

  override fun requestMtu(
    session: PeripheralSession,
    mtu: Long,
    callback: (kotlin.Result<Long>) -> Unit
  ) {
    TODO("Not yet implemented")
  }
}
