import Foundation

/// Detailed metrics for a network request.
///
/// `RequestMetrics` captures comprehensive timing and size information
/// about a network request lifecycle.
///
/// ```swift
/// let metrics = try await client.requestWithMetrics(endpoint)
/// print("DNS: \(metrics.dnsLookupDuration)ms")
/// print("Connect: \(metrics.connectionDuration)ms")
/// print("Total: \(metrics.totalDuration)ms")
/// ```
public struct RequestMetrics: Sendable {

    // MARK: - Timing Properties

    /// When the request was initiated.
    public let requestStartDate: Date

    /// When the request completed.
    public let requestEndDate: Date?

    /// DNS lookup start time.
    public let domainLookupStartDate: Date?

    /// DNS lookup end time.
    public let domainLookupEndDate: Date?

    /// TCP connection start time.
    public let connectStartDate: Date?

    /// TCP connection end time.
    public let connectEndDate: Date?

    /// TLS handshake start time.
    public let secureConnectionStartDate: Date?

    /// TLS handshake end time.
    public let secureConnectionEndDate: Date?

    /// Request body transmission start time.
    public let requestBodyStartDate: Date?

    /// Request body transmission end time.
    public let requestBodyEndDate: Date?

    /// Response body reception start time.
    public let responseStartDate: Date?

    /// Response body reception end time.
    public let responseEndDate: Date?

    // MARK: - Size Properties

    /// Total bytes sent (headers + body).
    public let totalBytesSent: Int64

    /// Request header bytes sent.
    public let headerBytesSent: Int64

    /// Request body bytes sent.
    public let bodyBytesSent: Int64

    /// Total bytes received (headers + body).
    public let totalBytesReceived: Int64

    /// Response header bytes received.
    public let headerBytesReceived: Int64

    /// Response body bytes received.
    public let bodyBytesReceived: Int64

    // MARK: - Connection Properties

    /// Whether the connection was reused.
    public let connectionReused: Bool

    /// Whether the connection used a proxy.
    public let usedProxy: Bool

    /// The network protocol used (e.g., "h2", "http/1.1").
    public let networkProtocolName: String?

    /// The remote address.
    public let remoteAddress: String?

    /// The remote port.
    public let remotePort: Int?

    /// The local address.
    public let localAddress: String?

    /// The local port.
    public let localPort: Int?

    /// TLS protocol version.
    public let tlsProtocolVersion: String?

    /// TLS cipher suite.
    public let tlsCipherSuite: String?

    // MARK: - Request Properties

    /// The request URL.
    public let url: URL?

    /// The HTTP method.
    public let httpMethod: String?

    /// The response status code.
    public let statusCode: Int?

    /// Whether the request failed.
    public let isFailed: Bool

    /// The error if failed.
    public let error: Error?

    // MARK: - Computed Durations

    /// Total request duration in milliseconds.
    public var totalDuration: Double? {
        guard let end = requestEndDate else { return nil }
        return end.timeIntervalSince(requestStartDate) * 1000
    }

