package com.nicospencer.butane_android

import ButaneFlutterApi
import ButaneHostApi
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** ButaneAndroidPlugin */
class ButaneAndroidPlugin: FlutterPlugin, ButaneHostApi, ActivityAware {
  private var flutterApi: ButaneFlutterApi? = null
  private var scope: CoroutineScope? = null

  private var applicationContext: Context? = null
  private var bluetoothAdapter: BluetoothAdapter? = null
  private val stateReceivers = mutableMapOf<String?, BroadcastReceiver>()
  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    ButaneHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
    flutterApi = ButaneFlutterApi(flutterPluginBinding.binaryMessenger)
    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    applicationContext = flutterPluginBinding.applicationContext
    val bluetoothManager =
        flutterPluginBinding.applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
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

  /// Host API

  override fun state(session: Session?, callback: (kotlin.Result<ClientState>) -> Unit) {
    val adapter = bluetoothAdapter
    if (adapter == null) {
      callback(kotlin.Result.success(ClientState.UNSUPPORTED))
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

    callback(kotlin.Result.success(mapAdapterState(adapter.state)))
  }

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
