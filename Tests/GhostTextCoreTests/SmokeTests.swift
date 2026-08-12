import XCTest
@testable import GhostTextCore

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(GhostTextCore.version, "0.1.0") }
}
