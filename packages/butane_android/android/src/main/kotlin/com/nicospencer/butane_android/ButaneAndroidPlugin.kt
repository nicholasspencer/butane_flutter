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
    session: ClientSession?,
    forServices: List<String>?,
    callback: (kotlin.Result<Unit>) -> Unit
  ) {
    val scanner = bluetoothAdapter?.bluetoothLeScanner
    if (scanner == null) {
      callback(Result.failure(FlutterError("unavailable", "BLE scanner not available", null)))
      return
    }

    // Stop any existing scan first
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
          isConnectable = if (result.isConnectable) true else null,
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

    if (filters.isNullOrEmpty()) {
      scanner.startScan(settings, scanCb)
    } else {
      scanner.startScan(filters, settings, scanCb)
    }
    callback(Result.success(Unit))
  }

  override fun cancelScan(session: ClientSession?, callback: (kotlin.Result<Unit>) -> Unit) {
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
    callback: (kotlin.Result<List<Peripheral>>) -> Unit
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
    callback: (kotlin.Result<List<Peripheral>>) -> Unit
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
