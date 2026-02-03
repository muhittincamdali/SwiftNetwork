import Foundation
import os.log

/// A configurable logger for network operations.
///
/// `NetworkLogger` provides structured logging with different verbosity levels
/// and output destinations for debugging network requests.
///
/// ```swift
/// let logger = NetworkLogger(level: .debug)
///
/// // Automatic logging via interceptor
/// let client = NetworkClient(
///     baseURL: url,
///     interceptors: [logger.interceptor]
/// )
///
/// // Manual logging
/// logger.log(request: request)
/// logger.log(response: response, duration: 0.5)
/// ```
public final class NetworkLogger: @unchecked Sendable {

    // MARK: - Types

    /// Log verbosity level.
    public enum Level: Int, Comparable, Sendable {
        case none = 0
        case error = 1
        case warning = 2
        case info = 3
        case debug = 4
        case verbose = 5

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Log output destination.
    public enum Destination: Sendable {
        case console
        case osLog(OSLog)
        case file(URL)
        case custom(@Sendable (String, Level) -> Void)
    }

    /// What components to include in logs.
    public struct Components: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let method = Components(rawValue: 1 << 0)
        public static let url = Components(rawValue: 1 << 1)
        public static let headers = Components(rawValue: 1 << 2)
        public static let body = Components(rawValue: 1 << 3)
        public static let statusCode = Components(rawValue: 1 << 4)
        public static let duration = Components(rawValue: 1 << 5)
        public static let size = Components(rawValue: 1 << 6)
        public static let timestamp = Components(rawValue: 1 << 7)

        public static let minimal: Components = [.method, .url, .statusCode]
        public static let standard: Components = [.method, .url, .statusCode, .duration, .size]
        public static let verbose: Components = [.method, .url, .headers, .body, .statusCode, .duration, .size, .timestamp]
        public static let all: Components = [.method, .url, .headers, .body, .statusCode, .duration, .size, .timestamp]
    }

    // MARK: - Properties

    /// The minimum level to log.
    public var level: Level

    /// Log output destination.
    public let destination: Destination

    /// Components to include in logs.
    public var components: Components

    /// Maximum body size to log (in bytes).
    public var maxBodySize: Int

    /// Headers to redact from logs.
    public var redactedHeaders: Set<String>

    /// Whether to pretty-print JSON bodies.
    public var prettyPrintJSON: Bool

    /// Custom log formatter.
    private let formatter: (@Sendable (String, Level) -> String)?

    /// File handle for file logging.
    private var fileHandle: FileHandle?

    /// Lock for thread safety.
    private let lock = NSLock()

    /// Date formatter for timestamps.
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Initialization

    /// Creates a network logger.
    ///
    /// - Parameters:
    ///   - level: Minimum log level. Defaults to `.info`.
    ///   - destination: Log destination. Defaults to console.
    ///   - components: Components to include. Defaults to standard.
    ///   - maxBodySize: Max body size to log. Defaults to 10KB.
    ///   - redactedHeaders: Headers to redact. Defaults to Authorization.
    ///   - prettyPrintJSON: Pretty-print JSON. Defaults to true.
    ///   - formatter: Custom formatter.
    public init(
        level: Level = .info,
        destination: Destination = .console,
        components: Components = .standard,
        maxBodySize: Int = 10 * 1024,
        redactedHeaders: Set<String> = ["Authorization", "Cookie", "Set-Cookie"],
        prettyPrintJSON: Bool = true,
        formatter: (@Sendable (String, Level) -> String)? = nil
    ) {
        self.level = level
        self.destination = destination
        self.components = components
        self.maxBodySize = maxBodySize
        self.redactedHeaders = redactedHeaders
        self.prettyPrintJSON = prettyPrintJSON
        self.formatter = formatter

        setupDestination()
    }

    deinit {
        fileHandle?.closeFile()
    }

    private func setupDestination() {
        if case .file(let url) = destination {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            fileHandle = FileHandle(forWritingAtPath: url.path)
            fileHandle?.seekToEndOfFile()
        }
    }

    // MARK: - Logging Methods

    /// Logs a request.
    ///
    /// - Parameter request: The URL request.
    public func log(request: URLRequest) {
        guard level >= .info else { return }

        var lines: [String] = []

        if components.contains(.timestamp) {
            lines.append("[\(dateFormatter.string(from: Date()))]")
        }

        lines.append("➡️ REQUEST")

        if components.contains(.method), let method = request.httpMethod {
            lines.append("Method: \(method)")
        }

        if components.contains(.url), let url = request.url {
            lines.append("URL: \(url.absoluteString)")
        }

        if components.contains(.headers), let headers = request.allHTTPHeaderFields {
            lines.append("Headers:")
            for (key, value) in headers {
                let displayValue = redactedHeaders.contains(key) ? "[REDACTED]" : value
                lines.append("  \(key): \(displayValue)")
            }
        }

        if components.contains(.body), let body = request.httpBody {
            lines.append("Body: \(formatBody(body))")
        }

        output(lines.joined(separator: "\n"), level: .info)
    }

