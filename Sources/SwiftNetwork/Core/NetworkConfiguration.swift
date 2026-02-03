import Foundation

/// Configuration options for network operations.
///
/// `NetworkConfiguration` provides a centralized way to configure common settings
/// that apply to all requests made through a ``NetworkClient``.
///
/// ```swift
/// let config = NetworkConfiguration(
///     defaultTimeout: 30,
///     maxConcurrentRequests: 4,
///     cachingPolicy: .returnCacheDataElseLoad
/// )
///
/// let client = NetworkClient(
///     baseURL: "https://api.example.com",
///     configuration: config
/// )
/// ```
public struct NetworkConfiguration: Sendable {

    // MARK: - Timeout Settings

    /// Default timeout interval for requests in seconds.
    public let defaultTimeout: TimeInterval

    /// Timeout interval for resource fetching.
    public let resourceTimeout: TimeInterval

    /// Connection establishment timeout.
    public let connectionTimeout: TimeInterval

    // MARK: - Concurrency Settings

    /// Maximum number of concurrent HTTP connections per host.
    public let maxConnectionsPerHost: Int

    /// Maximum number of concurrent requests being processed.
    public let maxConcurrentRequests: Int

    /// Whether to wait for connectivity before sending requests.
    public let waitsForConnectivity: Bool

    // MARK: - Caching Settings

    /// The default caching policy for requests.
    public let cachingPolicy: URLRequest.CachePolicy

    /// Maximum cache size in bytes.
    public let cacheSizeMemory: Int

    /// Maximum disk cache size in bytes.
    public let cacheSizeDisk: Int

    /// Whether responses should be cached.
    public let shouldCacheResponses: Bool

    // MARK: - Cookie Settings

    /// The cookie acceptance policy.
    public let cookiePolicy: HTTPCookie.AcceptPolicy

    /// Whether to store cookies automatically.
    public let shouldStoreCookies: Bool

    // MARK: - Security Settings

    /// Whether to allow cellular network access.
    public let allowsCellularAccess: Bool

    /// Whether to allow expensive network access (e.g., when roaming).
    public let allowsExpensiveNetworkAccess: Bool

    /// Whether to allow constrained network access.
    public let allowsConstrainedNetworkAccess: Bool

    /// TLS minimum supported protocol version.
    public let tlsMinimumVersion: tls_protocol_version_t

    /// TLS maximum supported protocol version.
    public let tlsMaximumVersion: tls_protocol_version_t

    // MARK: - Request Settings

    /// Default headers applied to all requests.
    public let defaultHeaders: [String: String]

    /// Whether to use HTTP pipelining.
    public let httpShouldUsePipelining: Bool

    /// Whether to set cookies automatically.
    public let httpShouldSetCookies: Bool

    // MARK: - Network Service Type

    /// The network service type for prioritization.
    public let networkServiceType: URLRequest.NetworkServiceType

    // MARK: - Proxy Configuration

    /// Custom proxy dictionary for connection settings.
    public let proxyConfiguration: [AnyHashable: Any]?

    // MARK: - Initialization

