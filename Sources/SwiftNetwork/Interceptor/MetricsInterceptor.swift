import Foundation

/// An interceptor that collects metrics about network requests.
///
/// `MetricsInterceptor` tracks timing, size, and outcome information
/// for all requests passing through it, useful for monitoring and debugging.
///
/// ```swift
/// let metrics = MetricsInterceptor()
/// let client = NetworkClient(
///     baseURL: url,
///     interceptors: [metrics]
/// )
///
/// // After making requests
/// let stats = await metrics.statistics()
/// print("Average response time: \(stats.averageResponseTime)ms")
/// ```
public final class MetricsInterceptor: NetworkInterceptor, @unchecked Sendable {

    // MARK: - Types

    /// A single request metric record.
    public struct RequestMetric: Sendable {
        /// Unique identifier for this request.
        public let requestId: String

        /// The request URL.
        public let url: URL?

        /// The HTTP method.
        public let method: String?

        /// When the request started.
        public let startTime: Date

        /// When the response was received.
        public let endTime: Date?

        /// The response status code.
        public let statusCode: Int?

        /// Size of the request body in bytes.
        public let requestSize: Int

        /// Size of the response body in bytes.
        public let responseSize: Int?

        /// Whether the request succeeded.
        public let success: Bool

        /// Error message if the request failed.
        public let errorMessage: String?

        /// Total duration in milliseconds.
        public var duration: TimeInterval? {
            guard let end = endTime else { return nil }
            return end.timeIntervalSince(startTime) * 1000
        }

        /// Custom tags for categorization.
        public let tags: [String: String]
    }

    /// Aggregated statistics for all tracked requests.
    public struct Statistics: Sendable {
        /// Total number of requests tracked.
        public let totalRequests: Int

        /// Number of successful requests.
        public let successfulRequests: Int

        /// Number of failed requests.
        public let failedRequests: Int

        /// Success rate as a percentage.
        public var successRate: Double {
            guard totalRequests > 0 else { return 0 }
            return Double(successfulRequests) / Double(totalRequests) * 100
        }

        /// Average response time in milliseconds.
        public let averageResponseTime: Double

        /// Minimum response time in milliseconds.
        public let minResponseTime: Double?

        /// Maximum response time in milliseconds.
        public let maxResponseTime: Double?

        /// Median response time in milliseconds.
        public let medianResponseTime: Double?

        /// 95th percentile response time.
        public let p95ResponseTime: Double?

        /// 99th percentile response time.
        public let p99ResponseTime: Double?

        /// Total bytes sent.
        public let totalBytesSent: Int

        /// Total bytes received.
        public let totalBytesReceived: Int

        /// Breakdown by status code.
        public let statusCodeCounts: [Int: Int]

        /// Breakdown by HTTP method.
        public let methodCounts: [String: Int]

        /// Breakdown by host.
        public let hostCounts: [String: Int]

        /// Time period covered by these statistics.
        public let timePeriod: DateInterval?
    }

    /// Metric event for callbacks.
    public enum MetricEvent: Sendable {
        case requestStarted(RequestMetric)
        case requestCompleted(RequestMetric)
        case requestFailed(RequestMetric)
    }

    // MARK: - Properties

    /// Maximum number of metrics to retain.
    public let maxRetainedMetrics: Int

    /// Whether to include request/response body sizes.
    public let trackBodySizes: Bool

    /// Custom tag generator for requests.
    private let tagGenerator: (@Sendable (URLRequest) -> [String: String])?

    /// Callback for metric events.
    private let eventHandler: (@Sendable (MetricEvent) -> Void)?

    private var metrics: [RequestMetric] = []
    private var pendingRequests: [String: RequestMetric] = [:]
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a metrics interceptor.
    ///
    /// - Parameters:
    ///   - maxRetainedMetrics: Maximum metrics to keep. Defaults to 1000.
    ///   - trackBodySizes: Whether to track body sizes. Defaults to true.
    ///   - tagGenerator: Optional custom tag generator.
    ///   - eventHandler: Optional callback for metric events.
    public init(
        maxRetainedMetrics: Int = 1000,
        trackBodySizes: Bool = true,
        tagGenerator: (@Sendable (URLRequest) -> [String: String])? = nil,
        eventHandler: (@Sendable (MetricEvent) -> Void)? = nil
    ) {
        self.maxRetainedMetrics = maxRetainedMetrics
        self.trackBodySizes = trackBodySizes
        self.tagGenerator = tagGenerator
        self.eventHandler = eventHandler
    }

