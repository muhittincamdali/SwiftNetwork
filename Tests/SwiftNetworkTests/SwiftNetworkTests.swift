import XCTest
@testable import SwiftNetwork

final class SwiftNetworkTests: XCTestCase {

    // MARK: - NetworkClient Tests

    func testNetworkClientInitialization() {
        let client = NetworkClient(baseURL: "https://api.example.com")
        XCTAssertEqual(client.baseURL, "https://api.example.com")
    }

    func testNetworkClientWithInterceptors() {
        let interceptors: [any NetworkInterceptor] = [
            LoggingInterceptor(level: .info),
            RetryInterceptor(maxAttempts: 3)
        ]

        let client = NetworkClient(
            baseURL: "https://api.example.com",
            interceptors: interceptors
        )

        XCTAssertEqual(client.baseURL, "https://api.example.com")
    }

    // MARK: - NetworkError Tests

    func testNetworkErrorEquality() {
        XCTAssertEqual(NetworkError.invalidURL, NetworkError.invalidURL)
        XCTAssertEqual(NetworkError.timeout, NetworkError.timeout)
        XCTAssertEqual(NetworkError.noConnection, NetworkError.noConnection)
        XCTAssertEqual(NetworkError.cancelled, NetworkError.cancelled)
        XCTAssertEqual(NetworkError.noData, NetworkError.noData)

        XCTAssertEqual(
            NetworkError.httpError(statusCode: 404, data: nil),
            NetworkError.httpError(statusCode: 404, data: nil)
        )
    }

    func testNetworkErrorDescriptions() {
        XCTAssertNotNil(NetworkError.invalidURL.errorDescription)
        XCTAssertNotNil(NetworkError.timeout.errorDescription)
        XCTAssertNotNil(NetworkError.noConnection.errorDescription)
        XCTAssertNotNil(NetworkError.cancelled.errorDescription)
        XCTAssertNotNil(NetworkError.noData.errorDescription)
        XCTAssertNotNil(NetworkError.certificatePinningFailed.errorDescription)
    }

    // MARK: - Endpoint Tests

    func testEndpointCreation() {
        let endpoint = Endpoint(path: "/users", method: .get)
        XCTAssertEqual(endpoint.path, "/users")
        XCTAssertEqual(endpoint.method, .get)
    }