    /// Creates a new network configuration with customizable options.
    ///
    /// - Parameters:
    ///   - defaultTimeout: Request timeout in seconds. Defaults to 30.
    ///   - resourceTimeout: Resource fetch timeout. Defaults to 300.
    ///   - connectionTimeout: Connection timeout. Defaults to 15.
    ///   - maxConnectionsPerHost: Max connections per host. Defaults to 6.
    ///   - maxConcurrentRequests: Max concurrent requests. Defaults to 4.
    ///   - waitsForConnectivity: Wait for connectivity. Defaults to true.
    ///   - cachingPolicy: Cache policy. Defaults to `.useProtocolCachePolicy`.
    ///   - cacheSizeMemory: Memory cache size. Defaults to 10MB.
    ///   - cacheSizeDisk: Disk cache size. Defaults to 100MB.
    ///   - shouldCacheResponses: Enable response caching. Defaults to true.
    ///   - cookiePolicy: Cookie acceptance policy. Defaults to `.onlyFromMainDocumentDomain`.
    ///   - shouldStoreCookies: Store cookies. Defaults to true.
    ///   - allowsCellularAccess: Allow cellular. Defaults to true.
    ///   - allowsExpensiveNetworkAccess: Allow expensive network. Defaults to true.
    ///   - allowsConstrainedNetworkAccess: Allow constrained network. Defaults to true.
    ///   - tlsMinimumVersion: Minimum TLS version. Defaults to TLS 1.2.
    ///   - tlsMaximumVersion: Maximum TLS version. Defaults to TLS 1.3.
    ///   - defaultHeaders: Headers for all requests. Defaults to empty.
    ///   - httpShouldUsePipelining: Use pipelining. Defaults to false.
    ///   - httpShouldSetCookies: Auto-set cookies. Defaults to true.
    ///   - networkServiceType: Service type. Defaults to `.default`.
    ///   - proxyConfiguration: Proxy settings. Defaults to nil.
    public init(
        defaultTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 300,
        connectionTimeout: TimeInterval = 15,
        maxConnectionsPerHost: Int = 6,
        maxConcurrentRequests: Int = 4,
        waitsForConnectivity: Bool = true,
        cachingPolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        cacheSizeMemory: Int = 10 * 1024 * 1024,
        cacheSizeDisk: Int = 100 * 1024 * 1024,
        shouldCacheResponses: Bool = true,
        cookiePolicy: HTTPCookie.AcceptPolicy = .onlyFromMainDocumentDomain,
        shouldStoreCookies: Bool = true,
        allowsCellularAccess: Bool = true,
        allowsExpensiveNetworkAccess: Bool = true,
        allowsConstrainedNetworkAccess: Bool = true,
        tlsMinimumVersion: tls_protocol_version_t = .TLSv12,
        tlsMaximumVersion: tls_protocol_version_t = .TLSv13,
        defaultHeaders: [String: String] = [:],
        httpShouldUsePipelining: Bool = false,
        httpShouldSetCookies: Bool = true,
        networkServiceType: URLRequest.NetworkServiceType = .default,
        proxyConfiguration: [AnyHashable: Any]? = nil
    ) {
        self.defaultTimeout = defaultTimeout
        self.resourceTimeout = resourceTimeout
        self.connectionTimeout = connectionTimeout
        self.maxConnectionsPerHost = maxConnectionsPerHost
        self.maxConcurrentRequests = maxConcurrentRequests
        self.waitsForConnectivity = waitsForConnectivity
        self.cachingPolicy = cachingPolicy
        self.cacheSizeMemory = cacheSizeMemory
        self.cacheSizeDisk = cacheSizeDisk
        self.shouldCacheResponses = shouldCacheResponses
        self.cookiePolicy = cookiePolicy
        self.shouldStoreCookies = shouldStoreCookies
        self.allowsCellularAccess = allowsCellularAccess
        self.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        self.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
        self.tlsMinimumVersion = tlsMinimumVersion
        self.tlsMaximumVersion = tlsMaximumVersion
        self.defaultHeaders = defaultHeaders
        self.httpShouldUsePipelining = httpShouldUsePipelining
        self.httpShouldSetCookies = httpShouldSetCookies
        self.networkServiceType = networkServiceType
        self.proxyConfiguration = proxyConfiguration
    }

    // MARK: - URLSession Configuration

    /// Creates a URLSessionConfiguration from this network configuration.
    ///
    /// - Returns: A configured URLSessionConfiguration instance.
    public func urlSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default

