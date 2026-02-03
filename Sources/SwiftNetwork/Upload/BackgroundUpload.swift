import Foundation

/// Manages background uploads that continue when the app is suspended.
///
/// `BackgroundUploadManager` uses background URLSession configurations
/// to ensure uploads complete even when the app isn't in the foreground.
///
/// ```swift
/// let manager = BackgroundUploadManager(identifier: "com.app.uploads")
///
/// let uploadId = try await manager.scheduleUpload(
///     from: localFileURL,
///     to: serverURL,
///     contentType: "image/jpeg"
/// )
///
/// // Handle completion in AppDelegate
/// func application(_ application: UIApplication,
///     handleEventsForBackgroundURLSession identifier: String,
///     completionHandler: @escaping () -> Void) {
///     BackgroundUploadManager.handleBackgroundEvents(
///         identifier: identifier,
///         completionHandler: completionHandler
///     )
/// }
/// ```
public final class BackgroundUploadManager: NSObject, @unchecked Sendable {

    // MARK: - Types

    /// Background upload status.
    public enum UploadStatus: Sendable {
        case pending
        case uploading(progress: Double)
        case completed(response: Data?)
        case failed(Error)
    }

    /// Upload record for tracking.
    public struct UploadRecord: Codable, Sendable {
        public let id: String
        public let sourceURL: URL
        public let destinationURL: URL
        public let contentType: String?
        public let createdAt: Date
        public var completedAt: Date?
        public var error: String?
    }

    // MARK: - Static Properties

    /// Shared instances by identifier.
    private nonisolated(unsafe) static var managers: [String: BackgroundUploadManager] = [:]
    private static let managersLock = NSLock()

    /// Background completion handlers.
    private nonisolated(unsafe) static var completionHandlers: [String: () -> Void] = [:]
    private static let handlersLock = NSLock()

    // MARK: - Properties

    /// Session identifier.
    public let identifier: String

    /// The background URLSession.
    public let session: URLSession

    /// Active upload tasks.
    private var activeTasks: [Int: String] = [:]

    /// Upload status by ID.
    private var uploadStatus: [String: UploadStatus] = [:]

    /// Upload records.
    private var records: [String: UploadRecord] = [:]

    /// Status observers.
    private var observers: [String: (UploadStatus) -> Void] = [:]

    /// Lock for thread safety.
    private let lock = NSLock()

    /// Storage directory for records.
    private let storageDirectory: URL

    // MARK: - Initialization

    /// Creates a background upload manager.
    ///
    /// - Parameters:
    ///   - identifier: Unique identifier for this manager.
    ///   - storageDirectory: Directory for persisting state.
    public init(
        identifier: String,
        storageDirectory: URL? = nil
    ) {
        self.identifier = identifier

        // Set up storage directory
        if let storage = storageDirectory {
            self.storageDirectory = storage
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.storageDirectory = caches.appendingPathComponent("BackgroundUploads/\(identifier)")
        }

        // Create storage directory
        try? FileManager.default.createDirectory(
            at: self.storageDirectory,
            withIntermediateDirectories: true
        )

        // Configure background session
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.shouldUseExtendedBackgroundIdleMode = true

        // Temporary initialization
        self.session = URLSession.shared

        super.init()

        // Create session with delegate
        let backgroundSession = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )

        // Store reference using associated object
        objc_setAssociatedObject(
            self,
            &AssociatedKeys.session,
            backgroundSession,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        // Register this manager
        Self.managersLock.withLock {
            Self.managers[identifier] = self
        }

        // Load persisted records
        loadRecords()
    }

    private enum AssociatedKeys {
        static var session: UInt8 = 0
    }

    private var backgroundSession: URLSession {
        objc_getAssociatedObject(self, &AssociatedKeys.session) as? URLSession ?? session
    }

    // MARK: - Public API

    /// Schedules a background upload.
    ///
    /// - Parameters:
    ///   - sourceURL: Local file URL to upload.
    ///   - destinationURL: Server URL.
    ///   - contentType: Content type header.
    ///   - headers: Additional headers.
    /// - Returns: The upload ID.
    /// - Throws: If the file doesn't exist.
    public func scheduleUpload(
        from sourceURL: URL,
        to destinationURL: URL,
        contentType: String? = nil,
        headers: [String: String] = [:]
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BackgroundUploadError.fileNotFound(sourceURL)
        }

        let uploadId = UUID().uuidString

        var request = URLRequest(url: destinationURL)
        request.httpMethod = "POST"

        if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = backgroundSession.uploadTask(with: request, fromFile: sourceURL)

        lock.withLock {
            activeTasks[task.taskIdentifier] = uploadId
            uploadStatus[uploadId] = .pending

            let record = UploadRecord(
                id: uploadId,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                contentType: contentType,
                createdAt: Date()
            )
            records[uploadId] = record
        }

