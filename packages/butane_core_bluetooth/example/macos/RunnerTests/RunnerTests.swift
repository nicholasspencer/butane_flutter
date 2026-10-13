import FlutterMacOS
import Cocoa
import CoreBluetooth
import XCTest

@testable import butane_core_bluetooth

private struct DescriptorDiscoveryTestError: Error {}

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

  func testDescriptorDiscoveryWaitsForEveryCallbackAndCompletesAfterError() {
    let firstCharacteristic = CBMutableCharacteristic(
      type: CBUUID(string: "0001"),
      properties: [],
      value: nil,
      permissions: []
    )
    let secondCharacteristic = CBMutableCharacteristic(
      type: CBUUID(string: "0002"),
      properties: [],
      value: nil,
      permissions: []
    )
    let service = CBMutableService(type: CBUUID(string: "0000"), primary: true)
    service.characteristics = [firstCharacteristic, secondCharacteristic]

    let store = DescriptorDiscoveryContinuationStore()
    let starts = expectation(description: "Descriptor discovery starts for every characteristic")
    starts.expectedFulfillmentCount = 2
    let completion = DispatchSemaphore(value: 0)

    Task {
      await withTaskGroup(of: Void.self) { group in
        for characteristic in service.characteristics ?? [] {
          group.addTask {
            await store.wait(for: characteristic) {
              starts.fulfill()
            }
          }
        }
      }

      completion.signal()
    }

    wait(for: [starts], timeout: 1)
    XCTAssertEqual(completion.wait(timeout: .now() + 0.1), .timedOut)

    store.didDiscoverDescriptorsFor(characteristic: firstCharacteristic, error: nil)
    XCTAssertEqual(completion.wait(timeout: .now() + 0.1), .timedOut)

    store.didDiscoverDescriptorsFor(
      characteristic: secondCharacteristic,
      error: DescriptorDiscoveryTestError()
    )
    XCTAssertEqual(completion.wait(timeout: .now() + 1), .success)
  }
}
