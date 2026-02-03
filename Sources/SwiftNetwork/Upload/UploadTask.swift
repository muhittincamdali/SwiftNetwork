import Foundation

/// Represents an active upload task with progress tracking.
///
/// `UploadTask` wraps `URLSessionUploadTask` and provides
/// a modern async/await interface with progress observation.
///
/// ```swift
/// let task = UploadTask(
///     url: uploadURL,
///     data: fileData,
///     contentType: "image/jpeg"
/// )
///
/// for await progress in task.progressStream {
///     print("Uploaded: \(progress.percentComplete)%")
/// }
///
/// let response = try await task.result
/// ```
public final class UploadTask: NSObject, @unchecked Sendable {

    // MARK: - Types

    /// The current state of the upload.
    public enum State: Sendable {
        case pending
        case uploading
        case completed
        case failed(Error)
        case cancelled
    }

    /// Upload source type.
    public enum Source: Sendable {
        case data(Data)
        case file(URL)
        case stream(InputStream, length: Int64)
    }

    /// Upload priority levels.
    public enum Priority: Float, Sendable {
        case low = 0.25
        case normal = 0.5
        case high = 0.75
        case critical = 1.0
    }

    // MARK: - Properties

    /// Unique identifier for this upload.
    public let id: String

    /// The upload destination URL.
    public let destinationURL: URL

    /// The upload source.
    public let source: Source

    /// HTTP method for the upload.
    public let httpMethod: String

    /// Content type header.
    public let contentType: String?

    /// Additional headers.
    public let headers: [String: String]

    /// The current state.
    public private(set) var state: State = .pending

    /// The current progress.
    public private(set) var progress: UploadProgress

    /// The underlying URLSessionUploadTask.
    private var uploadTask: URLSessionUploadTask?

    /// The URL session.
    private let session: URLSession

    /// Progress continuation.
    private var progressContinuation: AsyncStream<UploadProgress>.Continuation?

    /// Completion continuation.
    private var completionContinuation: CheckedContinuation<NetworkResponse, Error>?

    /// Response data accumulator.
    private var responseData = Data()

    /// Response object.
    private var httpResponse: HTTPURLResponse?

    /// Upload priority.
    public let priority: Priority

    // MARK: - Initialization

    /// Creates an upload task from data.
    ///
    /// - Parameters:
    ///   - url: The upload destination URL.
    ///   - data: The data to upload.
    ///   - contentType: The content type.
    ///   - method: HTTP method. Defaults to POST.
    ///   - headers: Additional headers.
    ///   - session: URL session to use.
    ///   - priority: Upload priority.
    public init(
        url: URL,
        data: Data,
        contentType: String? = nil,
        method: String = "POST",
        headers: [String: String] = [:],
        session: URLSession = .shared,
        priority: Priority = .normal
    ) {
        self.id = UUID().uuidString
        self.destinationURL = url
        self.source = .data(data)
        self.httpMethod = method
        self.contentType = contentType
        self.headers = headers
        self.session = session
        self.priority = priority
        self.progress = UploadProgress(totalBytes: Int64(data.count))

        super.init()
    }

    /// Creates an upload task from a file.
    ///
    /// - Parameters:
    ///   - url: The upload destination URL.
    ///   - fileURL: The file to upload.
    ///   - contentType: The content type.
    ///   - method: HTTP method.
    ///   - headers: Additional headers.
    ///   - session: URL session to use.
    ///   - priority: Upload priority.
    public init(
        url: URL,
        fileURL: URL,
        contentType: String? = nil,
        method: String = "POST",
        headers: [String: String] = [:],
        session: URLSession = .shared,
        priority: Priority = .normal
    ) {
        self.id = UUID().uuidString
        self.destinationURL = url
        self.source = .file(fileURL)
        self.httpMethod = method
        self.contentType = contentType
        self.headers = headers
        self.session = session
        self.priority = priority

        // Calculate file size
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        self.progress = UploadProgress(totalBytes: fileSize)

        super.init()
    }