    func testEndpointWithQueryItems() {
        let endpoint = Endpoint(
            path: "/users",
            method: .get,
            queryItems: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "limit", value: "25")
            ]
        )

        XCTAssertEqual(endpoint.queryItems?.count, 2)
    }

    func testEndpointURLRequest() throws {
        let endpoint = Endpoint(
            path: "/users",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: Data()
        )

        let request = try endpoint.urlRequest(baseURL: "https://api.example.com")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/users")
    }

    // MARK: - RequestBuilder Tests

    func testRequestBuilderBasicUsage() {
        let endpoint = RequestBuilder()
            .path("/users")
            .method(.get)
            .build()

        XCTAssertEqual(endpoint.path, "/users")
        XCTAssertEqual(endpoint.method, .get)
    }

    func testRequestBuilderWithHeaders() {
        let endpoint = RequestBuilder()
            .path("/users")
            .method(.post)
            .header("Authorization", "Bearer token123")
            .header("Content-Type", "application/json")
            .build()

        XCTAssertEqual(endpoint.headers?["Authorization"], "Bearer token123")
        XCTAssertEqual(endpoint.headers?["Content-Type"], "application/json")
    }

    func testRequestBuilderWithQueryParameters() {
        let endpoint = RequestBuilder()
            .path("/search")
            .method(.get)
            .query("q", "swift")
            .query("page", "1")
            .build()

        XCTAssertEqual(endpoint.queryItems?.count, 2)
    }

    func testRequestBuilderWithTimeout() {
        let endpoint = RequestBuilder()
            .path("/slow")
            .method(.get)
            .timeout(60)
            .build()

        XCTAssertEqual(endpoint.timeoutInterval, 60)
    }

    // MARK: - NetworkResponse Tests

    func testNetworkResponseCreation() {
        let data = "test".data(using: .utf8)!
        let response = NetworkResponse(
            data: data,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            originalRequest: nil,
            httpResponse: nil
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.data, data)
        XCTAssertTrue(response.isSuccess)
    }

    func testNetworkResponseStatusCategories() {
        let success = NetworkResponse(data: Data(), statusCode: 200, headers: [:], originalRequest: nil, httpResponse: nil)
        let redirect = NetworkResponse(data: Data(), statusCode: 301, headers: [:], originalRequest: nil, httpResponse: nil)
        let clientError = NetworkResponse(data: Data(), statusCode: 404, headers: [:], originalRequest: nil, httpResponse: nil)
        let serverError = NetworkResponse(data: Data(), statusCode: 500, headers: [:], originalRequest: nil, httpResponse: nil)

        XCTAssertTrue(success.isSuccess)
        XCTAssertFalse(redirect.isSuccess)
        XCTAssertFalse(clientError.isSuccess)
        XCTAssertFalse(serverError.isSuccess)
    }

    // MARK: - MultipartFormData Tests

    func testMultipartFormDataCreation() {
        var multipart = MultipartFormData()
        multipart.append(data: "test".data(using: .utf8)!, name: "field1")

        XCTAssertFalse(multipart.encode().isEmpty)
        XCTAssertTrue(multipart.contentType.hasPrefix("multipart/form-data"))
    }

    func testMultipartFormDataWithFile() {
        var multipart = MultipartFormData()
        let fileData = "file content".data(using: .utf8)!
        multipart.append(
            data: fileData,
            name: "file",
            fileName: "test.txt",
            mimeType: "text/plain"
        )

        let encoded = multipart.encode()
        XCTAssertFalse(encoded.isEmpty)
    }

    // MARK: - URLEncodedForm Tests

    func testURLEncodedFormBasic() {
        let form = URLEncodedForm()
            .add("username", "john")
            .add("password", "secret")

        let encoded = form.encodeToString()
        XCTAssertTrue(encoded.contains("username=john"))
        XCTAssertTrue(encoded.contains("password=secret"))
    }

    func testURLEncodedFormWithSpecialCharacters() {
        let form = URLEncodedForm()
            .add("query", "hello world")

        let encoded = form.encodeToString()
        XCTAssertTrue(encoded.contains("%20") || encoded.contains("+"))
    }

    func testURLEncodedFormDecoding() {
        let decoded = URLEncodedForm.decode("name=John&age=30")
        XCTAssertEqual(decoded.fields.count, 2)
    }

    // MARK: - Interceptor Tests

    func testLoggingInterceptorCreation() {
        let interceptor = LoggingInterceptor(level: .debug)
        XCTAssertNotNil(interceptor)
    }

    func testRetryInterceptorCreation() {
        let interceptor = RetryInterceptor(maxAttempts: 3)
        XCTAssertNotNil(interceptor)
    }

    func testAuthInterceptorCreation() {
        let interceptor = AuthInterceptor { "token123" }
        XCTAssertNotNil(interceptor)
    }

    // MARK: - InterceptorChain Tests

    func testInterceptorChainBuilding() {
        let chain = InterceptorChain()
            .add(LoggingInterceptor(level: .info))
            .add(RetryInterceptor(maxAttempts: 3))

        XCTAssertEqual(chain.count, 2)
    }

    func testInterceptorChainFreeze() {
        let chain = InterceptorChain()
            .add(LoggingInterceptor(level: .info))
            .freeze()

        chain.add(RetryInterceptor(maxAttempts: 1))
        XCTAssertEqual(chain.count, 1) // Should still be 1 after freeze
    }

    // MARK: - MockResponse Tests

    func testMockResponseCreation() {
        let response = MockResponse(statusCode: 200)
        XCTAssertEqual(response.statusCode, 200)
    }

    func testMockResponseJSON() {
        let response = MockResponse.json(["key": "value"])
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["Content-Type"], "application/json")
    }

    func testMockResponseError() {
        let response = MockResponse.error(NetworkError.timeout)
        XCTAssertNotNil(response.error)
    }

    func testMockResponsePresets() {
        let notFound = MockResponse.notFound
        let unauthorized = MockResponse.unauthorized
        let serverError = MockResponse.serverError

        XCTAssertEqual(notFound.statusCode, 404)
        XCTAssertEqual(unauthorized.statusCode, 401)
        XCTAssertEqual(serverError.statusCode, 500)
    }

    // MARK: - ResponseValidator Tests

    func testStatusCodeValidator() async throws {
        let validator = StatusCodeValidator(200...299)
        let response = NetworkResponse(data: Data(), statusCode: 200, headers: [:], originalRequest: nil, httpResponse: nil)

        try await validator.validate(response)
    }

    func testStatusCodeValidatorFailure() async {
        let validator = StatusCodeValidator(200...299)
        let response = NetworkResponse(data: Data(), statusCode: 404, headers: [:], originalRequest: nil, httpResponse: nil)

        do {
            try await validator.validate(response)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is NetworkError)
        }
    }

    func testContentTypeValidator() async throws {
        let validator = ContentTypeValidator(expected: "application/json")
        let response = NetworkResponse(data: Data(), statusCode: 200, headers: ["Content-Type": "application/json"], originalRequest: nil, httpResponse: nil)

        try await validator.validate(response)
    }

    // MARK: - DownloadProgress Tests

    func testDownloadProgressBasic() {
        let progress = DownloadProgress(bytesReceived: 500, totalBytes: 1000)

        XCTAssertEqual(progress.fractionCompleted, 0.5)
        XCTAssertEqual(progress.percentComplete, 50)
        XCTAssertFalse(progress.isComplete)
    }

    func testDownloadProgressComplete() {
        let progress = DownloadProgress(bytesReceived: 1000, totalBytes: 1000)

        XCTAssertEqual(progress.fractionCompleted, 1.0)
        XCTAssertEqual(progress.percentComplete, 100)
        XCTAssertTrue(progress.isComplete)
    }

    func testDownloadProgressFormatting() {
        let progress = DownloadProgress(bytesReceived: 1024 * 1024, totalBytes: 10 * 1024 * 1024)

        XCTAssertFalse(progress.formattedBytesReceived.isEmpty)
        XCTAssertFalse(progress.formattedProgress.isEmpty)
    }

    // MARK: - WebSocketMessage Tests

    func testWebSocketTextMessage() {
        let message = WebSocketMessage.text("Hello")

        XCTAssertTrue(message.isText)
        XCTAssertFalse(message.isBinary)
        XCTAssertEqual(message.textValue, "Hello")
    }

    func testWebSocketBinaryMessage() {
        let data = "test".data(using: .utf8)!
        let message = WebSocketMessage.binary(data)

        XCTAssertFalse(message.isText)
        XCTAssertTrue(message.isBinary)
        XCTAssertEqual(message.binaryValue, data)
    }

    func testWebSocketJSONMessage() throws {
        let message = try WebSocketMessage.json(["action": "ping"])

        XCTAssertTrue(message.isText)
        XCTAssertNotNil(message.textValue)
    }

    // MARK: - WebSocketState Tests

    func testWebSocketStateConnected() {
        let info = WebSocketState.ConnectionInfo()
        let state = WebSocketState.connected(info)

        XCTAssertTrue(state.isConnected)
        XCTAssertFalse(state.isDisconnected)
        XCTAssertNotNil(state.connectionInfo)
    }

    func testWebSocketStateDisconnected() {
        let state = WebSocketState.disconnected(reason: .normal)

        XCTAssertFalse(state.isConnected)
        XCTAssertTrue(state.isDisconnected)
        XCTAssertNotNil(state.disconnectReason)
    }

    // MARK: - ReconnectionStrategy Tests

    func testReconnectionStrategyDelays() {
        let strategy = WebSocketReconnectionStrategy(
            baseDelay: 1.0,
            backoffMultiplier: 2.0,
            backoffType: .exponential
        )

        XCTAssertEqual(strategy.delay(forAttempt: 1), 1.0)
        XCTAssertEqual(strategy.delay(forAttempt: 2), 2.0)
        XCTAssertEqual(strategy.delay(forAttempt: 3), 4.0)
    }

    func testReconnectionStrategyMaxDelay() {
        let strategy = WebSocketReconnectionStrategy(
            baseDelay: 1.0,
            maxDelay: 5.0,
            backoffMultiplier: 2.0
        )

        XCTAssertEqual(strategy.delay(forAttempt: 10), 5.0) // Should be capped
    }

    // MARK: - Data Extensions Tests

    func testDataHexString() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
        XCTAssertEqual(data.hexString, "48656c6c6f")
    }

    func testDataFromHex() {
        let data = Data.fromHex("48656c6c6f")
        XCTAssertEqual(data?.utf8String, "Hello")
    }

    func testDataSHA256() {
        let data = "test".data(using: .utf8)!
        let hash = data.sha256
        XCTAssertEqual(hash.count, 32)
    }

    func testDataIsJSON() {
        let jsonData = "{\"key\":\"value\"}".data(using: .utf8)!
        let textData = "plain text".data(using: .utf8)!

        XCTAssertTrue(jsonData.isJSON)
        XCTAssertFalse(textData.isJSON)
    }

    // MARK: - HTTPURLResponse Extensions Tests

    func testHTTPURLResponseStatusCategories() {
        let url = URL(string: "https://example.com")!

        let success = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let redirect = HTTPURLResponse(url: url, statusCode: 301, httpVersion: nil, headerFields: nil)!
        let clientError = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let serverError = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!

        XCTAssertTrue(success.isSuccess)
        XCTAssertTrue(redirect.isRedirect)
        XCTAssertTrue(clientError.isClientError)
        XCTAssertTrue(serverError.isServerError)
    }

    func testHTTPURLResponseContentType() {
        let url = URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json; charset=utf-8"]
        )!

        XCTAssertEqual(response.mimeType, "application/json")
        XCTAssertEqual(response.charset, "utf-8")
        XCTAssertTrue(response.isJSON)
    }

    // MARK: - NetworkConfiguration Tests

    func testNetworkConfigurationDefaults() {
        let config = NetworkConfiguration.default

        XCTAssertEqual(config.defaultTimeout, 30)
        XCTAssertTrue(config.waitsForConnectivity)
        XCTAssertTrue(config.shouldCacheResponses)
    }

    func testNetworkConfigurationPresets() {
        let highPerf = NetworkConfiguration.highPerformance
        let lowBand = NetworkConfiguration.lowBandwidth

        XCTAssertLessThan(highPerf.defaultTimeout, lowBand.defaultTimeout)
        XCTAssertGreaterThan(highPerf.maxConcurrentRequests, lowBand.maxConcurrentRequests)
    }

    func testNetworkConfigurationBuilder() {
        let config = NetworkConfiguration.Builder()
            .defaultTimeout(60)
            .maxConcurrentRequests(8)
            .build()

        XCTAssertEqual(config.defaultTimeout, 60)
        XCTAssertEqual(config.maxConcurrentRequests, 8)
    }

    // MARK: - RequestModifier Tests

    func testHeaderModifier() async throws {
        let modifier = HeaderModifier(headers: ["X-Custom": "value"])
        var request = URLRequest(url: URL(string: "https://example.com")!)

        request = try await modifier.modify(request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom"), "value")
    }

    func testBearerTokenModifier() async throws {
        let modifier = BearerTokenModifier(token: "abc123")
        var request = URLRequest(url: URL(string: "https://example.com")!)

        request = try await modifier.modify(request)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testTimeoutModifier() async throws {
        let modifier = TimeoutModifier(30)
        var request = URLRequest(url: URL(string: "https://example.com")!)

        request = try await modifier.modify(request)

        XCTAssertEqual(request.timeoutInterval, 30)
    }

    // MARK: - StubResponseStore Tests

    func testStubResponseStoreBasic() throws {
        let store = StubResponseStore()
        store.stub(.get, "/users", response: .json(["users": []]))

        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "GET"

        let response = try store.response(for: request)
        XCTAssertEqual(response.statusCode, 200)
    }

    func testStubResponseStoreBuilder() throws {
        let store = StubResponseStore()
            .when(.get, "/users")
            .thenReturn(.json(["users": []]))

        var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
        request.httpMethod = "GET"

        let response = try store.response(for: request)
        XCTAssertEqual(response.statusCode, 200)
    }
}

// MARK: - Async Test Helpers

extension XCTestCase {

    func asyncTest(
        timeout: TimeInterval = 10,
        _ block: @escaping () async throws -> Void
    ) {
        let expectation = expectation(description: "Async test")

        Task {
            do {
                try await block()
                expectation.fulfill()
            } catch {
                XCTFail("Async test failed: \(error)")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: timeout)
    }
}
