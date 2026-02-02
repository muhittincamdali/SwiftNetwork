import Foundation

/// A fluent builder for constructing ``Endpoint`` instances step by step.
///
/// `RequestBuilder` provides a chainable API that reads naturally and reduces
/// the chance of misconfigured requests.
///
/// ```swift
/// let endpoint = RequestBuilder()
///     .path("/users")
///     .method(.get)
///     .header("Authorization", "Bearer \(token)")
///     .query("page", "1")
///     .query("limit", "25")
///     .timeout(15)
///     .build()
/// ```
public final class RequestBuilder: Sendable {

    // MARK: - Stored State

    private let _path: String
    private let _method: HTTPMethod
    private let _headers: [String: String]
    private let _body: Data?
    private let _queryItems: [URLQueryItem]
    private let _timeoutInterval: TimeInterval?
    private let _cachePolicy: URLRequest.CachePolicy?

    // MARK: - Initialization

    /// Creates an empty request builder.
    public init() {
        self._path = ""
        self._method = .get
        self._headers = [:]
        self._body = nil
        self._queryItems = []
        self._timeoutInterval = nil
        self._cachePolicy = nil
    }

    private init(
        path: String,
        method: HTTPMethod,
        headers: [String: String],
        body: Data?,
        queryItems: [URLQueryItem],
        timeoutInterval: TimeInterval?,
        cachePolicy: URLRequest.CachePolicy?
    ) {
        self._path = path
        self._method = method
        self._headers = headers
        self._body = body
        self._queryItems = queryItems
        self._timeoutInterval = timeoutInterval
        self._cachePolicy = cachePolicy
    }

    // MARK: - Builder Methods

    /// Sets the request path.
    ///
    /// - Parameter path: The relative endpoint path.
    /// - Returns: A new builder with the updated path.
    public func path(_ path: String) -> RequestBuilder {
        RequestBuilder(
            path: path, method: _method, headers: _headers,
            body: _body, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Sets the HTTP method.
    ///
    /// - Parameter method: The HTTP method to use.
    /// - Returns: A new builder with the updated method.
    public func method(_ method: HTTPMethod) -> RequestBuilder {
        RequestBuilder(
            path: _path, method: method, headers: _headers,
            body: _body, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Adds a single header to the request.
    ///
    /// - Parameters:
    ///   - key: The header field name.
    ///   - value: The header field value.
    /// - Returns: A new builder with the added header.
    public func header(_ key: String, _ value: String) -> RequestBuilder {
        var merged = _headers
        merged[key] = value
        return RequestBuilder(
            path: _path, method: _method, headers: merged,
            body: _body, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Adds multiple headers to the request.
    ///
    /// - Parameter headers: A dictionary of header key-value pairs.
    /// - Returns: A new builder with the added headers.
    public func headers(_ headers: [String: String]) -> RequestBuilder {
        var merged = _headers
        for (key, value) in headers {
            merged[key] = value
        }
        return RequestBuilder(
            path: _path, method: _method, headers: merged,
            body: _body, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Sets the request body from raw data.
    ///
    /// - Parameter data: The raw body data.
    /// - Returns: A new builder with the updated body.
    public func body(_ data: Data) -> RequestBuilder {
        RequestBuilder(
            path: _path, method: _method, headers: _headers,
            body: data, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Sets the request body by encoding an `Encodable` value to JSON.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - encoder: The JSON encoder to use. Defaults to a standard instance.
    /// - Returns: A new builder with the encoded body and `Content-Type` header.
    /// - Throws: Encoding errors if the value cannot be serialized.
    public func body<T: Encodable>(_ value: T, encoder: JSONEncoder = .init()) throws -> RequestBuilder {
        let data = try encoder.encode(value)
        return RequestBuilder(
            path: _path, method: _method,
            headers: _headers.merging(["Content-Type": "application/json"]) { _, new in new },
            body: data, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Adds a query parameter to the request URL.
    ///
    /// - Parameters:
    ///   - name: The query parameter name.
    ///   - value: The query parameter value.
    /// - Returns: A new builder with the added query item.
    public func query(_ name: String, _ value: String) -> RequestBuilder {
        var items = _queryItems
        items.append(URLQueryItem(name: name, value: value))
        return RequestBuilder(
            path: _path, method: _method, headers: _headers,
            body: _body, queryItems: items,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Adds multiple query parameters from a dictionary.
    ///
    /// - Parameter parameters: A dictionary of query key-value pairs.
    /// - Returns: A new builder with the added query items.
    public func queryItems(_ parameters: [String: String]) -> RequestBuilder {
        var items = _queryItems
        for (key, value) in parameters {
            items.append(URLQueryItem(name: key, value: value))
        }
        return RequestBuilder(
            path: _path, method: _method, headers: _headers,
            body: _body, queryItems: items,
            timeoutInterval: _timeoutInterval, cachePolicy: _cachePolicy
        )
    }

    /// Sets the timeout interval for the request.
    ///
    /// - Parameter seconds: The timeout in seconds.
    /// - Returns: A new builder with the updated timeout.
    public func timeout(_ seconds: TimeInterval) -> RequestBuilder {
        RequestBuilder(
            path: _path, method: _method, headers: _headers,
            body: _body, queryItems: _queryItems,
            timeoutInterval: seconds, cachePolicy: _cachePolicy
        )
    }

    /// Sets the cache policy for the request.
    ///
    /// - Parameter policy: The cache policy to apply.
    /// - Returns: A new builder with the updated cache policy.
    public func cachePolicy(_ policy: URLRequest.CachePolicy) -> RequestBuilder {
        RequestBuilder(
            path: _path, method: _method, headers: _headers,
            body: _body, queryItems: _queryItems,
            timeoutInterval: _timeoutInterval, cachePolicy: policy
        )
    }

    // MARK: - Build

    /// Constructs the final ``Endpoint`` from the builder state.
    ///
    /// - Returns: A configured `Endpoint` ready for use with ``NetworkClient``.
    public func build() -> Endpoint {
        Endpoint(
            path: _path,
            method: _method,
            headers: _headers,
            body: _body,
            queryItems: _queryItems,
            timeoutInterval: _timeoutInterval,
            cachePolicy: _cachePolicy
        )
    }
}