    // MARK: - Control Methods

    /// Starts the upload.
    ///
    /// - Returns: The server response.
    /// - Throws: Upload errors.
    @discardableResult
    public func start() async throws -> NetworkResponse {
        guard state == .pending else {
            throw UploadError.invalidState(current: state)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.completionContinuation = continuation

            // Build the request
            var request = URLRequest(url: destinationURL)
            request.httpMethod = httpMethod

            if let contentType = contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }

            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            // Create the upload task
            switch source {
            case .data(let data):
                uploadTask = session.uploadTask(with: request, from: data)
            case .file(let fileURL):
                uploadTask = session.uploadTask(with: request, fromFile: fileURL)
            case .stream:
                // Streams require custom handling
                uploadTask = session.uploadTask(withStreamedRequest: request)
            }

            uploadTask?.priority = priority.rawValue
            state = .uploading
            uploadTask?.resume()
        }
    }

    /// Cancels the upload.
    public func cancel() {
        guard state == .uploading else { return }

        uploadTask?.cancel()
        state = .cancelled
        progressContinuation?.finish()
        completionContinuation?.resume(throwing: UploadError.cancelled)
        completionContinuation = nil
    }

    // MARK: - Progress Observation

    /// An async stream of upload progress updates.
    public var progressStream: AsyncStream<UploadProgress> {
        AsyncStream { continuation in
            self.progressContinuation = continuation

            continuation.onTermination = { [weak self] _ in
                self?.progressContinuation = nil
            }
        }
    }

    /// The result of the upload.
    public var result: NetworkResponse {
        get async throws {
            try await start()
        }
    }

    // MARK: - Internal Updates

    func updateProgress(bytesSent: Int64, totalBytesSent: Int64, totalBytesExpected: Int64) {
        progress = UploadProgress(
            bytesSent: totalBytesSent,
            totalBytes: totalBytesExpected > 0 ? totalBytesExpected : progress.totalBytes
        )

        progressContinuation?.yield(progress)
    }

    func receiveData(_ data: Data) {
        responseData.append(data)
    }

    func receiveResponse(_ response: HTTPURLResponse) {
        httpResponse = response
    }

    func completeUpload() {
        state = .completed

        progress = UploadProgress(
            bytesSent: progress.totalBytes ?? progress.bytesSent,
            totalBytes: progress.totalBytes
        )

        progressContinuation?.yield(progress)
        progressContinuation?.finish()

        let response = NetworkResponse(
            data: responseData,
            statusCode: httpResponse?.statusCode ?? 200,
            headers: (httpResponse?.allHeaderFields as? [String: String]) ?? [:],
            originalRequest: uploadTask?.originalRequest,
            httpResponse: httpResponse
        )

        completionContinuation?.resume(returning: response)
        completionContinuation = nil
    }

    func failUpload(with error: Error) {
        state = .failed(error)
        progressContinuation?.finish()
        completionContinuation?.resume(throwing: error)
        completionContinuation = nil
    }
}

// MARK: - Upload Progress

/// Represents the progress of an upload operation.
public struct UploadProgress: Sendable {

    /// Bytes sent so far.
    public let bytesSent: Int64

    /// Total bytes to send.
    public let totalBytes: Int64?

    /// Timestamp of this progress.
    public let timestamp: Date

    /// Previous progress for speed calculation.
    private let previousProgress: (bytes: Int64, time: Date)?

    /// Creates upload progress.
    public init(
        bytesSent: Int64 = 0,
        totalBytes: Int64? = nil,
        timestamp: Date = Date(),
        previousProgress: (bytes: Int64, time: Date)? = nil
    ) {
        self.bytesSent = bytesSent
        self.totalBytes = totalBytes
        self.timestamp = timestamp
        self.previousProgress = previousProgress
    }

    /// Fraction completed (0.0 to 1.0).
    public var fractionCompleted: Double {
        guard let total = totalBytes, total > 0 else { return 0 }
        return min(1.0, Double(bytesSent) / Double(total))
    }

