import Foundation
import os.log

/// An interceptor that logs HTTP request and response details.
///
/// Useful during development for debugging network calls. Logs method, URL,
/// status codes, and timing information.
///
/// ```swift
/// let client = NetworkClient(
///     baseURL: "https://api.example.com",
///     interceptors: [LoggingInterceptor()]
/// )
/// ```
public final class LoggingInterceptor: NetworkInterceptor, @unchecked Sendable {

    /// The log level for output.
    public enum LogLevel: Sendable {
        /// Logs only basic info (method, URL, status).
        case basic
        /// Logs headers in addition to basic info.
        case headers
        /// Logs everything including request/response bodies.
        case verbose
    }

    // MARK: - Properties

    private let level: LogLevel
    private let logger: Logger

    // MARK: - Initialization

    /// Creates a new logging interceptor.
    ///
    /// - Parameters:
    ///   - level: The detail level for logs. Defaults to `.basic`.
    ///   - subsystem: The logging subsystem. Defaults to the bundle identifier.
    ///   - category: The logging category. Defaults to "Network".
    public init(
        level: LogLevel = .basic,
        subsystem: String = Bundle.main.bundleIdentifier ?? "SwiftNetwork",
        category: String = "Network"
    ) {
        self.level = level
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - NetworkInterceptor

    public func intercept(request: URLRequest) async throws -> URLRequest {
        let method = request.httpMethod ?? "UNKNOWN"
        let url = request.url?.absoluteString ?? "nil"
        logger.info("→ \(method) \(url)")

        if level == .headers || level == .verbose {
            if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
                for (key, value) in headers {
                    logger.debug("  → \(key): \(value)")
                }
            }
        }

        if level == .verbose, let body = request.httpBody {
            let bodyString = String(data: body, encoding: .utf8) ?? "\(body.count) bytes"
            logger.debug("  → Body: \(bodyString)")
        }

        return request
    }

    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        let url = response.originalRequest?.url?.absoluteString ?? "nil"
        let status = response.statusCode
        let size = response.data.count

        logger.info("← \(status) \(url) (\(size) bytes)")

        if level == .headers || level == .verbose {
            for (key, value) in response.headers {
                logger.debug("  ← \(key): \(value)")
            }
        }

        if level == .verbose, let text = response.text {
            let preview = String(text.prefix(500))
            logger.debug("  ← Body: \(preview)")
        }

        return response
    }
}
