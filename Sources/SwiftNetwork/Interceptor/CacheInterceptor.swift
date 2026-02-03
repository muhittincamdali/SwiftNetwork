import Foundation

/// An interceptor that provides caching for network responses.
///
/// `CacheInterceptor` can cache responses based on configurable policies
/// and return cached data for subsequent identical requests.
///
/// ```swift
/// let cacheInterceptor = CacheInterceptor(
///     storage: MemoryCacheStorage(),
///     policy: .cacheFirst
/// )
///
/// let client = NetworkClient(
///     baseURL: url,
///     interceptors: [cacheInterceptor]
/// )
/// ```
public final class CacheInterceptor: NetworkInterceptor, @unchecked Sendable {

    // MARK: - Types

    /// Cache policy determining when to use cached responses.
    public enum CachePolicy: Sendable {
        /// Always use network, cache response for future use.
        case networkFirst

        /// Use cache if available, otherwise use network.
        case cacheFirst

        /// Use cache only if within TTL, otherwise network.
        case cacheIfFresh

        /// Always use network, ignore cache entirely.
        case networkOnly

        /// Use cache only, never hit network.
        case cacheOnly

        /// Use stale cache while revalidating in background.
        case staleWhileRevalidate
    }

    /// Cache entry containing response and metadata.
    public struct CacheEntry: Sendable, Codable {
        /// The cached response data.
        public let data: Data

        /// The HTTP status code.
        public let statusCode: Int

        /// The response headers.
        public let headers: [String: String]

        /// When the entry was cached.
        public let cachedAt: Date

        /// Time-to-live for this entry in seconds.
        public let ttl: TimeInterval

        /// The ETag for conditional requests.
        public let etag: String?

        /// The Last-Modified header value.
        public let lastModified: String?

        /// Whether the entry is still fresh.
        public var isFresh: Bool {
            Date().timeIntervalSince(cachedAt) < ttl
        }

        /// The age of this cache entry in seconds.
        public var age: TimeInterval {
            Date().timeIntervalSince(cachedAt)
        }

        /// Creates a cache entry.
        public init(
            data: Data,
            statusCode: Int,
            headers: [String: String],
            cachedAt: Date = Date(),
            ttl: TimeInterval,
            etag: String? = nil,
            lastModified: String? = nil
        ) {
            self.data = data
            self.statusCode = statusCode
            self.headers = headers
            self.cachedAt = cachedAt
            self.ttl = ttl
            self.etag = etag
            self.lastModified = lastModified
        }

        /// Creates a cache entry from a network response.
        public init(from response: NetworkResponse, ttl: TimeInterval) {
            self.data = response.data
            self.statusCode = response.statusCode
            self.headers = response.headers
            self.cachedAt = Date()
            self.ttl = ttl
            self.etag = response.headers["ETag"]
            self.lastModified = response.headers["Last-Modified"]
        }
    }

    /// Protocol for cache storage implementations.
    public protocol CacheStorage: Sendable {
        func get(key: String) async -> CacheEntry?
        func set(key: String, entry: CacheEntry) async
        func remove(key: String) async
        func removeAll() async
        func keys() async -> [String]
    }

    // MARK: - Properties

    /// The cache storage backend.
    public let storage: any CacheStorage

    /// The default cache policy.
    public let defaultPolicy: CachePolicy

    /// Default TTL for cached responses in seconds.
    public let defaultTTL: TimeInterval

    /// HTTP methods that should be cached.
    public let cacheableMethods: Set<String>

    /// Status codes that should be cached.
    public let cacheableStatusCodes: Set<Int>

    /// Whether to respect Cache-Control headers.
    public let respectCacheHeaders: Bool

    /// Custom key generator function.
    private let keyGenerator: @Sendable (URLRequest) -> String

    // MARK: - Initialization

    /// Creates a cache interceptor.
    ///
    /// - Parameters:
    ///   - storage: The cache storage to use.
    ///   - policy: The default cache policy. Defaults to `.cacheFirst`.
    ///   - defaultTTL: Default TTL in seconds. Defaults to 300 (5 minutes).
    ///   - cacheableMethods: Methods to cache. Defaults to GET.
    ///   - cacheableStatusCodes: Status codes to cache. Defaults to 200-299.
    ///   - respectCacheHeaders: Whether to respect cache headers. Defaults to true.
    ///   - keyGenerator: Custom cache key generator.
    public init(
        storage: any CacheStorage,
        policy: CachePolicy = .cacheFirst,
        defaultTTL: TimeInterval = 300,
        cacheableMethods: Set<String> = ["GET"],
        cacheableStatusCodes: Set<Int> = Set(200...299),
        respectCacheHeaders: Bool = true,
        keyGenerator: (@Sendable (URLRequest) -> String)? = nil
    ) {
        self.storage = storage
        self.defaultPolicy = policy
        self.defaultTTL = defaultTTL
        self.cacheableMethods = cacheableMethods
        self.cacheableStatusCodes = cacheableStatusCodes
        self.respectCacheHeaders = respectCacheHeaders
        self.keyGenerator = keyGenerator ?? Self.defaultKeyGenerator
    }