    /// Percentage completed.
    public var percentComplete: Int {
        Int(fractionCompleted * 100)
    }

    /// Whether the upload is complete.
    public var isComplete: Bool {
        guard let total = totalBytes else { return false }
        return bytesSent >= total
    }

    /// Upload speed in bytes per second.
    public var bytesPerSecond: Double {
        guard let prev = previousProgress else { return 0 }
        let byteDiff = Double(bytesSent - prev.bytes)
        let timeDiff = timestamp.timeIntervalSince(prev.time)
        guard timeDiff > 0 else { return 0 }
        return byteDiff / timeDiff
    }

    /// Formatted progress string.
    public var formattedProgress: String {
        let sent = ByteCountFormatter.string(fromByteCount: bytesSent, countStyle: .file)
        if let total = totalBytes {
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "\(sent) / \(totalStr)"
        }
        return sent
    }

    /// Formatted speed string.
    public var formattedSpeed: String {
        let speed = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
        return "\(speed)/s"
    }

    /// Creates updated progress.
    public func updated(bytesSent: Int64, totalBytes: Int64? = nil) -> UploadProgress {
        UploadProgress(
            bytesSent: bytesSent,
            totalBytes: totalBytes ?? self.totalBytes,
            timestamp: Date(),
            previousProgress: (bytes: self.bytesSent, time: self.timestamp)
        )
    }
}

// MARK: - Upload Manager

/// Manages multiple concurrent uploads.
public actor UploadManager {

    /// Active uploads.
    private var uploads: [String: UploadTask] = [:]

    /// Maximum concurrent uploads.
    public let maxConcurrentUploads: Int

    /// The URL session for uploads.
    private let session: URLSession

    /// Creates an upload manager.
    public init(
        maxConcurrentUploads: Int = 4,
        session: URLSession = .shared
    ) {
        self.maxConcurrentUploads = maxConcurrentUploads
        self.session = session
    }

    /// Creates an upload task.
    public func upload(
        to url: URL,
        data: Data,
        contentType: String? = nil,
        priority: UploadTask.Priority = .normal
    ) -> UploadTask {
        let task = UploadTask(
            url: url,
            data: data,
            contentType: contentType,
            session: session,
            priority: priority
        )

        uploads[task.id] = task
        return task
    }

    /// Creates a file upload task.
    public func upload(
        to url: URL,
        file: URL,
        contentType: String? = nil,
        priority: UploadTask.Priority = .normal
    ) -> UploadTask {
        let task = UploadTask(
            url: url,
            fileURL: file,
            contentType: contentType,
            session: session,
            priority: priority
        )

        uploads[task.id] = task
        return task
    }

    /// Gets an upload by ID.
    public func upload(id: String) -> UploadTask? {
        uploads[id]
    }

    /// Gets all active uploads.
    public var activeUploads: [UploadTask] {
        Array(uploads.values)
    }

    /// Cancels all uploads.
    public func cancelAll() {
        for upload in uploads.values {
            upload.cancel()
        }
        uploads.removeAll()
    }

    /// Removes a completed upload.
    public func remove(id: String) {
        uploads[id] = nil
    }
}

// MARK: - Upload Errors

/// Errors specific to upload operations.
public enum UploadError: Error, Sendable {
    case invalidState(current: UploadTask.State)
    case cancelled
    case fileNotFound
    case fileTooLarge(size: Int64, limit: Int64)
    case invalidContentType
}

extension UploadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidState(let state):
            return "Invalid upload state: \(state)"
        case .cancelled:
            return "Upload was cancelled"
        case .fileNotFound:
            return "Upload file not found"
        case .fileTooLarge(let size, let limit):
            return "File size \(size) exceeds limit \(limit)"
        case .invalidContentType:
            return "Invalid content type for upload"
        }
    }
}

extension UploadTask.State: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pending: return "pending"
        case .uploading: return "uploading"
        case .completed: return "completed"
        case .failed(let error): return "failed: \(error.localizedDescription)"
        case .cancelled: return "cancelled"
        }
    }
}
