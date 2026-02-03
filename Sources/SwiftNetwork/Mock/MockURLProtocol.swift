import Foundation

/// A URLProtocol subclass that intercepts requests for testing.
///
/// `MockURLProtocol` allows you to intercept URL requests and return
/// predetermined responses, useful for testing without network access.
///
/// ```swift
/// MockURLProtocol.requestHandler = { request in
///     let response = HTTPURLResponse(
///         url: request.url!,
///         statusCode: 200,
///         httpVersion: nil,
///         headerFields: nil
///     )!
///     return (response, Data())
/// }
///
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [MockURLProtocol.self]
/// let session = URLSession(configuration: config)
/// ```
public final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Types

    /// Handler type for mock requests.
    public typealias RequestHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    /// Async handler type for mock requests.
    public typealias AsyncRequestHandler = @Sendable (URLRequest) async throws -> (HTTPURLResponse, Data)

    /// Request matcher for conditional stubbing.
    public struct RequestMatcher: Sendable {
        let matches: @Sendable (URLRequest) -> Bool
        let handler: RequestHandler

        public init(
            matches: @escaping @Sendable (URLRequest) -> Bool,
            handler: @escaping RequestHandler
        ) {
            self.matches = matches
            self.handler = handler
        }
    }

    // MARK: - Static Properties

    /// The global request handler.
    public nonisolated(unsafe) static var requestHandler: RequestHandler?

    /// The global async request handler.
    public nonisolated(unsafe) static var asyncRequestHandler: AsyncRequestHandler?

    /// Request matchers for conditional stubbing.
    public nonisolated(unsafe) static var matchers: [RequestMatcher] = []

    /// Recorded requests for verification.
    public nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    /// Whether to record requests.
    public nonisolated(unsafe) static var recordRequests: Bool = false

    /// Lock for thread safety.
    private static let lock = NSLock()

    // MARK: - URLProtocol Override

    public override class func canInit(with request: URLRequest) -> Bool {
        // Handle all requests when a handler is set
        return requestHandler != nil || asyncRequestHandler != nil || !matchers.isEmpty
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        if Self.recordRequests {
            Self.lock.withLock {
                Self.recordedRequests.append(request)
            }
        }

        // Try matchers first
        for matcher in Self.matchers {
            if matcher.matches(request) {
                handleRequest(with: matcher.handler)
                return
            }
        }

        // Try async handler
        if let asyncHandler = Self.asyncRequestHandler {
            Task {
                do {
                    let (response, data) = try await asyncHandler(request)
                    sendResponse(response: response, data: data)
                } catch {
                    sendError(error)
                }
            }
            return
        }

        // Try sync handler
        if let handler = Self.requestHandler {
            handleRequest(with: handler)
            return
        }

        // No handler configured
        sendError(MockError.noMatchingStub(request: request))
    }

    public override func stopLoading() {
        // Nothing to do
    }

    // MARK: - Private Helpers

    private func handleRequest(with handler: RequestHandler) {
        do {
            let (response, data) = try handler(request)
            sendResponse(response: response, data: data)
        } catch {
            sendError(error)
        }
    }

    private func sendResponse(response: HTTPURLResponse, data: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func sendError(_ error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }

    // MARK: - Public API

    /// Resets all mock configuration.
    public static func reset() {
        lock.withLock {
            requestHandler = nil
            asyncRequestHandler = nil
            matchers.removeAll()
            recordedRequests.removeAll()
            recordRequests = false
        }
    }

    /// Adds a matcher for specific requests.
    ///
    /// - Parameters:
    ///   - matcher: The condition to match.
    ///   - handler: The handler for matched requests.
    public static func addMatcher(
        matching matcher: @escaping @Sendable (URLRequest) -> Bool,
        handler: @escaping RequestHandler
    ) {
        lock.withLock {
            matchers.append(RequestMatcher(matches: matcher, handler: handler))
        }
    }

    /// Stubs requests to a specific URL.
    ///
    /// - Parameters:
    ///   - url: The URL to stub.
    ///   - response: The mock response to return.
    public static func stub(url: URL, with response: MockResponse) {
        addMatcher(matching: { $0.url == url }) { request in
            try mockResponseToURLResponse(response, request: request)
        }
    }

    /// Stubs requests matching a URL pattern.
    ///
    /// - Parameters:
    ///   - pattern: The regex pattern to match.
    ///   - response: The mock response to return.
    public static func stub(pattern: String, with response: MockResponse) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        addMatcher(matching: { request in
            guard let urlString = request.url?.absoluteString else { return false }
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
        }) { request in
            try mockResponseToURLResponse(response, request: request)
        }
    }

    /// Stubs requests to a specific path.
    ///
    /// - Parameters:
    ///   - path: The path to stub.
    ///   - method: Optional HTTP method to match.
    ///   - response: The mock response to return.
    public static func stub(
        path: String,
        method: String? = nil,
        with response: MockResponse
    ) {
        addMatcher(matching: { request in
            guard request.url?.path == path else { return false }
            if let method = method {
                return request.httpMethod == method
            }
            return true
        }) { request in
            try mockResponseToURLResponse(response, request: request)
        }
    }

    /// Stubs all requests with the same response.
    ///
    /// - Parameter response: The mock response to return.
    public static func stubAll(with response: MockResponse) {
        requestHandler = { request in
            try mockResponseToURLResponse(response, request: request)
        }
    }

    /// Gets recorded requests matching a predicate.
    ///
    /// - Parameter predicate: The filter predicate.
    /// - Returns: Matching requests.
    public static func requests(matching predicate: (URLRequest) -> Bool) -> [URLRequest] {
        lock.withLock {
            recordedRequests.filter(predicate)
        }
    }

    /// Gets recorded requests to a specific URL.
    ///
    /// - Parameter url: The URL to find.
    /// - Returns: Matching requests.
    public static func requests(to url: URL) -> [URLRequest] {
        requests { $0.url == url }
    }

    /// Gets recorded requests to a specific path.
    ///
    /// - Parameter path: The path to find.
    /// - Returns: Matching requests.
    public static func requests(toPath path: String) -> [URLRequest] {
        requests { $0.url?.path == path }
    }

    private static func mockResponseToURLResponse(
        _ mockResponse: MockResponse,
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        if let error = mockResponse.error {
            throw error
        }

        guard let url = request.url else {
            throw MockError.unexpectedRequest(request)
        }

        let data = try mockResponse.resolveBodyData()

        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: mockResponse.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: mockResponse.headers
        ) else {
            throw MockError.unexpectedRequest(request)
        }

        return (httpResponse, data)
    }
}

