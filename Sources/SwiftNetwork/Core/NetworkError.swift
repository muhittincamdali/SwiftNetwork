import Foundation

/// Represents all possible errors that can occur during network operations.
///
/// Each case provides specific context about what went wrong, making error handling
/// straightforward and exhaustive.
///
/// ```swift
/// do {
///     let user: User = try await client.request(endpoint)
/// } catch let error as NetworkError {
///     switch error {
///     case .httpError(let code, _):
///         print("Server returned \(code)")
///     default:
///         print(error.localizedDescription)
///     }
/// }
/// ```
public enum NetworkError: Error, Sendable, Equatable {

    /// The URL could not be constructed from the base URL and endpoint path.
    case invalidURL

    /// The server returned a non-success HTTP status code.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code returned by the server.
    ///   - data: The raw response body, if available.
    case httpError(statusCode: Int, data: Data?)

    /// The response data could not be decoded into the expected type.
    ///
    /// - Parameter error: The underlying decoding error.
    case decodingFailed(Error)

    /// The server returned an empty response body when data was expected.
    case noData

    /// The request timed out before receiving a response.
    case timeout

    /// No network connection is available.
    case noConnection

    /// SSL certificate pinning validation failed.
    case certificatePinningFailed

    /// The request was explicitly cancelled.
    case cancelled

    /// The request failed after exhausting all retry attempts.
    ///
    /// - Parameter lastError: The error from the final attempt.
    case retryExhausted(Error)

    /// An unexpected error occurred.
    ///
    /// - Parameter error: The underlying system error.
    case unknown(Error)

    // MARK: - Equatable

    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.httpError(let lCode, let lData), .httpError(let rCode, let rData)):
            return lCode == rCode && lData == rData
        case (.noData, .noData): return true
        case (.timeout, .timeout): return true
        case (.noConnection, .noConnection): return true
        case (.certificatePinningFailed, .certificatePinningFailed): return true
        case (.cancelled, .cancelled): return true
        default: return false
        }
    }
}

// MARK: - LocalizedError

extension NetworkError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is invalid."
        case .httpError(let statusCode, _):
            return "HTTP error with status code \(statusCode)."
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noData:
            return "No data received from the server."
        case .timeout:
            return "The request timed out."
        case .noConnection:
            return "No internet connection available."
        case .certificatePinningFailed:
            return "Certificate pinning validation failed."
        case .cancelled:
            return "The request was cancelled."
        case .retryExhausted(let error):
            return "All retry attempts failed. Last error: \(error.localizedDescription)"
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}
