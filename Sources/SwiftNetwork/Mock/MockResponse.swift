import Foundation

/// A configurable mock response for testing network requests.
///
/// `MockResponse` provides a flexible way to define expected responses
/// for unit testing without making actual network calls.
///
/// ```swift
/// let mockResponse = MockResponse(
///     statusCode: 200,
///     headers: ["Content-Type": "application/json"],
///     body: .json(["id": 1, "name": "Test"])
/// )
/// ```
public struct MockResponse: Sendable {

    // MARK: - Types

    /// The body type for mock responses.
    public enum Body: Sendable {
        /// Empty body.
        case empty

        /// Raw data body.
        case data(Data)

        /// String body with optional encoding.
        case string(String, encoding: String.Encoding = .utf8)

        /// JSON body from an encodable value.
        case json(Encodable & Sendable)

        /// JSON body from a dictionary.
        case jsonDictionary([String: Any])

        /// Load body from a file.
        case file(URL)

        /// Load body from a bundle resource.
        case resource(name: String, extension: String, bundle: Bundle = .main)
    }

    /// Timing configuration for mock responses.
    public struct Timing: Sendable {
        /// Delay before starting the response.
        public let delay: TimeInterval

        /// Whether to simulate streaming with chunks.
        public let chunked: Bool

        /// Number of chunks if streaming.
        public let chunkCount: Int

        /// Delay between chunks.
        public let chunkDelay: TimeInterval

        /// Creates a timing configuration.
        public init(
            delay: TimeInterval = 0,
            chunked: Bool = false,
            chunkCount: Int = 1,
            chunkDelay: TimeInterval = 0.1
        ) {
            self.delay = delay
            self.chunked = chunked
            self.chunkCount = chunkCount
            self.chunkDelay = chunkDelay
        }

        /// Immediate response with no delay.
        public static let immediate = Timing()

        /// Simulated network latency.
        public static let realistic = Timing(delay: 0.2)

        /// Slow network simulation.
        public static let slow = Timing(delay: 2.0)
    }

    // MARK: - Properties

    /// The HTTP status code.
    public let statusCode: Int

    /// The response headers.
    public let headers: [String: String]

    /// The response body.
    public let body: Body

    /// The response timing.
    public let timing: Timing

    /// An optional error to throw instead of returning a response.
    public let error: Error?

    // MARK: - Initialization

    /// Creates a mock response.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code. Defaults to 200.
    ///   - headers: The response headers.
    ///   - body: The response body.
    ///   - timing: The response timing.
    ///   - error: An optional error to throw.
    public init(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: Body = .empty,
        timing: Timing = .immediate,
        error: Error? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.timing = timing
        self.error = error
    }

    // MARK: - Factory Methods