// MARK: - URLSession Extension

extension URLSession {

    /// Creates a URLSession configured with MockURLProtocol.
    ///
    /// - Parameter configuration: Base configuration. Defaults to `.ephemeral`.
    /// - Returns: A session configured for mocking.
    public static func mock(
        configuration: URLSessionConfiguration = .ephemeral
    ) -> URLSession {
        let config = configuration
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Mock Session Builder

/// Builder for creating mock URLSession configurations.
public final class MockSessionBuilder: @unchecked Sendable {

    private var stubs: [(matcher: (URLRequest) -> Bool, response: MockResponse)] = []
    private var defaultResponse: MockResponse?
    private var recordRequests: Bool = false

    /// Creates a new mock session builder.
    public init() {}

    /// Adds a stub for a specific URL.
    @discardableResult
    public func stub(url: URL, response: MockResponse) -> MockSessionBuilder {
        stubs.append(({ $0.url == url }, response))
        return self
    }

    /// Adds a stub for a specific path.
    @discardableResult
    public func stub(path: String, method: String? = nil, response: MockResponse) -> MockSessionBuilder {
        stubs.append(({ request in
            guard request.url?.path == path else { return false }
            if let method = method {
                return request.httpMethod == method
            }
            return true
        }, response))
        return self
    }

    /// Sets the default response for unmatched requests.
    @discardableResult
    public func defaultResponse(_ response: MockResponse) -> MockSessionBuilder {
        self.defaultResponse = response
        return self
    }

    /// Enables request recording.
    @discardableResult
    public func recordingRequests() -> MockSessionBuilder {
        self.recordRequests = true
        return self
    }

    /// Builds the configured URLSession.
    public func build() -> URLSession {
        MockURLProtocol.reset()
        MockURLProtocol.recordRequests = recordRequests

        for (matcher, response) in stubs {
            MockURLProtocol.addMatcher(matching: matcher) { request in
                try MockURLProtocol.mockResponseToURLResponse(response, request: request)
            }
        }

        if let defaultResponse = defaultResponse {
            MockURLProtocol.stubAll(with: defaultResponse)
        }

        return .mock()
    }
}

// MARK: - Helper Extensions

extension MockURLProtocol {
    fileprivate static func mockResponseToURLResponse(
        _ mockResponse: MockResponse,
        request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        if let error = mockResponse.error {
            throw error
        }

        guard let url = request.url else {
            throw MockError.unexpectedRequest(request)
        }

        let data = try mockResponse.resolveBodyData()

        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: mockResponse.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: mockResponse.headers
        ) else {
            throw MockError.unexpectedRequest(request)
        }

        return (httpResponse, data)
    }
}
