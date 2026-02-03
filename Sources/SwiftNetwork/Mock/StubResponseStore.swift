import Foundation

/// A store for managing stubbed responses for testing.
///
/// `StubResponseStore` provides a centralized way to define and manage
/// mock responses for different endpoints during testing.
///
/// ```swift
/// let store = StubResponseStore()
/// store.stub(.get, "/users") { _ in .json(["id": 1, "name": "John"]) }
/// store.stub(.post, "/users") { request in
///     guard let body = request.httpBody else { return .error(MockError.invalidRequest) }
///     return .json(["success": true])
/// }
/// ```
public final class StubResponseStore: @unchecked Sendable {

    // MARK: - Types

    /// HTTP method for matching.
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
        case head = "HEAD"
        case options = "OPTIONS"
        case any = "*"
    }

    /// A stub entry in the store.
    public struct StubEntry: Sendable {
        let method: Method
        let path: String
        let queryMatcher: (@Sendable ([String: String]) -> Bool)?
        let headerMatcher: (@Sendable ([String: String]) -> Bool)?
        let bodyMatcher: (@Sendable (Data?) -> Bool)?
        let responseProvider: @Sendable (URLRequest) -> MockResponse
        let callCount: Int
        let maxCalls: Int?
        let delay: TimeInterval

        var isExhausted: Bool {
            guard let max = maxCalls else { return false }
            return callCount >= max
        }
    }

    /// Statistics about stub usage.
    public struct StubStatistics: Sendable {
        public let totalStubs: Int
        public let matchedRequests: Int
        public let unmatchedRequests: Int
        public let stubCallCounts: [String: Int]
    }

    // MARK: - Properties

    private var stubs: [StubEntry] = []
    private var unmatchedRequests: [URLRequest] = []
    private var callCounts: [String: Int] = [:]
    private let lock = NSLock()

    /// Whether to fail on unmatched requests.
    public var failOnUnmatched: Bool = true

    /// Default response for unmatched requests.
    public var defaultResponse: MockResponse?

    // MARK: - Initialization

    /// Creates a new stub response store.
    public init() {}

    // MARK: - Stubbing

    /// Stubs a request with a static response.
    ///
    /// - Parameters:
    ///   - method: The HTTP method to match.
    ///   - path: The path to match.
    ///   - response: The response to return.
    @discardableResult
    public func stub(
        _ method: Method,
        _ path: String,
        response: MockResponse
    ) -> StubResponseStore {
        stub(method, path) { _ in response }
    }

    /// Stubs a request with a dynamic response.
    ///
    /// - Parameters:
    ///   - method: The HTTP method to match.
    ///   - path: The path to match.
    ///   - responseProvider: A closure that generates the response.
    @discardableResult
    public func stub(
        _ method: Method,
        _ path: String,
        responseProvider: @escaping @Sendable (URLRequest) -> MockResponse
    ) -> StubResponseStore {
        lock.withLock {
            let entry = StubEntry(
                method: method,
                path: path,
                queryMatcher: nil,
                headerMatcher: nil,
                bodyMatcher: nil,
                responseProvider: responseProvider,
                callCount: 0,
                maxCalls: nil,
                delay: 0
            )
            stubs.append(entry)
        }
        return self
    }

    /// Creates a stub builder for more complex matching.
    ///
    /// - Parameters:
    ///   - method: The HTTP method to match.
    ///   - path: The path to match.
    /// - Returns: A stub builder.
    public func when(_ method: Method, _ path: String) -> StubBuilder {
        StubBuilder(store: self, method: method, path: path)
    }

    // MARK: - Response Retrieval

    /// Gets the response for a request.
    ///
    /// - Parameter request: The request to match.
    /// - Returns: The mock response.
    /// - Throws: If no matching stub is found and failOnUnmatched is true.
    public func response(for request: URLRequest) throws -> MockResponse {
        lock.lock()
        defer { lock.unlock() }

        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let stubKey = "\(method) \(path)"

        // Find matching stub
        for (index, stub) in stubs.enumerated() {
            guard matchesStub(stub, request: request) else { continue }
            guard !stub.isExhausted else { continue }

            // Update call count
            var updatedStub = stub
            let newCallCount = stub.callCount + 1
            updatedStub = StubEntry(
                method: stub.method,
                path: stub.path,
                queryMatcher: stub.queryMatcher,
                headerMatcher: stub.headerMatcher,
                bodyMatcher: stub.bodyMatcher,
                responseProvider: stub.responseProvider,
                callCount: newCallCount,
                maxCalls: stub.maxCalls,
                delay: stub.delay
            )
            stubs[index] = updatedStub
            callCounts[stubKey, default: 0] += 1

            return stub.responseProvider(request)
        }

        // No match found
        unmatchedRequests.append(request)

        if let defaultResponse = defaultResponse {
            return defaultResponse
        }

        if failOnUnmatched {
            throw MockError.noMatchingStub(request: request)
        }

        return .notFound
    }

    private func matchesStub(_ stub: StubEntry, request: URLRequest) -> Bool {
        // Match method
        if stub.method != .any {
            guard request.httpMethod == stub.method.rawValue else { return false }
        }

        // Match path
        guard request.url?.path == stub.path else { return false }

        // Match query parameters
        if let queryMatcher = stub.queryMatcher {
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]
            guard queryMatcher(queryItems) else { return false }
        }

        // Match headers
        if let headerMatcher = stub.headerMatcher {
            let headers = request.allHTTPHeaderFields ?? [:]
            guard headerMatcher(headers) else { return false }
        }

        // Match body
        if let bodyMatcher = stub.bodyMatcher {
            guard bodyMatcher(request.httpBody) else { return false }
        }

        return true
    }

    // MARK: - Management

    /// Removes all stubs.
    public func removeAll() {
        lock.withLock {
            stubs.removeAll()
            unmatchedRequests.removeAll()
            callCounts.removeAll()
        }
    }

    /// Removes stubs matching a path.
    ///
    /// - Parameter path: The path to remove.
    public func remove(path: String) {
        lock.withLock {
            stubs.removeAll { $0.path == path }
        }
    }

    /// Removes stubs matching a method and path.
    ///
    /// - Parameters:
    ///   - method: The method to match.
    ///   - path: The path to match.
    public func remove(_ method: Method, _ path: String) {
        lock.withLock {
            stubs.removeAll { $0.method == method && $0.path == path }
        }
    }

    // MARK: - Statistics

    /// Gets statistics about stub usage.
    public func statistics() -> StubStatistics {
        lock.withLock {
            StubStatistics(
                totalStubs: stubs.count,
                matchedRequests: callCounts.values.reduce(0, +),
                unmatchedRequests: unmatchedRequests.count,
                stubCallCounts: callCounts
            )
        }
    }

    /// Gets unmatched requests.
    public func getUnmatchedRequests() -> [URLRequest] {
        lock.withLock { unmatchedRequests }
    }

    /// Gets the call count for a stub.
    ///
    /// - Parameters:
    ///   - method: The method.
    ///   - path: The path.
    /// - Returns: The number of times the stub was called.
    public func callCount(for method: Method, path: String) -> Int {
        lock.withLock {
            callCounts["\(method.rawValue) \(path)"] ?? 0
        }
    }

    /// Verifies all stubs were called at least once.
    ///
    /// - Returns: True if all stubs were called.
    public func verifyAllStubsCalled() -> Bool {
        lock.withLock {
            stubs.allSatisfy { $0.callCount > 0 }
        }
    }
}

