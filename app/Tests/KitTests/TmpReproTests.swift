import XCTest
#if canImport(VoyagerKit)
@testable import VoyagerKit
#endif
final class TmpReproTests: XCTestCase {
    func testRepro() throws {
        let m = CalculatorMachine(); try m.loadFirmware(Fixtures.multiE3E3!); try m.boot(restoring: nil)
        let e = CalculatorEngine(machine: m); e.start()
        e.send(.setInspector(true))
        func d() -> String { e.performAndWait { $0.displayText } ?? "?" }
        e.send(.switchModel(160, { _ in })); Thread.sleep(forTimeInterval: 8)
        print("A", d(), m.variant)
        e.send(.press(30)); e.send(.release(30)); Thread.sleep(forTimeInterval: 1)
        print("B", d())
        e.send(.press(32)); e.send(.press(25)); Thread.sleep(forTimeInterval: 0.6)
        print("C", d())
        e.send(.press(30)); Thread.sleep(forTimeInterval: 0.3); e.send(.release(30)); e.send(.releaseLater([25, 32], afterMs: 200))
        for _ in 0..<3 { Thread.sleep(forTimeInterval: 0.5); print("D", d(), m.keysDown) }
        e.stop()
    }
}