    /// DNS lookup duration in milliseconds.
    public var dnsLookupDuration: Double? {
        guard let start = domainLookupStartDate,
              let end = domainLookupEndDate else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    /// TCP connection duration in milliseconds.
    public var connectionDuration: Double? {
        guard let start = connectStartDate,
              let end = connectEndDate else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    /// TLS handshake duration in milliseconds.
    public var secureConnectionDuration: Double? {
        guard let start = secureConnectionStartDate,
              let end = secureConnectionEndDate else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    /// Request body transmission duration in milliseconds.
    public var requestBodyDuration: Double? {
        guard let start = requestBodyStartDate,
              let end = requestBodyEndDate else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    /// Response body reception duration in milliseconds.
    public var responseBodyDuration: Double? {
        guard let start = responseStartDate,
              let end = responseEndDate else { return nil }
        return end.timeIntervalSince(start) * 1000
    }

    /// Time to first byte (TTFB) in milliseconds.
    public var timeToFirstByte: Double? {
        guard let responseStart = responseStartDate else { return nil }
        return responseStart.timeIntervalSince(requestStartDate) * 1000
    }

    /// Server processing time (approximate) in milliseconds.
    public var serverProcessingTime: Double? {
        guard let requestEnd = requestBodyEndDate,
              let responseStart = responseStartDate else { return nil }
        return responseStart.timeIntervalSince(requestEnd) * 1000
    }

    // MARK: - Computed Rates

    /// Upload speed in bytes per second.
    public var uploadSpeed: Double? {
        guard let duration = requestBodyDuration, duration > 0 else { return nil }
        return Double(bodyBytesSent) / (duration / 1000)
    }

    /// Download speed in bytes per second.
    public var downloadSpeed: Double? {
        guard let duration = responseBodyDuration, duration > 0 else { return nil }
        return Double(bodyBytesReceived) / (duration / 1000)
    }

    // MARK: - Initialization

    /// Creates request metrics from URLSessionTaskMetrics.
    ///
    /// - Parameters:
    ///   - urlMetrics: The URLSession task metrics.
    ///   - statusCode: The response status code.
    ///   - error: Any error that occurred.
    public init(
        urlMetrics: URLSessionTaskMetrics,
        statusCode: Int? = nil,
        error: Error? = nil
    ) {
        let transaction = urlMetrics.transactionMetrics.last

        self.requestStartDate = urlMetrics.taskInterval.start
        self.requestEndDate = urlMetrics.taskInterval.end

        self.domainLookupStartDate = transaction?.domainLookupStartDate
        self.domainLookupEndDate = transaction?.domainLookupEndDate
        self.connectStartDate = transaction?.connectStartDate
        self.connectEndDate = transaction?.connectEndDate
        self.secureConnectionStartDate = transaction?.secureConnectionStartDate
        self.secureConnectionEndDate = transaction?.secureConnectionEndDate
        self.requestBodyStartDate = transaction?.requestStartDate
        self.requestBodyEndDate = transaction?.requestEndDate
        self.responseStartDate = transaction?.responseStartDate
        self.responseEndDate = transaction?.responseEndDate

        self.totalBytesSent = transaction?.countOfRequestHeaderBytesSent ?? 0
            + (transaction?.countOfRequestBodyBytesSent ?? 0)
        self.headerBytesSent = transaction?.countOfRequestHeaderBytesSent ?? 0
        self.bodyBytesSent = transaction?.countOfRequestBodyBytesSent ?? 0

        self.totalBytesReceived = transaction?.countOfResponseHeaderBytesReceived ?? 0
            + (transaction?.countOfResponseBodyBytesReceived ?? 0)
        self.headerBytesReceived = transaction?.countOfResponseHeaderBytesReceived ?? 0
        self.bodyBytesReceived = transaction?.countOfResponseBodyBytesReceived ?? 0

        self.connectionReused = transaction?.isReusedConnection ?? false
        self.usedProxy = transaction?.isProxyConnection ?? false
        self.networkProtocolName = transaction?.networkProtocolName
        self.remoteAddress = transaction?.remoteAddress?.url?.host
        self.remotePort = transaction?.remotePort?.intValue
        self.localAddress = transaction?.localAddress?.url?.host
        self.localPort = transaction?.localPort?.intValue

        if #available(iOS 14.0, macOS 11.0, *) {
            self.tlsProtocolVersion = transaction?.negotiatedTLSProtocolVersion.flatMap { String(describing: $0) }
            self.tlsCipherSuite = transaction?.negotiatedTLSCipherSuite.flatMap { String(describing: $0) }
        } else {
            self.tlsProtocolVersion = nil
            self.tlsCipherSuite = nil
        }

        self.url = transaction?.request.url
        self.httpMethod = transaction?.request.httpMethod
        self.statusCode = statusCode
        self.isFailed = error != nil
        self.error = error
    }

    /// Creates manual request metrics.
    public init(
        requestStartDate: Date,
        requestEndDate: Date?,
        totalBytesSent: Int64 = 0,
        totalBytesReceived: Int64 = 0,
        url: URL? = nil,
        httpMethod: String? = nil,
        statusCode: Int? = nil,
        error: Error? = nil
    ) {
        self.requestStartDate = requestStartDate
        self.requestEndDate = requestEndDate
        self.domainLookupStartDate = nil
        self.domainLookupEndDate = nil
        self.connectStartDate = nil
        self.connectEndDate = nil
        self.secureConnectionStartDate = nil
        self.secureConnectionEndDate = nil
        self.requestBodyStartDate = nil
        self.requestBodyEndDate = nil
        self.responseStartDate = nil
        self.responseEndDate = nil

        self.totalBytesSent = totalBytesSent
        self.headerBytesSent = 0
        self.bodyBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.headerBytesReceived = 0
        self.bodyBytesReceived = totalBytesReceived

        self.connectionReused = false
        self.usedProxy = false
        self.networkProtocolName = nil
        self.remoteAddress = nil
        self.remotePort = nil
        self.localAddress = nil
        self.localPort = nil
        self.tlsProtocolVersion = nil
        self.tlsCipherSuite = nil

        self.url = url
        self.httpMethod = httpMethod
        self.statusCode = statusCode
        self.isFailed = error != nil
        self.error = error
    }
}

// MARK: - CustomStringConvertible

extension RequestMetrics: CustomStringConvertible {

    public var description: String {
        var parts: [String] = []

        if let method = httpMethod, let url = url {
            parts.append("\(method) \(url.path)")
        }

        if let status = statusCode {
            parts.append("Status: \(status)")
        }

        if let total = totalDuration {
            parts.append(String(format: "Total: %.2fms", total))
        }

        if let dns = dnsLookupDuration, dns > 0 {
            parts.append(String(format: "DNS: %.2fms", dns))
        }

        if let connect = connectionDuration {
            parts.append(String(format: "Connect: %.2fms", connect))
        }

        if let ttfb = timeToFirstByte {
            parts.append(String(format: "TTFB: %.2fms", ttfb))
        }

        if connectionReused {
            parts.append("(reused)")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Metrics Aggregator

/// Aggregates multiple request metrics for analysis.
public struct MetricsAggregator: Sendable {

    /// The aggregated metrics.
    public let metrics: [RequestMetrics]

    /// Creates an aggregator.
    public init(metrics: [RequestMetrics]) {
        self.metrics = metrics
    }

    /// Total request count.
    public var count: Int { metrics.count }

    /// Success count.
    public var successCount: Int {
        metrics.filter { !$0.isFailed }.count
    }

    /// Failure count.
    public var failureCount: Int {
        metrics.filter { $0.isFailed }.count
    }

    /// Success rate as percentage.
    public var successRate: Double {
        guard count > 0 else { return 0 }
        return Double(successCount) / Double(count) * 100
    }

    /// Average total duration.
    public var averageDuration: Double? {
        let durations = metrics.compactMap { $0.totalDuration }
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// Median total duration.
    public var medianDuration: Double? {
        let durations = metrics.compactMap { $0.totalDuration }.sorted()
        guard !durations.isEmpty else { return nil }
        return durations[durations.count / 2]
    }

    /// P95 duration.
    public var p95Duration: Double? {
        let durations = metrics.compactMap { $0.totalDuration }.sorted()
        guard !durations.isEmpty else { return nil }
        let index = Int(Double(durations.count) * 0.95)
        return durations[min(index, durations.count - 1)]
    }

    /// Total bytes sent.
    public var totalBytesSent: Int64 {
        metrics.reduce(0) { $0 + $1.totalBytesSent }
    }

    /// Total bytes received.
    public var totalBytesReceived: Int64 {
        metrics.reduce(0) { $0 + $1.totalBytesReceived }
    }
}
