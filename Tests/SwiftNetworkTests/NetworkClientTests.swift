import XCTest
@testable import SwiftNetwork

final class NetworkClientTests: XCTestCase {

    // MARK: - Endpoint Tests

    func testEndpointURLConstruction() {
        let endpoint = Endpoint(
            path: "/users",
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "20")
            ]
        )

        let url = endpoint.url(relativeTo: "https://api.example.com")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "api.example.com")
        XCTAssertEqual(url?.path, "/users")
        XCTAssertTrue(url?.query?.contains("page=1") ?? false)
        XCTAssertTrue(url?.query?.contains("limit=20") ?? false)
    }

    func testEndpointURLRequestConstruction() throws {
        let endpoint = Endpoint(
            path: "/users",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: Data("{\"name\":\"Test\"}".utf8),
            timeoutInterval: 15
        )

        let request = try endpoint.urlRequest(baseURL: "https://api.example.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.httpBody)
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testEndpointConvenienceGet() {
        let endpoint = Endpoint.get("/items", query: ["sort": "name"])
        XCTAssertEqual(endpoint.path, "/items")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.queryItems.count, 1)
        XCTAssertEqual(endpoint.queryItems.first?.name, "sort")
    }

    // MARK: - NetworkError Tests

    func testNetworkErrorEquality() {
        XCTAssertEqual(NetworkError.invalidURL, NetworkError.invalidURL)
        XCTAssertEqual(NetworkError.timeout, NetworkError.timeout)
        XCTAssertEqual(NetworkError.noConnection, NetworkError.noConnection)
        XCTAssertEqual(NetworkError.cancelled, NetworkError.cancelled)
        XCTAssertEqual(
            NetworkError.httpError(statusCode: 404, data: nil),
            NetworkError.httpError(statusCode: 404, data: nil)
        )
        XCTAssertNotEqual(
            NetworkError.httpError(statusCode: 404, data: nil),
            NetworkError.httpError(statusCode: 500, data: nil)
        )
    }

    func testNetworkErrorDescription() {
        XCTAssertNotNil(NetworkError.invalidURL.errorDescription)
        XCTAssertNotNil(NetworkError.timeout.errorDescription)
        XCTAssertNotNil(NetworkError.noConnection.errorDescription)
        XCTAssertTrue(NetworkError.httpError(statusCode: 404, data: nil).errorDescription?.contains("404") ?? false)
    }

    // MARK: - NetworkResponse Tests

    func testNetworkResponseSuccess() {
        let response = NetworkResponse(data: Data(), statusCode: 200)
        XCTAssertTrue(response.isSuccess)
        XCTAssertFalse(response.isClientError)
        XCTAssertFalse(response.isServerError)
    }

    func testNetworkResponseClientError() {
        let response = NetworkResponse(data: Data(), statusCode: 404)
        XCTAssertFalse(response.isSuccess)
        XCTAssertTrue(response.isClientError)
        XCTAssertFalse(response.isServerError)
    }

    func testNetworkResponseServerError() {
        let response = NetworkResponse(data: Data(), statusCode: 500)
        XCTAssertFalse(response.isSuccess)
        XCTAssertFalse(response.isClientError)
        XCTAssertTrue(response.isServerError)
    }

    func testNetworkResponseTextDecoding() {
        let data = Data("Hello, World!".utf8)
        let response = NetworkResponse(data: data, statusCode: 200)
        XCTAssertEqual(response.text, "Hello, World!")
    }

    func testNetworkResponseDecode() throws {
        struct User: Decodable {
            let id: Int
            let name: String
        }

        let json = Data("{\"id\":1,\"name\":\"Test\"}".utf8)
        let response = NetworkResponse(data: json, statusCode: 200)
        let user = try response.decode(User.self)
        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.name, "Test")
    }

    func testNetworkResponseHeaderLookup() {
        let response = NetworkResponse(
            data: Data(),
            statusCode: 200,
            headers: ["Content-Type": "application/json"]
        )
        XCTAssertEqual(response.header("content-type"), "application/json")
        XCTAssertNil(response.header("X-Missing"))
    }

    // MARK: - MockNetworkClient Tests

    func testMockClientReturnsStub() async throws {
        struct Item: Codable {
            let id: Int
            let title: String
        }

        let mock = MockNetworkClient()
        mock.stub(path: "/items", response: [Item(id: 1, title: "Test Item")])

        let items: [Item] = try await mock.request(Endpoint(path: "/items", method: .get))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Test Item")
    }

    func testMockClientRecordsRequests() async throws {
        struct Empty: Codable {}

        let mock = MockNetworkClient()
        mock.stub(path: "/ping", response: Empty())

        let _: Empty = try await mock.request(Endpoint(path: "/ping", method: .get))
        let _: Empty = try await mock.request(Endpoint(path: "/ping", method: .get))

        XCTAssertTrue(mock.wasRequested(path: "/ping"))
        XCTAssertEqual(mock.requestCount(path: "/ping"), 2)
    }

    func testMockClientThrowsForUnstubbed() async {
        let mock = MockNetworkClient()

        do {
            let _: String = try await mock.request(Endpoint(path: "/missing", method: .get))
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }

    // MARK: - MultipartFormData Tests

    func testMultipartAppendValue() {
        var multipart = MultipartFormData(boundary: "test-boundary")
        multipart.append(value: "hello", name: "greeting")
        XCTAssertEqual(multipart.partCount, 1)
        XCTAssertFalse(multipart.isEmpty)

        let encoded = multipart.encode()
        let string = String(data: encoded, encoding: .utf8)!
        XCTAssertTrue(string.contains("test-boundary"))
        XCTAssertTrue(string.contains("greeting"))
        XCTAssertTrue(string.contains("hello"))
    }

    func testMultipartContentType() {
        let multipart = MultipartFormData(boundary: "my-boundary")
        XCTAssertEqual(multipart.contentType, "multipart/form-data; boundary=my-boundary")
    }
}
