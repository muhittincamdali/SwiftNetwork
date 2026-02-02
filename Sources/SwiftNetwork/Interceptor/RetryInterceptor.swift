import Foundation

/// An interceptor that retries failed requests with exponential backoff.
///
/// Automatically retries requests that fail with transient errors (timeouts,
/// server errors, connection issues) up to a configurable maximum number of attempts.
///
/// ```swift
/// let retry = RetryInterceptor(maxRetries: 3, baseDelay: 1.0, maxDelay: 30.0)
/// let client = NetworkClient(
///     baseURL: "https://api.example.com",
///     interceptors: [retry]
/// )
/// ```
public final class RetryInterceptor: NetworkInterceptor, @unchecked Sendable {

    // MARK: - Properties

    /// Maximum number of retry attempts.
    private let maxRetries: Int

    /// Base delay between retries in seconds.
    private let baseDelay: TimeInterval

    /// Maximum delay cap in seconds.
    private let maxDelay: TimeInterval

    /// Whether to add random jitter to the delay.
    private let jitterEnabled: Bool

    /// Status codes that trigger a retry.
    private let retryableStatusCodes: Set<Int>

    // MARK: - Initialization

    /// Creates a retry interceptor.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts. Defaults to 3.
    ///   - baseDelay: Initial delay in seconds. Defaults to 1.0.
    ///   - maxDelay: Maximum delay cap in seconds. Defaults to 30.0.
    ///   - jitterEnabled: Whether to apply random jitter. Defaults to `true`.
    ///   - retryableStatusCodes: HTTP status codes that should trigger retries.
    ///     Defaults to 408, 429, 500, 502, 503, 504.
    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        jitterEnabled: Bool = true,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterEnabled = jitterEnabled
        self.retryableStatusCodes = retryableStatusCodes
    }

    // MARK: - NetworkInterceptor

    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        guard retryableStatusCodes.contains(response.statusCode) else {
            return response
        }

        guard let request = response.originalRequest else {
            return response
        }

        var lastResponse = response

        for attempt in 1...maxRetries {
            let delay = calculateDelay(attempt: attempt)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            let session = URLSession.shared
            let (data, urlResponse) = try await session.data(for: request)

            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                return lastResponse
            }

            let retryResponse = NetworkResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String] ?? [:],
                originalRequest: request,
                httpResponse: httpResponse
            )

            if !retryableStatusCodes.contains(retryResponse.statusCode) {
                return retryResponse
            }

            lastResponse = retryResponse
        }

        return lastResponse
    }

    // MARK: - Private

    private func calculateDelay(attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt - 1))
        let capped = min(exponential, maxDelay)

        if jitterEnabled {
            let jitter = Double.random(in: 0...(capped * 0.25))
            return capped + jitter
        }

        return capped
    }
}
