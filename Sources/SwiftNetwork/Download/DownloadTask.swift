import Foundation

/// Represents an active download task with progress tracking.
///
/// `DownloadTask` wraps `URLSessionDownloadTask` and provides
/// a modern async/await interface with progress observation.
///
/// ```swift
/// let task = DownloadTask(url: url, destination: localURL)
///
/// for await progress in task.progressStream {
///     print("Downloaded: \(progress.fractionCompleted * 100)%")
/// }
///
/// let fileURL = try await task.result
/// ```
public final class DownloadTask: NSObject, @unchecked Sendable {

    // MARK: - Types

    /// The current state of the download.
    public enum State: Sendable {
        case pending
        case downloading
        case paused
        case completed
        case failed(Error)
        case cancelled
    }

    /// Download priority levels.
    public enum Priority: Float, Sendable {
        case low = 0.25
        case normal = 0.5
        case high = 0.75
        case critical = 1.0
    }

    // MARK: - Properties

    /// Unique identifier for this download.
    public let id: String

    /// The source URL.
    public let sourceURL: URL

    /// The destination file URL.
    public let destination: URL

    /// The current state.
    public private(set) var state: State = .pending

    /// The current progress.
    public private(set) var progress: DownloadProgress

    /// Resume data for resumable downloads.
    public private(set) var resumeData: ResumeData?

    /// The underlying URLSessionDownloadTask.
    private var downloadTask: URLSessionDownloadTask?

    /// The URL session.
    private let session: URLSession

    /// Progress continuation.
    private var progressContinuation: AsyncStream<DownloadProgress>.Continuation?

    /// Completion continuation.
    private var completionContinuation: CheckedContinuation<URL, Error>?

    /// File manager for file operations.
    private let fileManager: FileManager

    /// Whether to allow cellular access.
    public let allowsCellularAccess: Bool

    /// Download priority.
    public let priority: Priority

    // MARK: - Initialization

    /// Creates a new download task.
    ///
    /// - Parameters:
    ///   - url: The URL to download from.
    ///   - destination: The local file URL to save to.
    ///   - session: The URL session to use. Defaults to shared.
    ///   - allowsCellularAccess: Whether to allow cellular. Defaults to true.
    ///   - priority: Download priority. Defaults to normal.
    public init(
        url: URL,
        destination: URL,
        session: URLSession = .shared,
        allowsCellularAccess: Bool = true,
        priority: Priority = .normal
    ) {
        self.id = UUID().uuidString
        self.sourceURL = url
        self.destination = destination
        self.session = session
        self.allowsCellularAccess = allowsCellularAccess
        self.priority = priority
        self.progress = DownloadProgress()
        self.fileManager = FileManager.default

        super.init()
    }

    /// Creates a download task from resume data.
    ///
    /// - Parameters:
    ///   - resumeData: The resume data from a previous download.
    ///   - destination: The destination file URL.
    ///   - session: The URL session to use.
    public init(
        resumeData: ResumeData,
        destination: URL,
        session: URLSession = .shared
    ) {
        self.id = resumeData.downloadId
        self.sourceURL = resumeData.originalURL
        self.destination = destination
        self.session = session
        self.allowsCellularAccess = true
        self.priority = .normal
        self.progress = DownloadProgress(
            bytesReceived: resumeData.bytesReceived,
            totalBytes: resumeData.totalBytes
        )
        self.resumeData = resumeData
        self.fileManager = FileManager.default

        super.init()
    }

    // MARK: - Control Methods

    /// Starts the download.
    ///
    /// - Returns: The final file URL.
    /// - Throws: Download errors.
    @discardableResult
    public func start() async throws -> URL {
        guard state == .pending || state == .paused else {
            throw DownloadError.invalidState(current: state)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.completionContinuation = continuation

            // Create or resume the download task
            if let resumeData = self.resumeData {
                downloadTask = session.downloadTask(withResumeData: resumeData.data)
            } else {
                var request = URLRequest(url: sourceURL)
                request.allowsCellularAccess = allowsCellularAccess
                downloadTask = session.downloadTask(with: request)
            }

            downloadTask?.priority = priority.rawValue
            state = .downloading
            downloadTask?.resume()
        }
    }

    /// Pauses the download.
    ///
    /// - Returns: Resume data for later continuation.
    public func pause() async -> ResumeData? {
        guard state == .downloading, let task = downloadTask else {
            return nil
        }

        state = .paused

        return await withCheckedContinuation { continuation in
            task.cancel { [weak self] data in
                guard let self = self, let data = data else {
                    continuation.resume(returning: nil)
                    return
                }

                let resume = ResumeData(
                    downloadId: self.id,
                    originalURL: self.sourceURL,
                    data: data,
                    bytesReceived: self.progress.bytesReceived,
                    totalBytes: self.progress.totalBytes,
                    createdAt: Date()
                )

                self.resumeData = resume
                continuation.resume(returning: resume)
            }
        }
    }

