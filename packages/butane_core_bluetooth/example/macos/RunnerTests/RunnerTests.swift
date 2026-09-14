import FlutterMacOS
import Cocoa
import CoreBluetooth
import XCTest

@testable import butane_core_bluetooth

class RunnerTests: XCTestCase {
  private var flutterEngine: FlutterEngine!
  private var flutterApi: ButaneFlutterApi!

  override func setUp() {
    super.setUp()
    flutterEngine = FlutterEngine(name: "RunnerTests", project: nil)
    flutterApi = ButaneFlutterApi(binaryMessenger: flutterEngine.binaryMessenger)
  }

  override func tearDown() {
    flutterEngine.shutDownEngine()
    flutterApi = nil
    flutterEngine = nil
    super.tearDown()
  }

  func testCentralManagerFactoryReceivesRestorationOptions() {
    let queue = DispatchQueue(label: "central.manager.factory.test")
    let restorationIdentifier = "central.restore.test"
    var callCount = 0
    var capturedDelegate: CBCentralManagerDelegate?
    var capturedQueue: dispatch_queue_t?
    var capturedOptions: [String: Any]?

    let subject = CentralManager(
      identifier: nil,
      restorationIdentifier: restorationIdentifier,
      flutterApi: flutterApi,
      queue: queue,
      centralManagerFactory: { delegate, queue, options in
        callCount += 1
        capturedDelegate = delegate
        capturedQueue = queue
        capturedOptions = options
        return CBCentralManager(delegate: nil, queue: nil)
      }
    )

    _ = subject.manager

    XCTAssertEqual(callCount, 1)
    XCTAssertTrue(capturedDelegate === subject)
    XCTAssertTrue(capturedQueue === queue)
    XCTAssertEqual(
      capturedOptions?[CBCentralManagerOptionRestoreIdentifierKey] as? String,
      restorationIdentifier
    )
    XCTAssertNil(capturedOptions?[CBCentralManagerRestoredStateScanOptionsKey])
  }

  func testDefaultCentralManagerFactoryConstructsManager() {
    let subject = CentralManager(
      identifier: nil,
      restorationIdentifier: nil,
      flutterApi: flutterApi,
      queue: nil
    )

    XCTAssertTrue(type(of: subject.manager) == CBCentralManager.self)
  }
}