// MARK: - Stub Builder

/// Builder for creating complex stub configurations.
public final class StubBuilder: @unchecked Sendable {

    private let store: StubResponseStore
    private let method: StubResponseStore.Method
    private let path: String
    private var queryMatcher: (@Sendable ([String: String]) -> Bool)?
    private var headerMatcher: (@Sendable ([String: String]) -> Bool)?
    private var bodyMatcher: (@Sendable (Data?) -> Bool)?
    private var maxCalls: Int?
    private var delay: TimeInterval = 0

    init(store: StubResponseStore, method: StubResponseStore.Method, path: String) {
        self.store = store
        self.method = method
        self.path = path
    }

    /// Adds a query parameter matcher.
    @discardableResult
    public func withQuery(_ matcher: @escaping @Sendable ([String: String]) -> Bool) -> StubBuilder {
        self.queryMatcher = matcher
        return self
    }

    /// Requires specific query parameters.
    @discardableResult
    public func withQuery(_ params: [String: String]) -> StubBuilder {
        withQuery { query in
            for (key, value) in params {
                if query[key] != value { return false }
            }
            return true
        }
    }

    /// Adds a header matcher.
    @discardableResult
    public func withHeaders(_ matcher: @escaping @Sendable ([String: String]) -> Bool) -> StubBuilder {
        self.headerMatcher = matcher
        return self
    }

    /// Requires specific headers.
    @discardableResult
    public func withHeaders(_ headers: [String: String]) -> StubBuilder {
        withHeaders { requestHeaders in
            for (key, value) in headers {
                if requestHeaders[key] != value { return false }
            }
            return true
        }
    }

    /// Adds a body matcher.
    @discardableResult
    public func withBody(_ matcher: @escaping @Sendable (Data?) -> Bool) -> StubBuilder {
        self.bodyMatcher = matcher
        return self
    }

    /// Requires a JSON body matching a predicate.
    @discardableResult
    public func withJSONBody(_ matcher: @escaping @Sendable ([String: Any]) -> Bool) -> StubBuilder {
        withBody { data in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            return matcher(json)
        }
    }

    /// Limits the number of times this stub can be called.
    @discardableResult
    public func times(_ count: Int) -> StubBuilder {
        self.maxCalls = count
        return self
    }

    /// Adds a delay before returning the response.
    @discardableResult
    public func withDelay(_ seconds: TimeInterval) -> StubBuilder {
        self.delay = seconds
        return self
    }

    /// Returns a static response.
    @discardableResult
    public func thenReturn(_ response: MockResponse) -> StubResponseStore {
        thenRespond { _ in response }
    }

    /// Returns a dynamic response.
    @discardableResult
    public func thenRespond(
        _ provider: @escaping @Sendable (URLRequest) -> MockResponse
    ) -> StubResponseStore {
        let entry = StubResponseStore.StubEntry(
            method: method,
            path: path,
            queryMatcher: queryMatcher,
            headerMatcher: headerMatcher,
            bodyMatcher: bodyMatcher,
            responseProvider: { [delay] request in
                var response = provider(request)
                if delay > 0 {
                    response = response.withDelay(delay)
                }
                return response
            },
            callCount: 0,
            maxCalls: maxCalls,
            delay: delay
        )

        store.lock.withLock {
            store.stubs.append(entry)
        }

        return store
    }

    /// Returns a JSON response.
    @discardableResult
    public func thenReturnJSON(_ value: [String: Any]) -> StubResponseStore {
        thenReturn(.json(value))
    }

    /// Returns an error.
    @discardableResult
    public func thenFail(with error: Error) -> StubResponseStore {
        thenReturn(.error(error))
    }
}

// MARK: - Private Lock Extension

private extension StubResponseStore {
    var lock: NSLock {
        NSLock()
    }
}

extension StubResponseStore.StubEntry: @unchecked Sendable {}
