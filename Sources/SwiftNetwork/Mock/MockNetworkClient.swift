import Foundation

/// A mock network client for unit testing without hitting the network.
///
/// Stub responses for specific paths and methods, then use `MockNetworkClient`
/// as a drop-in replacement during tests.
///
/// ```swift
/// let mock = MockNetworkClient()
/// mock.stub(path: "/users", response: [
///     User(id: 1, name: "Test")
/// ])
///
/// let users: [User] = try await mock.request(
///     Endpoint(path: "/users", method: .get)
/// )
/// ```
public final class MockNetworkClient: @unchecked Sendable {

    // MARK: - Types

    /// A key identifying a stubbed route.
    private struct StubKey: Hashable {
        let path: String
        let method: HTTPMethod
    }

    /// A stubbed response configuration.
    private struct StubResponse {
        let data: Data
        let statusCode: Int
        let headers: [String: String]
        let delay: TimeInterval
    }

    // MARK: - Properties

    private var stubs: [StubKey: StubResponse] = [:]
    private var requestLog: [Endpoint] = []
    private let lock = NSLock()
    private let decoder: JSONDecoder

    /// Error to throw on unstubbed requests. Defaults to ``NetworkError/noData``.
    public var defaultError: NetworkError = .noData

    // MARK: - Initialization

    /// Creates a new mock client.
    ///
    /// - Parameter decoder: The JSON decoder for response parsing.
    public init(decoder: JSONDecoder = .init()) {
        self.decoder = decoder
    }

    // MARK: - Stubbing

    /// Stubs a response for a given path and method.
    ///
    /// - Parameters:
    ///   - path: The endpoint path to match.
    ///   - method: The HTTP method to match. Defaults to `.get`.
    ///   - statusCode: The status code to return. Defaults to 200.
    ///   - headers: Response headers. Defaults to empty.
    ///   - delay: Simulated network delay in seconds. Defaults to 0.
    ///   - response: The encodable response body.
    public func stub<T: Encodable>(
        path: String,
        method: HTTPMethod = .get,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        delay: TimeInterval = 0,
        response: T
    ) {
        let data = (try? JSONEncoder().encode(response)) ?? Data()
        let key = StubKey(path: path, method: method)
        lock.lock()
        stubs[key] = StubResponse(data: data, statusCode: statusCode, headers: headers, delay: delay)
        lock.unlock()
    }

    /// Stubs a raw data response for a given path.
    ///
    /// - Parameters:
    ///   - path: The endpoint path to match.
    ///   - method: The HTTP method to match. Defaults to `.get`.
    ///   - statusCode: The status code to return. Defaults to 200.
    ///   - data: The raw response data.
    public func stubData(
        path: String,
        method: HTTPMethod = .get,
        statusCode: Int = 200,
        data: Data
    ) {
        let key = StubKey(path: path, method: method)
        lock.lock()
        stubs[key] = StubResponse(data: data, statusCode: statusCode, headers: [:], delay: 0)
        lock.unlock()
    }

    /// Removes all stubs and recorded requests.
    public func reset() {
        lock.lock()
        stubs.removeAll()
        requestLog.removeAll()
        lock.unlock()
    }

    // MARK: - Request

    /// Performs a mock request returning the stubbed response.
    ///
    /// - Parameter endpoint: The endpoint to look up.
    /// - Returns: The decoded response from the matching stub.
    /// - Throws: ``NetworkError`` if no stub matches or decoding fails.
    public func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        lock.lock()
        requestLog.append(endpoint)
        lock.unlock()

        let key = StubKey(path: endpoint.path, method: endpoint.method)

        lock.lock()
        let stub = stubs[key]
        lock.unlock()

        guard let stub else {
            throw defaultError
        }

        if stub.delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(stub.delay * 1_000_000_000))
        }

        guard (200...299).contains(stub.statusCode) else {
            throw NetworkError.httpError(statusCode: stub.statusCode, data: stub.data)
        }

        do {
            return try decoder.decode(T.self, from: stub.data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    // MARK: - Inspection

    /// All endpoints that have been requested, in order.
    public var recordedRequests: [Endpoint] {
        lock.lock()
        defer { lock.unlock() }
        return requestLog
    }

    /// Whether a specific path and method combination was requested.
    public func wasRequested(path: String, method: HTTPMethod = .get) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.contains { $0.path == path && $0.method == method }
    }

    /// The number of times a specific path and method was requested.
    public func requestCount(path: String, method: HTTPMethod = .get) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestLog.filter { $0.path == path && $0.method == method }.count
    }
}