        saveRecords()
        task.resume()

        return uploadId
    }

    /// Gets the status of an upload.
    ///
    /// - Parameter id: The upload ID.
    /// - Returns: The current status.
    public func status(for id: String) -> UploadStatus? {
        lock.withLock { uploadStatus[id] }
    }

    /// Observes status changes for an upload.
    ///
    /// - Parameters:
    ///   - id: The upload ID.
    ///   - observer: The observer callback.
    public func observe(id: String, observer: @escaping (UploadStatus) -> Void) {
        lock.withLock {
            observers[id] = observer
            if let status = uploadStatus[id] {
                observer(status)
            }
        }
    }

    /// Removes a status observer.
    ///
    /// - Parameter id: The upload ID.
    public func removeObserver(for id: String) {
        lock.withLock {
            observers[id] = nil
        }
    }

    /// Gets all upload records.
    public func allRecords() -> [UploadRecord] {
        lock.withLock { Array(records.values) }
    }

    /// Cancels an upload.
    ///
    /// - Parameter id: The upload ID.
    public func cancel(id: String) {
        backgroundSession.getAllTasks { tasks in
            self.lock.withLock {
                for task in tasks {
                    if self.activeTasks[task.taskIdentifier] == id {
                        task.cancel()
                        self.uploadStatus[id] = .failed(BackgroundUploadError.cancelled)
                        break
                    }
                }
            }
        }
    }

    /// Cancels all uploads.
    public func cancelAll() {
        backgroundSession.invalidateAndCancel()
    }

    // MARK: - Static Methods

    /// Handles background session events.
    ///
    /// Call this from `handleEventsForBackgroundURLSession` in AppDelegate.
    ///
    /// - Parameters:
    ///   - identifier: The session identifier.
    ///   - completionHandler: The completion handler to call.
    public static func handleBackgroundEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        handlersLock.withLock {
            completionHandlers[identifier] = completionHandler
        }

        // Ensure manager exists
        managersLock.withLock {
            if managers[identifier] == nil {
                _ = BackgroundUploadManager(identifier: identifier)
            }
        }
    }

    // MARK: - Persistence

    private func loadRecords() {
        let fileURL = storageDirectory.appendingPathComponent("records.json")

        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([String: UploadRecord].self, from: data) else {
            return
        }

        lock.withLock {
            records = loaded
        }
    }

    private func saveRecords() {
        let fileURL = storageDirectory.appendingPathComponent("records.json")

        lock.withLock {
            guard let data = try? JSONEncoder().encode(records) else { return }
            try? data.write(to: fileURL)
        }
    }

    private func notifyObserver(id: String, status: UploadStatus) {
        let observer = lock.withLock { observers[id] }
        observer?(status)
    }
}

// MARK: - URLSessionDelegate

extension BackgroundUploadManager: URLSessionDelegate {

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Self.handlersLock.withLock {
            let handler = Self.completionHandlers[identifier]
            Self.completionHandlers[identifier] = nil

            DispatchQueue.main.async {
                handler?()
            }
        }
    }
}

// MARK: - URLSessionTaskDelegate

extension BackgroundUploadManager: URLSessionTaskDelegate {

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let uploadId = lock.withLock({ activeTasks[task.taskIdentifier] }) else { return }

        let progress = totalBytesExpectedToSend > 0
            ? Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            : 0

        lock.withLock {
            uploadStatus[uploadId] = .uploading(progress: progress)
        }

        notifyObserver(id: uploadId, status: .uploading(progress: progress))
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let uploadId = lock.withLock({ activeTasks.removeValue(forKey: task.taskIdentifier) }) else {
            return
        }

        let status: UploadStatus
        if let error = error {
            status = .failed(error)
            lock.withLock {
                records[uploadId]?.error = error.localizedDescription
            }
        } else {
            status = .completed(response: nil)
            lock.withLock {
                records[uploadId]?.completedAt = Date()
            }
        }

        lock.withLock {
            uploadStatus[uploadId] = status
        }

        saveRecords()
        notifyObserver(id: uploadId, status: status)
    }
}

// MARK: - URLSessionDataDelegate

extension BackgroundUploadManager: URLSessionDataDelegate {

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let uploadId = lock.withLock({ activeTasks[dataTask.taskIdentifier] }) else { return }

        lock.withLock {
            uploadStatus[uploadId] = .completed(response: data)
        }

        notifyObserver(id: uploadId, status: .completed(response: data))
    }
}

// MARK: - Errors

/// Errors specific to background uploads.
public enum BackgroundUploadError: Error, Sendable {
    case fileNotFound(URL)
    case cancelled
    case sessionInvalidated
}

extension BackgroundUploadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .cancelled:
            return "Upload was cancelled"
        case .sessionInvalidated:
            return "Background session was invalidated"
        }
    }
}
