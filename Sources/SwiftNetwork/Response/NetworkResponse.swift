import Foundation

/// Wraps the raw HTTP response including data, status code, and headers.
///
/// `NetworkResponse` provides access to all aspects of the server response,
/// useful when you need more than just the decoded body.
///
/// ```swift
/// let response = try await client.rawRequest(endpoint)
/// print("Status: \(response.statusCode)")
/// print("Content-Type: \(response.headers["Content-Type"] ?? "unknown")")
/// ```
public struct NetworkResponse: Sendable {

    /// The raw response body data.
    public let data: Data

    /// The HTTP status code returned by the server.
    public let statusCode: Int

    /// The response headers as a string dictionary.
    public let headers: [String: String]

    /// The original request that produced this response.
    public let originalRequest: URLRequest?

    /// The underlying `HTTPURLResponse` object.
    public let httpResponse: HTTPURLResponse?

    /// Creates a new network response.
    ///
    /// - Parameters:
    ///   - data: The response body data.
    ///   - statusCode: The HTTP status code.
    ///   - headers: Response headers.
    ///   - originalRequest: The original URL request.
    ///   - httpResponse: The raw HTTP response.
    public init(
        data: Data,
        statusCode: Int,
        headers: [String: String] = [:],
        originalRequest: URLRequest? = nil,
        httpResponse: HTTPURLResponse? = nil
    ) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.originalRequest = originalRequest
        self.httpResponse = httpResponse
    }

    /// Whether the status code indicates success (2xx).
    public var isSuccess: Bool {
        (200...299).contains(statusCode)
    }

    /// Whether the status code indicates a client error (4xx).
    public var isClientError: Bool {
        (400...499).contains(statusCode)
    }

    /// Whether the status code indicates a server error (5xx).
    public var isServerError: Bool {
        (500...599).contains(statusCode)
    }

    /// The response body decoded as a UTF-8 string, if possible.
    public var text: String? {
        String(data: data, encoding: .utf8)
    }

    /// Decodes the response data into the specified `Decodable` type.
    ///
    /// - Parameters:
    ///   - type: The type to decode into.
    ///   - decoder: The JSON decoder to use. Defaults to a standard instance.
    /// - Returns: The decoded object.
    /// - Throws: ``NetworkError/decodingFailed(_:)`` if decoding fails.
    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = .init()) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    /// Returns the value of a specific response header (case-insensitive lookup).
    ///
    /// - Parameter name: The header field name.
    /// - Returns: The header value, or `nil` if not present.
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }
}