    /// Creates a successful JSON response.
    ///
    /// - Parameters:
    ///   - value: The encodable value.
    ///   - statusCode: The status code. Defaults to 200.
    /// - Returns: A mock response.
    public static func json<T: Encodable & Sendable>(
        _ value: T,
        statusCode: Int = 200
    ) -> MockResponse {
        MockResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: .json(value)
        )
    }

    /// Creates a successful JSON response from a dictionary.
    ///
    /// - Parameters:
    ///   - dictionary: The dictionary value.
    ///   - statusCode: The status code. Defaults to 200.
    /// - Returns: A mock response.
    public static func json(
        _ dictionary: [String: Any],
        statusCode: Int = 200
    ) -> MockResponse {
        MockResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: .jsonDictionary(dictionary)
        )
    }

    /// Creates a successful empty response.
    ///
    /// - Parameter statusCode: The status code. Defaults to 204.
    /// - Returns: A mock response.
    public static func empty(statusCode: Int = 204) -> MockResponse {
        MockResponse(statusCode: statusCode, body: .empty)
    }

    /// Creates an error response.
    ///
    /// - Parameter error: The error to throw.
    /// - Returns: A mock response.
    public static func error(_ error: Error) -> MockResponse {
        MockResponse(error: error)
    }

    /// Creates a timeout error response.
    ///
    /// - Returns: A mock response.
    public static var timeout: MockResponse {
        MockResponse(error: NetworkError.timeout)
    }

    /// Creates a no connection error response.
    ///
    /// - Returns: A mock response.
    public static var noConnection: MockResponse {
        MockResponse(error: NetworkError.noConnection)
    }

    /// Creates a 404 not found response.
    ///
    /// - Returns: A mock response.
    public static var notFound: MockResponse {
        MockResponse(
            statusCode: 404,
            headers: ["Content-Type": "application/json"],
            body: .jsonDictionary(["error": "Not Found"])
        )
    }

    /// Creates a 401 unauthorized response.
    ///
    /// - Returns: A mock response.
    public static var unauthorized: MockResponse {
        MockResponse(
            statusCode: 401,
            headers: ["Content-Type": "application/json"],
            body: .jsonDictionary(["error": "Unauthorized"])
        )
    }

    /// Creates a 500 internal server error response.
    ///
    /// - Returns: A mock response.
    public static var serverError: MockResponse {
        MockResponse(
            statusCode: 500,
            headers: ["Content-Type": "application/json"],
            body: .jsonDictionary(["error": "Internal Server Error"])
        )
    }

    // MARK: - Data Resolution

    /// Resolves the body to raw data.
    ///
    /// - Returns: The body data.
    /// - Throws: If body resolution fails.
    public func resolveBodyData() throws -> Data {
        switch body {
        case .empty:
            return Data()

        case .data(let data):
            return data

        case .string(let string, let encoding):
            guard let data = string.data(using: encoding) else {
                throw MockError.stringEncodingFailed
            }
            return data

        case .json(let encodable):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(AnyEncodable(encodable))

        case .jsonDictionary(let dictionary):
            return try JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted)

        case .file(let url):
            return try Data(contentsOf: url)

        case .resource(let name, let ext, let bundle):
            guard let url = bundle.url(forResource: name, withExtension: ext) else {
                throw MockError.resourceNotFound(name: name, extension: ext)
            }
            return try Data(contentsOf: url)
        }
    }

    /// Converts to a NetworkResponse.
    ///
    /// - Parameter request: The original request.
    /// - Returns: A network response.
    /// - Throws: If body resolution fails.
    public func toNetworkResponse(for request: URLRequest) throws -> NetworkResponse {
        let data = try resolveBodyData()

        var responseHeaders = headers
        if responseHeaders["Content-Length"] == nil {
            responseHeaders["Content-Length"] = String(data.count)
        }

        return NetworkResponse(
            data: data,
            statusCode: statusCode,
            headers: responseHeaders,
            originalRequest: request,
            httpResponse: nil
        )
    }
}

// MARK: - Mock Error

/// Errors that can occur when working with mock responses.
public enum MockError: Error, Sendable {
    case stringEncodingFailed
    case resourceNotFound(name: String, extension: String)
    case noMatchingStub(request: URLRequest)
    case unexpectedRequest(URLRequest)
}

extension MockError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .stringEncodingFailed:
            return "Failed to encode string to data"
        case .resourceNotFound(let name, let ext):
            return "Resource not found: \(name).\(ext)"
        case .noMatchingStub(let request):
            return "No matching stub for request: \(request.url?.absoluteString ?? "unknown")"
        case .unexpectedRequest(let request):
            return "Unexpected request: \(request.url?.absoluteString ?? "unknown")"
        }
    }
}

// MARK: - AnyEncodable

/// Type-erased encodable wrapper.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeClosure = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

// MARK: - Response Builders

extension MockResponse {

    /// Creates a new response with an updated status code.
    public func withStatusCode(_ code: Int) -> MockResponse {
        MockResponse(
            statusCode: code,
            headers: headers,
            body: body,
            timing: timing,
            error: error
        )
    }

    /// Creates a new response with additional headers.
    public func withHeaders(_ additionalHeaders: [String: String]) -> MockResponse {
        var mergedHeaders = headers
        for (key, value) in additionalHeaders {
            mergedHeaders[key] = value
        }
        return MockResponse(
            statusCode: statusCode,
            headers: mergedHeaders,
            body: body,
            timing: timing,
            error: error
        )
    }

    /// Creates a new response with specified timing.
    public func withTiming(_ newTiming: Timing) -> MockResponse {
        MockResponse(
            statusCode: statusCode,
            headers: headers,
            body: body,
            timing: newTiming,
            error: error
        )
    }

    /// Creates a new response with a delay.
    public func withDelay(_ seconds: TimeInterval) -> MockResponse {
        withTiming(Timing(delay: seconds))
    }
}
