import XCTest
@testable import SwiftNetwork

final class RequestBuilderTests: XCTestCase {

    func testBasicBuild() {
        let endpoint = RequestBuilder()
            .path("/users")
            .method(.get)
            .build()

        XCTAssertEqual(endpoint.path, "/users")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertTrue(endpoint.headers.isEmpty)
        XCTAssertNil(endpoint.body)
        XCTAssertTrue(endpoint.queryItems.isEmpty)
    }

    func testHeadersAndQuery() {
        let endpoint = RequestBuilder()
            .path("/search")
            .method(.get)
            .header("Authorization", "Bearer token123")
            .header("Accept", "application/json")
            .query("q", "swift")
            .query("page", "1")
            .build()

        XCTAssertEqual(endpoint.headers["Authorization"], "Bearer token123")
        XCTAssertEqual(endpoint.headers["Accept"], "application/json")
        XCTAssertEqual(endpoint.queryItems.count, 2)
        XCTAssertEqual(endpoint.queryItems[0].name, "q")
        XCTAssertEqual(endpoint.queryItems[0].value, "swift")
    }

    func testBodyData() {
        let data = Data("test body".utf8)
        let endpoint = RequestBuilder()
            .path("/upload")
            .method(.post)
            .body(data)
            .build()

        XCTAssertEqual(endpoint.method, .post)
        XCTAssertEqual(endpoint.body, data)
    }

    func testEncodableBody() throws {
        struct Payload: Encodable {
            let name: String
            let value: Int
        }

        let endpoint = try RequestBuilder()
            .path("/items")
            .method(.post)
            .body(Payload(name: "test", value: 42))
            .build()

        XCTAssertNotNil(endpoint.body)
        XCTAssertEqual(endpoint.headers["Content-Type"], "application/json")
    }

    func testTimeout() {
        let endpoint = RequestBuilder()
            .path("/slow")
            .timeout(60)
            .build()

        XCTAssertEqual(endpoint.timeoutInterval, 60)
    }

    func testCachePolicy() {
        let endpoint = RequestBuilder()
            .path("/cached")
            .cachePolicy(.returnCacheDataElseLoad)
            .build()

        XCTAssertEqual(endpoint.cachePolicy, .returnCacheDataElseLoad)
    }

    func testImmutability() {
        let base = RequestBuilder().path("/base")
        let withGet = base.method(.get)
        let withPost = base.method(.post)

        XCTAssertEqual(withGet.build().method, .get)
        XCTAssertEqual(withPost.build().method, .post)
        XCTAssertEqual(withGet.build().path, "/base")
    }

    func testBulkHeaders() {
        let endpoint = RequestBuilder()
            .path("/api")
            .headers([
                "X-App-Version": "1.0",
                "X-Platform": "iOS"
            ])
            .build()

        XCTAssertEqual(endpoint.headers["X-App-Version"], "1.0")
        XCTAssertEqual(endpoint.headers["X-Platform"], "iOS")
    }

    func testQueryItems() {
        let endpoint = RequestBuilder()
            .path("/filter")
            .queryItems(["status": "active", "role": "admin"])
            .build()

        XCTAssertEqual(endpoint.queryItems.count, 2)
        let names = Set(endpoint.queryItems.map(\.name))
        XCTAssertTrue(names.contains("status"))
        XCTAssertTrue(names.contains("role"))
    }
}
