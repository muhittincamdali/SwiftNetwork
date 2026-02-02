import Foundation

/// A protocol for intercepting network requests and responses.
///
/// Interceptors form a chain that processes each request before it is sent
/// and each response after it is received. Common uses include authentication,
/// logging, retry logic, and caching.
///
/// ```swift
/// struct MyInterceptor: NetworkInterceptor {
///     func intercept(request: URLRequest) async throws -> URLRequest {
///         var modified = request
///         modified.setValue("custom-value", forHTTPHeaderField: "X-Custom")
///         return modified
///     }
///
///     func intercept(response: NetworkResponse) async throws -> NetworkResponse {
///         return response
///     }
/// }
/// ```
public protocol NetworkInterceptor: Sendable {

    /// Intercepts and optionally modifies an outgoing request.
    ///
    /// Called before the request is sent to the server. Interceptors are invoked
    /// in the order they were registered.
    ///
    /// - Parameter request: The current URL request.
    /// - Returns: The (possibly modified) URL request.
    /// - Throws: To abort the request chain with an error.
    func intercept(request: URLRequest) async throws -> URLRequest

    /// Intercepts and optionally modifies an incoming response.
    ///
    /// Called after the response is received. Interceptors are invoked
    /// in reverse registration order.
    ///
    /// - Parameter response: The network response.
    /// - Returns: The (possibly modified) network response.
    /// - Throws: To signal a response processing error.
    func intercept(response: NetworkResponse) async throws -> NetworkResponse
}

// MARK: - Default Implementations

extension NetworkInterceptor {

    /// Default implementation that passes the request through unchanged.
    public func intercept(request: URLRequest) async throws -> URLRequest {
        request
    }

    /// Default implementation that passes the response through unchanged.
    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        response
    }
}