        config.timeoutIntervalForRequest = defaultTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.httpMaximumConnectionsPerHost = maxConnectionsPerHost
        config.waitsForConnectivity = waitsForConnectivity
        config.requestCachePolicy = cachingPolicy
        config.httpCookieAcceptPolicy = cookiePolicy
        config.httpShouldSetCookies = httpShouldSetCookies
        config.httpShouldUsePipelining = httpShouldUsePipelining
        config.allowsCellularAccess = allowsCellularAccess
        config.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        config.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
        config.networkServiceType = networkServiceType
        config.tlsMinimumSupportedProtocolVersion = tlsMinimumVersion
        config.tlsMaximumSupportedProtocolVersion = tlsMaximumVersion

        if shouldCacheResponses {
            config.urlCache = URLCache(
                memoryCapacity: cacheSizeMemory,
                diskCapacity: cacheSizeDisk
            )
        }

        if let proxy = proxyConfiguration {
            config.connectionProxyDictionary = proxy
        }

        if !defaultHeaders.isEmpty {
            config.httpAdditionalHeaders = defaultHeaders
        }

        return config
    }

    // MARK: - Presets

    /// Default configuration suitable for most applications.
    public static let `default` = NetworkConfiguration()

    /// High-performance configuration for fast API calls.
    public static let highPerformance = NetworkConfiguration(
        defaultTimeout: 15,
        resourceTimeout: 60,
        connectionTimeout: 5,
        maxConnectionsPerHost: 8,
        maxConcurrentRequests: 8,
        waitsForConnectivity: false,
        cachingPolicy: .reloadIgnoringLocalCacheData,
        shouldCacheResponses: false,
        httpShouldUsePipelining: true
    )

    /// Low-bandwidth configuration for slow connections.
    public static let lowBandwidth = NetworkConfiguration(
        defaultTimeout: 120,
        resourceTimeout: 600,
        connectionTimeout: 60,
        maxConnectionsPerHost: 2,
        maxConcurrentRequests: 2,
        waitsForConnectivity: true,
        cachingPolicy: .returnCacheDataElseLoad,
        shouldCacheResponses: true,
        allowsExpensiveNetworkAccess: false
    )

    /// Background transfer configuration.
    public static let background = NetworkConfiguration(
        defaultTimeout: 300,
        resourceTimeout: 3600,
        connectionTimeout: 60,
        maxConnectionsPerHost: 4,
        maxConcurrentRequests: 2,
        waitsForConnectivity: true,
        cachingPolicy: .useProtocolCachePolicy,
        shouldCacheResponses: true,
        networkServiceType: .background
    )

    /// Secure configuration with strict TLS settings.
    public static let secure = NetworkConfiguration(
        defaultTimeout: 30,
        tlsMinimumVersion: .TLSv13,
        tlsMaximumVersion: .TLSv13,
        defaultHeaders: [
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains"
        ]
    )
}

// MARK: - Builder Pattern

extension NetworkConfiguration {

    /// A builder for creating customized network configurations.
    public final class Builder: @unchecked Sendable {
        private var defaultTimeout: TimeInterval = 30
        private var resourceTimeout: TimeInterval = 300
        private var connectionTimeout: TimeInterval = 15
        private var maxConnectionsPerHost: Int = 6
        private var maxConcurrentRequests: Int = 4
        private var waitsForConnectivity: Bool = true
        private var cachingPolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
        private var cacheSizeMemory: Int = 10 * 1024 * 1024
        private var cacheSizeDisk: Int = 100 * 1024 * 1024
        private var shouldCacheResponses: Bool = true
        private var cookiePolicy: HTTPCookie.AcceptPolicy = .onlyFromMainDocumentDomain
        private var shouldStoreCookies: Bool = true
        private var allowsCellularAccess: Bool = true
        private var allowsExpensiveNetworkAccess: Bool = true
        private var allowsConstrainedNetworkAccess: Bool = true
        private var tlsMinimumVersion: tls_protocol_version_t = .TLSv12
        private var tlsMaximumVersion: tls_protocol_version_t = .TLSv13
        private var defaultHeaders: [String: String] = [:]
        private var httpShouldUsePipelining: Bool = false
        private var httpShouldSetCookies: Bool = true
        private var networkServiceType: URLRequest.NetworkServiceType = .default
        private var proxyConfiguration: [AnyHashable: Any]?

