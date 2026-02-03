import Foundation

/// Represents the progress of a download operation.
///
/// `DownloadProgress` provides comprehensive information about download
/// progress including bytes, speed, and time estimates.
///
/// ```swift
/// for await progress in downloadTask.progressStream {
///     print("Progress: \(progress.percentComplete)%")
///     print("Speed: \(progress.formattedSpeed)")
///     print("ETA: \(progress.formattedTimeRemaining)")
/// }
/// ```
public struct DownloadProgress: Sendable {

    // MARK: - Properties

    /// Bytes received so far.
    public let bytesReceived: Int64

    /// Total bytes expected, if known.
    public let totalBytes: Int64?

    /// When this progress was recorded.
    public let timestamp: Date

    /// Previous progress for speed calculation.
    private let previousProgress: (bytes: Int64, time: Date)?

    // MARK: - Initialization

    /// Creates a new download progress.
    ///
    /// - Parameters:
    ///   - bytesReceived: Bytes received so far.
    ///   - totalBytes: Total expected bytes.
    ///   - timestamp: When this progress was recorded.
    ///   - previousProgress: Previous progress for speed calculation.
    public init(
        bytesReceived: Int64 = 0,
        totalBytes: Int64? = nil,
        timestamp: Date = Date(),
        previousProgress: (bytes: Int64, time: Date)? = nil
    ) {
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.timestamp = timestamp
        self.previousProgress = previousProgress
    }

    // MARK: - Computed Properties

    /// Fraction completed (0.0 to 1.0).
    public var fractionCompleted: Double {
        guard let total = totalBytes, total > 0 else { return 0 }
        return min(1.0, Double(bytesReceived) / Double(total))
    }

    /// Percentage completed (0 to 100).
    public var percentComplete: Int {
        Int(fractionCompleted * 100)
    }

    /// Whether the total size is known.
    public var isTotalKnown: Bool {
        totalBytes != nil
    }

    /// Whether the download is complete.
    public var isComplete: Bool {
        guard let total = totalBytes else { return false }
        return bytesReceived >= total
    }

    /// Bytes remaining to download.
    public var bytesRemaining: Int64? {
        guard let total = totalBytes else { return nil }
        return max(0, total - bytesReceived)
    }

    /// Download speed in bytes per second.
    public var bytesPerSecond: Double {
        guard let prev = previousProgress else { return 0 }
        let byteDiff = Double(bytesReceived - prev.bytes)
        let timeDiff = timestamp.timeIntervalSince(prev.time)
        guard timeDiff > 0 else { return 0 }
        return byteDiff / timeDiff
    }

    /// Estimated time remaining in seconds.
    public var estimatedTimeRemaining: TimeInterval? {
        guard let remaining = bytesRemaining else { return nil }
        let speed = bytesPerSecond
        guard speed > 0 else { return nil }
        return Double(remaining) / speed
    }

    // MARK: - Formatting

    /// Formatted bytes received string.
    public var formattedBytesReceived: String {
        ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
    }

    /// Formatted total bytes string.
    public var formattedTotalBytes: String? {
        guard let total = totalBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    /// Formatted progress string (e.g., "10 MB / 50 MB").
    public var formattedProgress: String {
        if let total = formattedTotalBytes {
            return "\(formattedBytesReceived) / \(total)"
        }
        return formattedBytesReceived
    }

    /// Formatted download speed (e.g., "1.5 MB/s").
    public var formattedSpeed: String {
        let speed = bytesPerSecond
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
        return "\(formatted)/s"
    }

    /// Formatted time remaining (e.g., "5 min 30 sec").
    public var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: remaining)
    }

    // MARK: - Progress Update

    /// Creates a new progress with updated values.
    ///
    /// - Parameters:
    ///   - bytesReceived: New bytes received value.
    ///   - totalBytes: Updated total bytes.
    /// - Returns: A new progress instance.
    public func updated(
        bytesReceived: Int64,
        totalBytes: Int64? = nil
    ) -> DownloadProgress {
        DownloadProgress(
            bytesReceived: bytesReceived,
            totalBytes: totalBytes ?? self.totalBytes,
            timestamp: Date(),
            previousProgress: (bytes: self.bytesReceived, time: self.timestamp)
        )
    }
}

// MARK: - CustomStringConvertible

extension DownloadProgress: CustomStringConvertible {

    public var description: String {
        var parts: [String] = []

        parts.append(formattedProgress)
        parts.append("(\(percentComplete)%)")
        parts.append(formattedSpeed)

        if let timeRemaining = formattedTimeRemaining {
            parts.append("ETA: \(timeRemaining)")
        }

        return parts.joined(separator: " - ")
    }
}

// MARK: - Equatable

extension DownloadProgress: Equatable {

    public static func == (lhs: DownloadProgress, rhs: DownloadProgress) -> Bool {
        lhs.bytesReceived == rhs.bytesReceived &&
        lhs.totalBytes == rhs.totalBytes
    }
}

// MARK: - Progress Aggregator

/// Aggregates progress from multiple downloads.
public struct AggregateDownloadProgress: Sendable {

    /// Individual download progresses.
    public let progresses: [DownloadProgress]

    /// Creates an aggregate progress.
    ///
    /// - Parameter progresses: The individual progresses.
    public init(progresses: [DownloadProgress]) {
        self.progresses = progresses
    }

    /// Total bytes received across all downloads.
    public var totalBytesReceived: Int64 {
        progresses.reduce(0) { $0 + $1.bytesReceived }
    }

    /// Total bytes expected (only if all totals are known).
    public var totalBytesExpected: Int64? {
        guard progresses.allSatisfy({ $0.isTotalKnown }) else { return nil }
        return progresses.compactMap { $0.totalBytes }.reduce(0, +)
    }

    /// Overall fraction completed.
    public var fractionCompleted: Double {
        guard let total = totalBytesExpected, total > 0 else { return 0 }
        return Double(totalBytesReceived) / Double(total)
    }

    /// Number of completed downloads.
    public var completedCount: Int {
        progresses.filter { $0.isComplete }.count
    }

    /// Total number of downloads.
    public var totalCount: Int {
        progresses.count
    }

    /// Combined download speed.
    public var combinedSpeed: Double {
        progresses.reduce(0) { $0 + $1.bytesPerSecond }
    }

    /// Formatted combined speed.
    public var formattedCombinedSpeed: String {
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(combinedSpeed), countStyle: .file)
        return "\(formatted)/s"
    }
}

// MARK: - Progress Observer Protocol

/// Protocol for observing download progress.
public protocol DownloadProgressObserver: AnyObject, Sendable {

    /// Called when progress is updated.
    ///
    /// - Parameters:
    ///   - downloadId: The download identifier.
    ///   - progress: The current progress.
    func downloadProgressUpdated(downloadId: String, progress: DownloadProgress)

    /// Called when a download completes.
    ///
    /// - Parameters:
    ///   - downloadId: The download identifier.
    ///   - fileURL: The downloaded file URL.
    func downloadCompleted(downloadId: String, fileURL: URL)

    /// Called when a download fails.
    ///
    /// - Parameters:
    ///   - downloadId: The download identifier.
    ///   - error: The error that occurred.
    func downloadFailed(downloadId: String, error: Error)
}

// MARK: - Default Implementations

extension DownloadProgressObserver {
    public func downloadProgressUpdated(downloadId: String, progress: DownloadProgress) {}
    public func downloadCompleted(downloadId: String, fileURL: URL) {}
    public func downloadFailed(downloadId: String, error: Error) {}
}
