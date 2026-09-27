#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif
import CoreBluetooth
import Foundation

extension FlutterError: Error {}

private let cbErrorPeerRemovedPairingInformation = 14
private let cbErrorEncryptionTimedOut = 15

func butaneFlutterError(
  nativeError: Error?,
  fallback: ButaneErrorCode,
  message: String
) -> FlutterError {
  if let flutterError = nativeError as? FlutterError {
    return flutterError
  }

  let errorCode = butaneErrorCode(nativeError: nativeError, fallback: fallback)
  var details: [String: String] = ["platform": "darwin"]

  if let nativeError = nativeError {
    let nsError = nativeError as NSError
    details["nativeCode"] = "\(nsError.domain):\(nsError.code)"
  }

  return FlutterError(
    code: errorCode.wireName,
    message: message,
    details: details
  )
}

private func butaneErrorCode(
  nativeError: Error?,
  fallback: ButaneErrorCode
) -> ButaneErrorCode {
  guard let nativeError = nativeError else {
    return fallback
  }
  let nsError = nativeError as NSError

  if nsError.domain == CBErrorDomain {
    switch nsError.code {
    case CBError.Code.invalidParameters.rawValue, CBError.Code.invalidHandle.rawValue:
      return .invalidArgument
    case CBError.Code.notConnected.rawValue:
      return .notConnected
    case CBError.Code.connectionTimeout.rawValue, cbErrorEncryptionTimedOut:
      return .timeout
    case CBError.Code.peripheralDisconnected.rawValue,
         cbErrorPeerRemovedPairingInformation:
      return .disconnected
    case CBError.Code.connectionFailed.rawValue:
      return .connectFailed
    case CBError.Code.operationNotSupported.rawValue:
      return .unsupported
    default:
      return fallback
    }
  }

  if nsError.domain == CBATTErrorDomain {
    switch nsError.code {
    case CBATTError.Code.invalidHandle.rawValue, CBATTError.Code.invalidOffset.rawValue:
      return .invalidArgument
    case CBATTError.Code.requestNotSupported.rawValue:
      return .unsupported
    default:
      return fallback
    }
  }

  return fallback
}

private extension ButaneErrorCode {
  var wireName: String {
    switch self {
    case .unsupported:
      return "unsupported"
    case .unavailable:
      return "unavailable"
    case .poweredOff:
      return "poweredOff"
    case .notFound:
      return "notFound"
    case .notConnected:
      return "notConnected"
    case .connectFailed:
      return "connectFailed"
    case .disconnected:
      return "disconnected"
    case .timeout:
      return "timeout"
    case .invalidArgument:
      return "invalidArgument"
    case .operationFailed:
      return "operationFailed"
    }
  }
}
