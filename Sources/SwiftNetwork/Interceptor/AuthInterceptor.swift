import Foundation

/// An interceptor that automatically injects authorization tokens and handles token refresh.
///
/// `AuthInterceptor` adds a Bearer token to every outgoing request. When a 401 response
/// is received and a `tokenRefresher` is provided, it automatically refreshes the token
/// and signals for the request to be retried.
///
/// ```swift
/// let auth = AuthInterceptor(
///     tokenProvider: { await TokenStore.shared.accessToken },
///     tokenRefresher: {
///         let newToken = try await AuthService.refresh()
///         await TokenStore.shared.update(newToken)
///     }
/// )
/// ```
public final class AuthInterceptor: NetworkInterceptor, @unchecked Sendable {

    // MARK: - Properties

    /// Closure that provides the current access token.
    private let tokenProvider: @Sendable () async -> String?

    /// Optional closure that refreshes an expired token.
    private let tokenRefresher: (@Sendable () async throws -> Void)?

    /// The header field name for the authorization token.
    private let headerField: String

    /// The token prefix (e.g., "Bearer").
    private let tokenPrefix: String

    /// Flag to prevent infinite refresh loops.
    private var isRefreshing = false

    /// Lock for thread-safe access to isRefreshing.
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new auth interceptor.
    ///
    /// - Parameters:
    ///   - tokenProvider: Async closure returning the current token.
    ///   - tokenRefresher: Optional async closure to refresh an expired token.
    ///   - headerField: The header name. Defaults to "Authorization".
    ///   - tokenPrefix: The prefix before the token. Defaults to "Bearer".
    public init(
        tokenProvider: @escaping @Sendable () async -> String?,
        tokenRefresher: (@Sendable () async throws -> Void)? = nil,
        headerField: String = "Authorization",
        tokenPrefix: String = "Bearer"
    ) {
        self.tokenProvider = tokenProvider
        self.tokenRefresher = tokenRefresher
        self.headerField = headerField
        self.tokenPrefix = tokenPrefix
    }

    // MARK: - NetworkInterceptor

    public func intercept(request: URLRequest) async throws -> URLRequest {
        var modified = request

        if let token = await tokenProvider() {
            let value = tokenPrefix.isEmpty ? token : "\(tokenPrefix) \(token)"
            modified.setValue(value, forHTTPHeaderField: headerField)
        }

        return modified
    }

    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        guard response.statusCode == 401 else {
            return response
        }

        guard let refresher = tokenRefresher else {
            return response
        }

        lock.lock()
        guard !isRefreshing else {
            lock.unlock()
            return response
        }
        isRefreshing = true
        lock.unlock()

        defer {
            lock.lock()
            isRefreshing = false
            lock.unlock()
        }

        try await refresher()

        // Return the 401 response; the retry interceptor or client handles replay.
        return response
    }
}