    // MARK: - NetworkInterceptor

    public func intercept(request: URLRequest) async throws -> URLRequest {
        // Check if request is cacheable
        guard isCacheable(request) else {
            return request
        }

        let key = keyGenerator(request)

        // Add cache headers for conditional requests
        if let entry = await storage.get(key: key) {
            var modified = request

            if let etag = entry.etag {
                modified.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            if let lastModified = entry.lastModified {
                modified.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }

            return modified
        }

        return request
    }

    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        guard let request = response.originalRequest,
              isCacheable(request),
              shouldCache(response) else {
            return response
        }

        let key = keyGenerator(request)
        let ttl = determineTTL(from: response)

        let entry = CacheEntry(from: response, ttl: ttl)
        await storage.set(key: key, entry: entry)

        return response
    }

    // MARK: - Cache Operations

    /// Gets a cached response for a request.
    ///
    /// - Parameter request: The request to look up.
    /// - Returns: The cached response, or nil.
    public func getCached(for request: URLRequest) async -> NetworkResponse? {
        guard isCacheable(request) else { return nil }

        let key = keyGenerator(request)
        guard let entry = await storage.get(key: key) else { return nil }

        switch defaultPolicy {
        case .cacheFirst, .staleWhileRevalidate:
            return responseFromEntry(entry, request: request)
        case .cacheIfFresh:
            return entry.isFresh ? responseFromEntry(entry, request: request) : nil
        case .cacheOnly:
            return responseFromEntry(entry, request: request)
        case .networkFirst, .networkOnly:
            return nil
        }
    }

    /// Removes a cached response.
    ///
    /// - Parameter request: The request to remove.
    public func removeCached(for request: URLRequest) async {
        let key = keyGenerator(request)
        await storage.remove(key: key)
    }

    /// Clears all cached responses.
    public func clearCache() async {
        await storage.removeAll()
    }

    /// Gets all cache keys.
    ///
    /// - Returns: An array of cache keys.
    public func allCacheKeys() async -> [String] {
        await storage.keys()
    }

    // MARK: - Private Helpers

    private func isCacheable(_ request: URLRequest) -> Bool {
        guard let method = request.httpMethod else { return false }
        return cacheableMethods.contains(method.uppercased())
    }

    private func shouldCache(_ response: NetworkResponse) -> Bool {
        guard cacheableStatusCodes.contains(response.statusCode) else {
            return false
        }

        if respectCacheHeaders {
            if let cacheControl = response.headers["Cache-Control"] {
                if cacheControl.contains("no-store") || cacheControl.contains("no-cache") {
                    return false
                }
            }

            if response.headers["Pragma"] == "no-cache" {
                return false
            }
        }

        return true
    }

    private func determineTTL(from response: NetworkResponse) -> TimeInterval {
        guard respectCacheHeaders else {
            return defaultTTL
        }

        // Check Cache-Control max-age
        if let cacheControl = response.headers["Cache-Control"] {
            let components = cacheControl.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for component in components {
                if component.hasPrefix("max-age=") {
                    let valueString = component.dropFirst("max-age=".count)
                    if let maxAge = TimeInterval(valueString) {
                        return maxAge
                    }
                }
            }
        }

        // Check Expires header
        if let expires = response.headers["Expires"] {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let expiresDate = formatter.date(from: expires) {
                let ttl = expiresDate.timeIntervalSince(Date())
                return max(0, ttl)
            }
        }

        return defaultTTL
    }

    private func responseFromEntry(_ entry: CacheEntry, request: URLRequest) -> NetworkResponse {
        NetworkResponse(
            data: entry.data,
            statusCode: entry.statusCode,
            headers: entry.headers,
            originalRequest: request,
            httpResponse: nil
        )
    }

    private static let defaultKeyGenerator: @Sendable (URLRequest) -> String = { request in
        var components: [String] = []

        if let method = request.httpMethod {
            components.append(method)
        }

        if let url = request.url?.absoluteString {
            components.append(url)
        }

        return components.joined(separator: ":")
    }
}

// MARK: - Memory Cache Storage

/// In-memory cache storage implementation.
public final class MemoryCacheStorage: CacheInterceptor.CacheStorage, @unchecked Sendable {

    private var cache: [String: CacheInterceptor.CacheEntry] = [:]
    private let lock = NSLock()
    private let maxEntries: Int
    private let pruneAmount: Int

