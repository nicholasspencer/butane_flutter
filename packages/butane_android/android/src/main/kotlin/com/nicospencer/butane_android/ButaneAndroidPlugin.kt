package com.nicospencer.butane_android

import ButaneFlutterApi
import ButaneHostApi
import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** ButaneAndroidPlugin */
class ButaneAndroidPlugin: FlutterPlugin, ButaneHostApi {
  private var flutterApi: ButaneFlutterApi? = null

  private var managers: Map<UUID, BluetoothManager> = mutableMapOf()
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
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
