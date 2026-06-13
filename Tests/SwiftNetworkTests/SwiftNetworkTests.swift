import XCTest
@testable import SwiftNetwork

final class SwiftNetworkTests: XCTestCase {
    func testNetworkClientExecution() async throws {
        let client = NetworkClient.shared
        XCTAssertNotNil(client)
    }
}