    /// Creates a memory cache storage.
    ///
    /// - Parameters:
    ///   - maxEntries: Maximum number of entries. Defaults to 100.
    ///   - pruneAmount: Number of entries to remove when full. Defaults to 20.
    public init(maxEntries: Int = 100, pruneAmount: Int = 20) {
        self.maxEntries = maxEntries
        self.pruneAmount = pruneAmount
    }

    public func get(key: String) async -> CacheInterceptor.CacheEntry? {
        lock.withLock {
            guard let entry = cache[key] else { return nil }

            // Remove expired entries
            if !entry.isFresh {
                cache[key] = nil
                return nil
            }

            return entry
        }
    }

    public func set(key: String, entry: CacheInterceptor.CacheEntry) async {
        lock.withLock {
            // Prune if at capacity
            if cache.count >= maxEntries {
                pruneExpiredEntries()

                // If still at capacity, remove oldest entries
                if cache.count >= maxEntries {
                    let sortedKeys = cache.sorted { $0.value.cachedAt < $1.value.cachedAt }
                        .prefix(pruneAmount)
                        .map { $0.key }

                    for key in sortedKeys {
                        cache[key] = nil
                    }
                }
            }

            cache[key] = entry
        }
    }

    public func remove(key: String) async {
        lock.withLock {
            cache[key] = nil
        }
    }

    public func removeAll() async {
        lock.withLock {
            cache.removeAll()
        }
    }

    public func keys() async -> [String] {
        lock.withLock {
            Array(cache.keys)
        }
    }

    private func pruneExpiredEntries() {
        let now = Date()
        cache = cache.filter { _, entry in
            now.timeIntervalSince(entry.cachedAt) < entry.ttl
        }
    }

    /// Returns the current number of entries.
    public var count: Int {
        lock.withLock { cache.count }
    }
}

// MARK: - Disk Cache Storage

/// Disk-based cache storage implementation.
public final class DiskCacheStorage: CacheInterceptor.CacheStorage, @unchecked Sendable {

    private let directory: URL
    private let fileManager: FileManager
    private let maxSize: Int64
    private var currentSize: Int64 = 0
    private let lock = NSLock()

    /// Creates a disk cache storage.
    ///
    /// - Parameters:
    ///   - directory: The directory to store cache files.
    ///   - maxSize: Maximum cache size in bytes. Defaults to 50MB.
    public init(directory: URL, maxSize: Int64 = 50 * 1024 * 1024) {
        self.directory = directory
        self.maxSize = maxSize
        self.fileManager = FileManager.default

        // Create directory if needed
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        // Calculate initial size
        calculateCurrentSize()
    }

    public func get(key: String) async -> CacheInterceptor.CacheEntry? {
        let fileURL = fileURL(for: key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let entry = try JSONDecoder().decode(CacheInterceptor.CacheEntry.self, from: data)

            // Remove if expired
            if !entry.isFresh {
                try? fileManager.removeItem(at: fileURL)
                updateSize()
                return nil
            }

            // Update access time
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)

            return entry
        } catch {
            return nil
        }
    }

    public func set(key: String, entry: CacheInterceptor.CacheEntry) async {
        let fileURL = fileURL(for: key)

        do {
            let data = try JSONEncoder().encode(entry)

            // Check if we need to make space
            lock.withLock {
                while currentSize + Int64(data.count) > maxSize {
                    evictOldestEntry()
                }
            }

            try data.write(to: fileURL, options: .atomic)
            updateSize()
        } catch {
            // Cache write failure is not critical
        }
    }

    public func remove(key: String) async {
        let fileURL = fileURL(for: key)
        try? fileManager.removeItem(at: fileURL)
        updateSize()
    }

    public func removeAll() async {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        lock.withLock {
            currentSize = 0
        }
    }

    public func keys() async -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }

        return contents.compactMap { filename in
            guard filename.hasSuffix(".cache") else { return nil }
            return String(filename.dropLast(6)) // Remove .cache extension
        }
    }

    private func fileURL(for key: String) -> URL {
        let safeKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return directory.appendingPathComponent("\(safeKey).cache")
    }

    private func calculateCurrentSize() {
        lock.withLock {
            currentSize = 0
            guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
                return
            }

            for url in contents {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    currentSize += Int64(size)
                }
            }
        }
    }

    private func updateSize() {
        Task {
            calculateCurrentSize()
        }
    }

    private func evictOldestEntry() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return
        }

        let sorted = contents.compactMap { url -> (URL, Date, Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else {
                return nil
            }
            return (url, date, Int64(size))
        }.sorted { $0.1 < $1.1 }

        if let oldest = sorted.first {
            try? fileManager.removeItem(at: oldest.0)
            currentSize -= oldest.2
        }
    }
}
