import Foundation

/// Describes an HTTP endpoint with all the information needed to construct a request.
///
/// Use `Endpoint` directly for simple requests, or use ``RequestBuilder`` for a fluent API.
///
/// ```swift
/// let endpoint = Endpoint(
///     path: "/users",
///     method: .get,
///     headers: ["Accept": "application/json"],
///     queryItems: [URLQueryItem(name: "page", value: "1")]
/// )
/// ```
public struct Endpoint: Sendable, Hashable {

    /// The relative path appended to the base URL.
    public let path: String

    /// The HTTP method for this request.
    public let method: HTTPMethod

    /// Additional HTTP headers to include in the request.
    public let headers: [String: String]

    /// The raw body data to send with the request.
    public let body: Data?

    /// Query parameters appended to the URL.
    public let queryItems: [URLQueryItem]

    /// The timeout interval for this specific request. If `nil`, the client default is used.
    public let timeoutInterval: TimeInterval?

    /// The cache policy for this request.
    public let cachePolicy: URLRequest.CachePolicy?

    /// Creates a new endpoint.
    ///
    /// - Parameters:
    ///   - path: The relative path for the endpoint.
    ///   - method: The HTTP method. Defaults to `.get`.
    ///   - headers: Additional headers. Defaults to empty.
    ///   - body: The request body data. Defaults to `nil`.
    ///   - queryItems: URL query parameters. Defaults to empty.
    ///   - timeoutInterval: Optional timeout override.
    ///   - cachePolicy: Optional cache policy override.
    public init(
        path: String,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        timeoutInterval: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) {
        self.path = path
        self.method = method
        self.headers = headers
        self.body = body
        self.queryItems = queryItems
        self.timeoutInterval = timeoutInterval
        self.cachePolicy = cachePolicy
    }

    /// Creates a URL relative to the given base URL, including query items.
    ///
    /// - Parameter baseURL: The base URL string to resolve against.
    /// - Returns: A fully resolved URL, or `nil` if construction fails.
    public func url(relativeTo baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL + path) else {
            return nil
        }
        if !queryItems.isEmpty {
            let existing = components.queryItems ?? []
            components.queryItems = existing + queryItems
        }
        return components.url
    }

    /// Builds a `URLRequest` from this endpoint relative to a base URL.
    ///
    /// - Parameter baseURL: The base URL string.
    /// - Returns: A configured `URLRequest`.
    /// - Throws: ``NetworkError/invalidURL`` if the URL cannot be constructed.
    public func urlRequest(baseURL: String) throws -> URLRequest {
        guard let url = url(relativeTo: baseURL) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let timeout = timeoutInterval {
            request.timeoutInterval = timeout
        }
        if let cache = cachePolicy {
            request.cachePolicy = cache
        }

        return request
    }
}

// MARK: - Convenience Initializers

extension Endpoint {

    /// Creates a GET endpoint with query items.
    public static func get(_ path: String, query: [String: String] = [:], headers: [String: String] = [:]) -> Endpoint {
        Endpoint(
            path: path,
            method: .get,
            headers: headers,
            queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) }
        )
    }

    /// Creates a POST endpoint with an encodable body.
    public static func post<T: Encodable>(_ path: String, body: T, encoder: JSONEncoder = .init(), headers: [String: String] = [:]) throws -> Endpoint {
        var mergedHeaders = headers
        mergedHeaders["Content-Type"] = mergedHeaders["Content-Type"] ?? "application/json"
        return Endpoint(
            path: path,
            method: .post,
            headers: mergedHeaders,
            body: try encoder.encode(body)
        )
    }

    /// Creates a DELETE endpoint.
    public static func delete(_ path: String, headers: [String: String] = [:]) -> Endpoint {
        Endpoint(path: path, method: .delete, headers: headers)
    }
}