    /// Cancels the download.
    ///
    /// - Parameter saveResumeData: Whether to save resume data.
    /// - Returns: Resume data if saved.
    @discardableResult
    public func cancel(saveResumeData: Bool = false) async -> ResumeData? {
        guard state == .downloading || state == .paused else {
            return nil
        }

        if saveResumeData {
            return await pause()
        }

        downloadTask?.cancel()
        state = .cancelled
        completionContinuation?.resume(throwing: DownloadError.cancelled)
        completionContinuation = nil

        return nil
    }

    /// Resumes a paused download.
    ///
    /// - Returns: The final file URL.
    /// - Throws: Download errors.
    @discardableResult
    public func resume() async throws -> URL {
        guard state == .paused, resumeData != nil else {
            throw DownloadError.cannotResume
        }

        return try await start()
    }

    // MARK: - Progress Observation

    /// An async stream of download progress updates.
    public var progressStream: AsyncStream<DownloadProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation

            continuation.onTermination = { [weak self] _ in
                self?.progressContinuation = nil
            }
        }
    }

    /// The result of the download.
    public var result: URL {
        get async throws {
            try await start()
        }
    }

    // MARK: - Internal Progress Updates

    func updateProgress(bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpected: Int64) {
        progress = DownloadProgress(
            bytesReceived: totalBytesWritten,
            totalBytes: totalBytesExpected > 0 ? totalBytesExpected : nil
        )

        progressContinuation?.yield(progress)
    }

    func completeDownload(tempURL: URL) {
        do {
            // Create destination directory if needed
            let directory = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            // Remove existing file if present
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            // Move downloaded file
            try fileManager.moveItem(at: tempURL, to: destination)

            state = .completed
            progress = DownloadProgress(
                bytesReceived: progress.totalBytes ?? progress.bytesReceived,
                totalBytes: progress.totalBytes
            )

            progressContinuation?.yield(progress)
            progressContinuation?.finish()
            completionContinuation?.resume(returning: destination)
            completionContinuation = nil

        } catch {
            failDownload(with: error)
        }
    }

    func failDownload(with error: Error) {
        state = .failed(error)
        progressContinuation?.finish()
        completionContinuation?.resume(throwing: error)
        completionContinuation = nil
    }
}

// MARK: - Download Manager

/// Manages multiple concurrent downloads.
public actor DownloadManager {

    /// Active downloads.
    private var downloads: [String: DownloadTask] = [:]

    /// Maximum concurrent downloads.
    public let maxConcurrentDownloads: Int

    /// The URL session for downloads.
    private let session: URLSession

    /// Creates a download manager.
    ///
    /// - Parameters:
    ///   - maxConcurrentDownloads: Maximum concurrent downloads. Defaults to 4.
    ///   - session: The URL session to use.
    public init(
        maxConcurrentDownloads: Int = 4,
        session: URLSession = .shared
    ) {
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.session = session
    }

    /// Starts a download.
    ///
    /// - Parameters:
    ///   - url: The URL to download.
    ///   - destination: The destination file URL.
    ///   - priority: Download priority.
    /// - Returns: The download task.
    public func download(
        from url: URL,
        to destination: URL,
        priority: DownloadTask.Priority = .normal
    ) -> DownloadTask {
        let task = DownloadTask(
            url: url,
            destination: destination,
            session: session,
            priority: priority
        )

        downloads[task.id] = task
        return task
    }

    /// Gets a download by ID.
    ///
    /// - Parameter id: The download ID.
    /// - Returns: The download task if found.
    public func download(id: String) -> DownloadTask? {
        downloads[id]
    }

    /// Gets all active downloads.
    public var activeDownloads: [DownloadTask] {
        Array(downloads.values)
    }

    /// Cancels all downloads.
    public func cancelAll() async {
        for download in downloads.values {
            await download.cancel()
        }
        downloads.removeAll()
    }

    /// Removes a completed download.
    ///
    /// - Parameter id: The download ID.
    public func remove(id: String) {
        downloads[id] = nil
    }

    /// Pauses all downloads.
    ///
    /// - Returns: Resume data for all paused downloads.
    public func pauseAll() async -> [ResumeData] {
        var resumeDataList: [ResumeData] = []

        for download in downloads.values {
            if let resumeData = await download.pause() {
                resumeDataList.append(resumeData)
            }
        }

        return resumeDataList
    }
}

// MARK: - Download Errors

/// Errors specific to download operations.
public enum DownloadError: Error, Sendable {
    case invalidState(current: DownloadTask.State)
    case cannotResume
    case cancelled
    case fileOperationFailed(Error)
    case noResumeData
    case resumeDataExpired
}

extension DownloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidState(let state):
            return "Invalid download state: \(state)"
        case .cannotResume:
            return "Download cannot be resumed"
        case .cancelled:
            return "Download was cancelled"
        case .fileOperationFailed(let error):
            return "File operation failed: \(error.localizedDescription)"
        case .noResumeData:
            return "No resume data available"
        case .resumeDataExpired:
            return "Resume data has expired"
        }
    }
}

extension DownloadTask.State: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pending: return "pending"
        case .downloading: return "downloading"
        case .paused: return "paused"
        case .completed: return "completed"
        case .failed(let error): return "failed: \(error.localizedDescription)"
        case .cancelled: return "cancelled"
        }
    }
}