    // MARK: - NetworkInterceptor

    public func intercept(request: URLRequest) async throws -> URLRequest {
        let requestId = UUID().uuidString
        let tags = tagGenerator?(request) ?? [:]

        let metric = RequestMetric(
            requestId: requestId,
            url: request.url,
            method: request.httpMethod,
            startTime: Date(),
            endTime: nil,
            statusCode: nil,
            requestSize: trackBodySizes ? (request.httpBody?.count ?? 0) : 0,
            responseSize: nil,
            success: false,
            errorMessage: nil,
            tags: tags
        )

        lock.withLock {
            pendingRequests[requestId] = metric
        }

        eventHandler?(.requestStarted(metric))

        // Attach request ID to the request
        var modified = request
        modified.setValue(requestId, forHTTPHeaderField: "X-SwiftNetwork-RequestId")
        return modified
    }

    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        guard let requestId = response.originalRequest?.value(forHTTPHeaderField: "X-SwiftNetwork-RequestId") else {
            return response
        }

        lock.withLock {
            guard let pending = pendingRequests[requestId] else { return }
            pendingRequests[requestId] = nil

            let completed = RequestMetric(
                requestId: pending.requestId,
                url: pending.url,
                method: pending.method,
                startTime: pending.startTime,
                endTime: Date(),
                statusCode: response.statusCode,
                requestSize: pending.requestSize,
                responseSize: trackBodySizes ? response.data.count : nil,
                success: (200...299).contains(response.statusCode),
                errorMessage: nil,
                tags: pending.tags
            )

            addMetric(completed)
            eventHandler?(.requestCompleted(completed))
        }