        /// Creates a new configuration builder.
        public init() {}

        /// Sets the default request timeout.
        @discardableResult
        public func defaultTimeout(_ value: TimeInterval) -> Builder {
            self.defaultTimeout = value
            return self
        }

        /// Sets the resource timeout.
        @discardableResult
        public func resourceTimeout(_ value: TimeInterval) -> Builder {
            self.resourceTimeout = value
            return self
        }

        /// Sets the connection timeout.
        @discardableResult
        public func connectionTimeout(_ value: TimeInterval) -> Builder {
            self.connectionTimeout = value
            return self
        }

        /// Sets max connections per host.
        @discardableResult
        public func maxConnectionsPerHost(_ value: Int) -> Builder {
            self.maxConnectionsPerHost = value
            return self
        }

        /// Sets max concurrent requests.
        @discardableResult
        public func maxConcurrentRequests(_ value: Int) -> Builder {
            self.maxConcurrentRequests = value
            return self
        }

        /// Sets whether to wait for connectivity.
        @discardableResult
        public func waitsForConnectivity(_ value: Bool) -> Builder {
            self.waitsForConnectivity = value
            return self
        }

        /// Sets the caching policy.
        @discardableResult
        public func cachingPolicy(_ value: URLRequest.CachePolicy) -> Builder {
            self.cachingPolicy = value
            return self
        }

        /// Sets the memory cache size.
        @discardableResult
        public func cacheSizeMemory(_ value: Int) -> Builder {
            self.cacheSizeMemory = value
            return self
        }

        /// Sets the disk cache size.
        @discardableResult
        public func cacheSizeDisk(_ value: Int) -> Builder {
            self.cacheSizeDisk = value
            return self
        }

        /// Sets whether to cache responses.
        @discardableResult
        public func shouldCacheResponses(_ value: Bool) -> Builder {
            self.shouldCacheResponses = value
            return self
        }

        /// Sets the cookie policy.
        @discardableResult
        public func cookiePolicy(_ value: HTTPCookie.AcceptPolicy) -> Builder {
            self.cookiePolicy = value
            return self
        }

        /// Adds a default header.
        @discardableResult
        public func addHeader(_ key: String, _ value: String) -> Builder {
            self.defaultHeaders[key] = value
            return self
        }

        /// Sets the network service type.
        @discardableResult
        public func networkServiceType(_ value: URLRequest.NetworkServiceType) -> Builder {
            self.networkServiceType = value
            return self
        }

        /// Builds the configuration.
        public func build() -> NetworkConfiguration {
            NetworkConfiguration(
                defaultTimeout: defaultTimeout,
                resourceTimeout: resourceTimeout,
                connectionTimeout: connectionTimeout,
                maxConnectionsPerHost: maxConnectionsPerHost,
                maxConcurrentRequests: maxConcurrentRequests,
                waitsForConnectivity: waitsForConnectivity,
                cachingPolicy: cachingPolicy,
                cacheSizeMemory: cacheSizeMemory,
                cacheSizeDisk: cacheSizeDisk,
                shouldCacheResponses: shouldCacheResponses,
                cookiePolicy: cookiePolicy,
                shouldStoreCookies: shouldStoreCookies,
                allowsCellularAccess: allowsCellularAccess,
                allowsExpensiveNetworkAccess: allowsExpensiveNetworkAccess,
                allowsConstrainedNetworkAccess: allowsConstrainedNetworkAccess,
                tlsMinimumVersion: tlsMinimumVersion,
                tlsMaximumVersion: tlsMaximumVersion,
                defaultHeaders: defaultHeaders,
                httpShouldUsePipelining: httpShouldUsePipelining,
                httpShouldSetCookies: httpShouldSetCookies,
                networkServiceType: networkServiceType,
                proxyConfiguration: proxyConfiguration
            )
        }
    }
}
