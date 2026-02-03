import Foundation

/// Encapsulates resume data for paused downloads.
///
/// `ResumeData` stores the information needed to resume an interrupted
/// download, including the raw resume data and metadata.
///
/// ```swift
/// let resumeData = await downloadTask.pause()
///
/// // Persist resume data
/// try resumeData?.save(to: cacheDirectory)
///
/// // Later, restore and resume
/// let restored = try ResumeData.load(from: cacheDirectory, id: downloadId)
/// let task = DownloadTask(resumeData: restored, destination: destination)
/// let file = try await task.resume()
/// ```
public struct ResumeData: Sendable, Codable {

    // MARK: - Properties

    /// Unique identifier for the download.
    public let downloadId: String

    /// The original download URL.
    public let originalURL: URL

    /// The raw resume data from URLSession.
    public let data: Data

    /// Bytes received before pause.
    public let bytesReceived: Int64

    /// Total expected bytes, if known.
    public let totalBytes: Int64?

    /// When the resume data was created.
    public let createdAt: Date

    /// Metadata for the download.
    public let metadata: [String: String]

    // MARK: - Computed Properties

    /// Whether this resume data is still valid (not expired).
    public var isValid: Bool {
        // Resume data typically expires after a certain period
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(createdAt) < expirationInterval
    }

    /// Age of the resume data in seconds.
    public var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }

    /// Size of the resume data in bytes.
    public var dataSize: Int {
        data.count
    }

    // MARK: - Initialization

    /// Creates new resume data.
    ///
    /// - Parameters:
    ///   - downloadId: Unique download identifier.
    ///   - originalURL: The download URL.
    ///   - data: Raw resume data.
    ///   - bytesReceived: Bytes received so far.
    ///   - totalBytes: Total expected bytes.
    ///   - createdAt: When created.
    ///   - metadata: Additional metadata.
    public init(
        downloadId: String,
        originalURL: URL,
        data: Data,
        bytesReceived: Int64 = 0,
        totalBytes: Int64? = nil,
        createdAt: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.downloadId = downloadId
        self.originalURL = originalURL
        self.data = data
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.createdAt = createdAt
        self.metadata = metadata
    }

    // MARK: - Persistence

    /// Saves resume data to a directory.
    ///
    /// - Parameter directory: The directory to save to.
    /// - Throws: File operation errors.
    public func save(to directory: URL) throws {
        let fileURL = directory.appendingPathComponent("\(downloadId).resume")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(self)

        try encoded.write(to: fileURL, options: .atomic)
    }

    /// Loads resume data from a directory.
    ///
    /// - Parameters:
    ///   - directory: The directory to load from.
    ///   - id: The download ID.
    /// - Returns: The loaded resume data.
    /// - Throws: File operation or decoding errors.
    public static func load(from directory: URL, id: String) throws -> ResumeData {
        let fileURL = directory.appendingPathComponent("\(id).resume")
        let data = try Data(contentsOf: fileURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResumeData.self, from: data)
    }

    /// Loads all resume data from a directory.
    ///
    /// - Parameter directory: The directory to scan.
    /// - Returns: Array of resume data objects.
    public static func loadAll(from directory: URL) -> [ResumeData] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return contents.compactMap { url -> ResumeData? in
            guard url.pathExtension == "resume" else { return nil }

            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(ResumeData.self, from: data)
            } catch {
                return nil
            }
        }
    }

    /// Deletes the resume data file.
    ///
    /// - Parameter directory: The directory containing the file.
    /// - Throws: File operation errors.
    public func delete(from directory: URL) throws {
        let fileURL = directory.appendingPathComponent("\(downloadId).resume")
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Cleans up expired resume data from a directory.
    ///
    /// - Parameter directory: The directory to clean.
    /// - Returns: Number of deleted files.
    @discardableResult
    public static func cleanupExpired(in directory: URL) -> Int {
        let allData = loadAll(from: directory)
        var deletedCount = 0

        for resumeData in allData {
            if !resumeData.isValid {
                try? resumeData.delete(from: directory)
                deletedCount += 1
            }
        }

        return deletedCount
    }
}

// MARK: - Resume Data Store

/// Manages persistent storage of resume data.
public actor ResumeDataStore {

    /// The storage directory.
    public let directory: URL

    /// In-memory cache of resume data.
    private var cache: [String: ResumeData] = [:]

    /// Whether to automatically clean expired data.
    public let autoCleanup: Bool

    /// Creates a resume data store.
    ///
    /// - Parameters:
    ///   - directory: The storage directory.
    ///   - autoCleanup: Whether to auto-clean expired data.
    public init(directory: URL, autoCleanup: Bool = true) {
        self.directory = directory
        self.autoCleanup = autoCleanup

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Load existing resume data into cache
        for data in ResumeData.loadAll(from: directory) {
            cache[data.downloadId] = data
        }

        // Clean up expired data
        if autoCleanup {
            let deleted = ResumeData.cleanupExpired(in: directory)
            if deleted > 0 {
                // Remove deleted items from cache
                cache = cache.filter { $0.value.isValid }
            }
        }
    }

    /// Saves resume data.
    ///
    /// - Parameter resumeData: The data to save.
    /// - Throws: File operation errors.
    public func save(_ resumeData: ResumeData) throws {
        cache[resumeData.downloadId] = resumeData
        try resumeData.save(to: directory)
    }

    /// Loads resume data by ID.
    ///
    /// - Parameter id: The download ID.
    /// - Returns: The resume data if found and valid.
    public func load(id: String) -> ResumeData? {
        if let cached = cache[id], cached.isValid {
            return cached
        }

        // Try loading from disk
        if let loaded = try? ResumeData.load(from: directory, id: id), loaded.isValid {
            cache[id] = loaded
            return loaded
        }

        return nil
    }

    /// Removes resume data.
    ///
    /// - Parameter id: The download ID.
    public func remove(id: String) {
        cache[id] = nil
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(id).resume")
        )
    }

    /// Gets all stored resume data.
    public var all: [ResumeData] {
        Array(cache.values).filter { $0.isValid }
    }

    /// Gets the count of stored resume data.
    public var count: Int {
        cache.values.filter { $0.isValid }.count
    }

    /// Clears all resume data.
    public func clearAll() {
        for id in cache.keys {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent("\(id).resume")
            )
        }
        cache.removeAll()
    }

    /// Performs cleanup of expired data.
    ///
    /// - Returns: Number of cleaned items.
    @discardableResult
    public func cleanup() -> Int {
        let before = cache.count
        cache = cache.filter { $0.value.isValid }
        let deleted = ResumeData.cleanupExpired(in: directory)
        return (before - cache.count) + deleted
    }
}

// MARK: - CustomStringConvertible

extension ResumeData: CustomStringConvertible {

    public var description: String {
        let bytesFormatter = ByteCountFormatter()
        bytesFormatter.countStyle = .file

        var parts: [String] = []
        parts.append("Download: \(downloadId)")
        parts.append("URL: \(originalURL.lastPathComponent)")
        parts.append("Progress: \(bytesFormatter.string(fromByteCount: bytesReceived))")

        if let total = totalBytes {
            parts.append("of \(bytesFormatter.string(fromByteCount: total))")
        }

        parts.append("Age: \(Int(age / 3600))h")
        parts.append("Valid: \(isValid)")

        return parts.joined(separator: " | ")
    }
}