        return response
    }

    // MARK: - Metric Recording

    /// Records a failed request.
    ///
    /// - Parameters:
    ///   - requestId: The request ID.
    ///   - error: The error that occurred.
    public func recordFailure(requestId: String, error: Error) {
        lock.withLock {
            guard let pending = pendingRequests[requestId] else { return }
            pendingRequests[requestId] = nil

            let failed = RequestMetric(
                requestId: pending.requestId,
                url: pending.url,
                method: pending.method,
                startTime: pending.startTime,
                endTime: Date(),
                statusCode: nil,
                requestSize: pending.requestSize,
                responseSize: nil,
                success: false,
                errorMessage: error.localizedDescription,
                tags: pending.tags
            )

            addMetric(failed)
            eventHandler?(.requestFailed(failed))
        }
    }

    private func addMetric(_ metric: RequestMetric) {
        metrics.append(metric)

        // Trim if over limit
        if metrics.count > maxRetainedMetrics {
            let excess = metrics.count - maxRetainedMetrics
            metrics.removeFirst(excess)
        }
    }

    // MARK: - Statistics

    /// Gets all recorded metrics.
    ///
    /// - Returns: An array of all metrics.
    public func allMetrics() -> [RequestMetric] {
        lock.withLock { metrics }
    }

    /// Gets metrics filtered by predicate.
    ///
    /// - Parameter predicate: The filter predicate.
    /// - Returns: Filtered metrics.
    public func metrics(where predicate: (RequestMetric) -> Bool) -> [RequestMetric] {
        lock.withLock { metrics.filter(predicate) }
    }

    /// Gets metrics for a specific time period.
    ///
    /// - Parameter interval: The date interval.
    /// - Returns: Metrics within the interval.
    public func metrics(in interval: DateInterval) -> [RequestMetric] {
        metrics { metric in
            interval.contains(metric.startTime)
        }
    }

    /// Calculates aggregate statistics.
    ///
    /// - Parameter filter: Optional filter predicate.
    /// - Returns: Aggregate statistics.
    public func statistics(where filter: ((RequestMetric) -> Bool)? = nil) -> Statistics {
        lock.withLock {
            let filtered = filter != nil ? metrics.filter(filter!) : metrics

            guard !filtered.isEmpty else {
                return Statistics(
                    totalRequests: 0,
                    successfulRequests: 0,
                    failedRequests: 0,
                    averageResponseTime: 0,
                    minResponseTime: nil,
                    maxResponseTime: nil,
                    medianResponseTime: nil,
                    p95ResponseTime: nil,
                    p99ResponseTime: nil,
                    totalBytesSent: 0,
                    totalBytesReceived: 0,
                    statusCodeCounts: [:],
                    methodCounts: [:],
                    hostCounts: [:],
                    timePeriod: nil
                )
            }

            let successful = filtered.filter { $0.success }
            let failed = filtered.filter { !$0.success }
            let durations = filtered.compactMap { $0.duration }.sorted()

            // Calculate percentiles
            let medianIndex = durations.count / 2
            let p95Index = Int(Double(durations.count) * 0.95)
            let p99Index = Int(Double(durations.count) * 0.99)

            // Count by status code
            var statusCodes: [Int: Int] = [:]
            for metric in filtered {
                if let code = metric.statusCode {
                    statusCodes[code, default: 0] += 1
                }
            }

            // Count by method
            var methods: [String: Int] = [:]
            for metric in filtered {
                if let method = metric.method {
                    methods[method, default: 0] += 1
                }
            }

            // Count by host
            var hosts: [String: Int] = [:]
            for metric in filtered {
                if let host = metric.url?.host {
                    hosts[host, default: 0] += 1
                }
            }

            // Time period
            let startDates = filtered.map { $0.startTime }
            let timePeriod: DateInterval?
            if let earliest = startDates.min(), let latest = startDates.max() {
                timePeriod = DateInterval(start: earliest, end: latest)
            } else {
                timePeriod = nil
            }

            return Statistics(
                totalRequests: filtered.count,
                successfulRequests: successful.count,
                failedRequests: failed.count,
                averageResponseTime: durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count),
                minResponseTime: durations.first,
                maxResponseTime: durations.last,
                medianResponseTime: durations.isEmpty ? nil : durations[medianIndex],
                p95ResponseTime: durations.isEmpty ? nil : durations[min(p95Index, durations.count - 1)],
                p99ResponseTime: durations.isEmpty ? nil : durations[min(p99Index, durations.count - 1)],
                totalBytesSent: filtered.reduce(0) { $0 + $1.requestSize },
                totalBytesReceived: filtered.reduce(0) { $0 + ($1.responseSize ?? 0) },
                statusCodeCounts: statusCodes,
                methodCounts: methods,
                hostCounts: hosts,
                timePeriod: timePeriod
            )
        }
    }

    /// Clears all recorded metrics.
    public func clearMetrics() {
        lock.withLock {
            metrics.removeAll()
            pendingRequests.removeAll()
        }
    }

    /// Gets the number of pending requests.
    public var pendingRequestCount: Int {
        lock.withLock { pendingRequests.count }
    }

    /// Gets the number of recorded metrics.
    public var recordedMetricsCount: Int {
        lock.withLock { metrics.count }
    }
}

// MARK: - Statistics Extensions

extension MetricsInterceptor.Statistics: CustomStringConvertible {

    public var description: String {
        """
        Network Statistics:
        - Total Requests: \(totalRequests)
        - Success Rate: \(String(format: "%.1f%%", successRate))
        - Average Response Time: \(String(format: "%.2fms", averageResponseTime))
        - Min/Max Response Time: \(minResponseTime.map { String(format: "%.2fms", $0) } ?? "N/A") / \(maxResponseTime.map { String(format: "%.2fms", $0) } ?? "N/A")
        - P95/P99 Response Time: \(p95ResponseTime.map { String(format: "%.2fms", $0) } ?? "N/A") / \(p99ResponseTime.map { String(format: "%.2fms", $0) } ?? "N/A")
        - Total Sent: \(ByteCountFormatter.string(fromByteCount: Int64(totalBytesSent), countStyle: .file))
        - Total Received: \(ByteCountFormatter.string(fromByteCount: Int64(totalBytesReceived), countStyle: .file))
        """
    }
}