    /// Logs a response.
    ///
    /// - Parameters:
    ///   - response: The network response.
    ///   - duration: Request duration in seconds.
    public func log(response: NetworkResponse, duration: TimeInterval? = nil) {
        guard level >= .info else { return }

        var lines: [String] = []

        if components.contains(.timestamp) {
            lines.append("[\(dateFormatter.string(from: Date()))]")
        }

        let emoji = (200...299).contains(response.statusCode) ? "✅" : "❌"
        lines.append("\(emoji) RESPONSE")

        if components.contains(.statusCode) {
            lines.append("Status: \(response.statusCode)")
        }

        if components.contains(.duration), let duration = duration {
            lines.append(String(format: "Duration: %.3fs", duration))
        }

        if components.contains(.size) {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: Int64(response.data.count), countStyle: .file))")
        }

        if components.contains(.headers) {
            lines.append("Headers:")
            for (key, value) in response.headers {
                let displayValue = redactedHeaders.contains(key) ? "[REDACTED]" : value
                lines.append("  \(key): \(displayValue)")
            }
        }

        if components.contains(.body) && !response.data.isEmpty {
            lines.append("Body: \(formatBody(response.data))")
        }

        output(lines.joined(separator: "\n"), level: .info)
    }

    /// Logs an error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - request: The associated request.
    public func log(error: Error, for request: URLRequest? = nil) {
        guard level >= .error else { return }

        var lines: [String] = []

        lines.append("❌ ERROR")

        if let request = request, let url = request.url {
            lines.append("URL: \(url.absoluteString)")
        }

        lines.append("Error: \(error.localizedDescription)")

        if let networkError = error as? NetworkError {
            lines.append("Type: \(networkError)")
        }

        output(lines.joined(separator: "\n"), level: .error)
    }

    /// Logs a debug message.
    ///
    /// - Parameter message: The message.
    public func debug(_ message: String) {
        guard level >= .debug else { return }
        output("🔍 DEBUG: \(message)", level: .debug)
    }

    /// Logs a warning message.
    ///
    /// - Parameter message: The message.
    public func warning(_ message: String) {
        guard level >= .warning else { return }
        output("⚠️ WARNING: \(message)", level: .warning)
    }

    // MARK: - Interceptor

    /// Creates a logging interceptor.
    public var interceptor: NetworkInterceptor {
        LoggingNetworkInterceptor(logger: self)
    }

    // MARK: - Private Methods

    private func formatBody(_ data: Data) -> String {
        if data.count > maxBodySize {
            return "[Body too large: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))]"
        }

        // Try to parse as JSON
        if let json = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(
               withJSONObject: json,
               options: prettyPrintJSON ? [.prettyPrinted, .sortedKeys] : []
           ),
           let string = String(data: formatted, encoding: .utf8) {
            return string
        }

        // Fall back to string
        if let string = String(data: data, encoding: .utf8) {
            return string
        }

        return "[Binary data: \(data.count) bytes]"
    }

    private func output(_ message: String, level: Level) {
        let formatted = formatter?(message, level) ?? message

        lock.withLock {
            switch destination {
            case .console:
                print(formatted)

            case .osLog(let log):
                let type: OSLogType = switch level {
                case .error: .error
                case .warning: .fault
                case .debug: .debug
                default: .info
                }
                os_log("%{public}@", log: log, type: type, formatted)

            case .file:
                if let data = (formatted + "\n").data(using: .utf8) {
                    fileHandle?.write(data)
                }

            case .custom(let handler):
                handler(formatted, level)
            }
        }
    }
}

// MARK: - Logging Interceptor

/// Internal interceptor for automatic logging.
private struct LoggingNetworkInterceptor: NetworkInterceptor {

    let logger: NetworkLogger
    private let startTimes = NSMapTable<NSURLRequest, NSDate>.strongToStrongObjects()

    init(logger: NetworkLogger) {
        self.logger = logger
    }

    func intercept(request: URLRequest) async throws -> URLRequest {
        logger.log(request: request)
        return request
    }

    func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        logger.log(response: response)
        return response
    }
}

// MARK: - Convenience Extensions

extension NetworkLogger {

    /// A shared default logger.
    public static let `default` = NetworkLogger()

    /// A verbose logger for debugging.
    public static let verbose = NetworkLogger(
        level: .verbose,
        components: .verbose
    )

    /// A minimal logger for production.
    public static let minimal = NetworkLogger(
        level: .warning,
        components: .minimal
    )
}
