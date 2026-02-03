import Foundation

/// A managed session wrapper providing lifecycle management and delegate handling.
///
/// `NetworkSession` wraps `URLSession` and provides additional functionality
/// for task management, metrics collection, and delegate-based operations.
///
/// ```swift
/// let session = NetworkSession(configuration: .default)
/// let response = try await session.data(for: request)
/// ```
public final class NetworkSession: NSObject, @unchecked Sendable {

    // MARK: - Types

    /// Session task completion information.
    public struct TaskCompletion: Sendable {
        /// The task that completed.
        public let taskIdentifier: Int

        /// The final URL request (after redirects).
        public let currentRequest: URLRequest?

        /// The response received.
        public let response: URLResponse?

        /// The error if the task failed.
        public let error: Error?

        /// Task metrics if available.
        public let metrics: URLSessionTaskMetrics?
    }

    /// Session event types for monitoring.
    public enum SessionEvent: Sendable {
        case taskCreated(Int)
        case taskCompleted(TaskCompletion)
        case taskProgress(taskId: Int, progress: Double)
        case authenticationRequired(taskId: Int, challenge: String)
        case redirected(taskId: Int, from: URL, to: URL)
        case invalidated
    }

    // MARK: - Properties

    /// The underlying URL session.
    public let urlSession: URLSession

    /// The session configuration used.
    public let configuration: NetworkConfiguration

    /// Unique identifier for this session.
    public let identifier: String

    /// Whether the session has been invalidated.
    public private(set) var isInvalidated: Bool = false

    /// Current active task count.
    public var activeTaskCount: Int {
        taskStateLock.withLock { taskStates.count }
    }

    private var taskStates: [Int: TaskState] = [:]
    private let taskStateLock = NSLock()
    private var eventContinuation: AsyncStream<SessionEvent>.Continuation?
    private var taskMetrics: [Int: URLSessionTaskMetrics] = [:]
    private let metricsLock = NSLock()

    // MARK: - Task State

    private final class TaskState {
        var continuation: CheckedContinuation<(Data, URLResponse), Error>?
        var downloadContinuation: CheckedContinuation<(URL, URLResponse), Error>?
        var data: Data = Data()
        var response: URLResponse?
        var metrics: URLSessionTaskMetrics?
        var progress: Double = 0

        init() {}
    }

    // MARK: - Initialization

    /// Creates a new managed network session.
    ///
    /// - Parameters:
    ///   - configuration: The network configuration to use.
    ///   - identifier: Optional unique identifier. Defaults to a UUID.
    public init(
        configuration: NetworkConfiguration = .default,
        identifier: String = UUID().uuidString
    ) {
        self.configuration = configuration
        self.identifier = identifier

        let sessionConfig = configuration.urlSessionConfiguration()
        sessionConfig.identifier = identifier

        // Temporary initialization
        self.urlSession = URLSession.shared

        super.init()

        // Create session with self as delegate
        let session = URLSession(
            configuration: sessionConfig,
            delegate: self,
            delegateQueue: nil
        )

        // Use reflection to set the session (workaround for initialization order)
        let mirror = Mirror(reflecting: self)
        _ = mirror

        // Store the session using associated object pattern
        objc_setAssociatedObject(
            self,
            &AssociatedKeys.session,
            session,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private enum AssociatedKeys {
        static var session: UInt8 = 0
    }

    private var session: URLSession {
        objc_getAssociatedObject(self, &AssociatedKeys.session) as? URLSession ?? urlSession
    }

    deinit {
        invalidate()
    }

    // MARK: - Session Management

    /// Invalidates the session and cancels all outstanding tasks.
    public func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        session.invalidateAndCancel()
        eventContinuation?.yield(.invalidated)
        eventContinuation?.finish()
    }

    /// Invalidates the session after completing outstanding tasks.
    public func finishTasksAndInvalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        session.finishTasksAndInvalidate()
    }

    /// Resets the session, clearing caches and credentials.
    public func reset() async {
        await session.reset()
    }

    /// Flushes pending data and clears transient caches.
    public func flush() async {
        await session.flush()
    }

    // MARK: - Data Tasks

    /// Performs a data request.
    ///
    /// - Parameter request: The URL request to perform.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: Network errors if the request fails.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard !isInvalidated else {
            throw NetworkError.cancelled
        }

        let task = session.dataTask(with: request)
        let taskId = task.taskIdentifier

        return try await withCheckedThrowingContinuation { continuation in
            taskStateLock.withLock {
                let state = TaskState()
                state.continuation = continuation
                taskStates[taskId] = state
            }

            eventContinuation?.yield(.taskCreated(taskId))
            task.resume()
        }
    }

    /// Performs a data request from a URL.
    ///
    /// - Parameter url: The URL to request.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: Network errors if the request fails.
    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }

    // MARK: - Download Tasks

    /// Downloads a file from a URL request.
    ///
    /// - Parameter request: The URL request.
    /// - Returns: A tuple of the temporary file URL and response.
    /// - Throws: Network errors if the download fails.
    public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        guard !isInvalidated else {
            throw NetworkError.cancelled
        }

        let task = session.downloadTask(with: request)
        let taskId = task.taskIdentifier

        return try await withCheckedThrowingContinuation { continuation in
            taskStateLock.withLock {
                let state = TaskState()
                state.downloadContinuation = continuation
                taskStates[taskId] = state
            }

            eventContinuation?.yield(.taskCreated(taskId))
            task.resume()
        }
    }

    /// Downloads a file from a URL.
    ///
    /// - Parameter url: The URL to download.
    /// - Returns: A tuple of the temporary file URL and response.
    /// - Throws: Network errors if the download fails.
    public func download(from url: URL) async throws -> (URL, URLResponse) {
        try await download(for: URLRequest(url: url))
    }

    /// Resumes a download from resume data.
    ///
    /// - Parameter resumeData: The resume data from a previous download.
    /// - Returns: A tuple of the temporary file URL and response.
    /// - Throws: Network errors if the download fails.
    public func download(resumeFrom resumeData: Data) async throws -> (URL, URLResponse) {
        guard !isInvalidated else {
            throw NetworkError.cancelled
        }

        let task = session.downloadTask(withResumeData: resumeData)
        let taskId = task.taskIdentifier

        return try await withCheckedThrowingContinuation { continuation in
            taskStateLock.withLock {
                let state = TaskState()
                state.downloadContinuation = continuation
                taskStates[taskId] = state
            }

            eventContinuation?.yield(.taskCreated(taskId))
            task.resume()
        }
    }

    // MARK: - Upload Tasks

    /// Uploads data to a URL request.
    ///
    /// - Parameters:
    ///   - request: The URL request.
    ///   - data: The data to upload.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: Network errors if the upload fails.
    public func upload(for request: URLRequest, from data: Data) async throws -> (Data, URLResponse) {
        guard !isInvalidated else {
            throw NetworkError.cancelled
        }

        let task = session.uploadTask(with: request, from: data)
        let taskId = task.taskIdentifier

        return try await withCheckedThrowingContinuation { continuation in
            taskStateLock.withLock {
                let state = TaskState()
                state.continuation = continuation
                taskStates[taskId] = state
            }

            eventContinuation?.yield(.taskCreated(taskId))
            task.resume()
        }
    }

    /// Uploads a file to a URL request.
    ///
    /// - Parameters:
    ///   - request: The URL request.
    ///   - fileURL: The file URL to upload.
    /// - Returns: A tuple of the response data and URL response.
    /// - Throws: Network errors if the upload fails.
    public func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> (Data, URLResponse) {
        guard !isInvalidated else {
            throw NetworkError.cancelled
        }

        let task = session.uploadTask(with: request, fromFile: fileURL)
        let taskId = task.taskIdentifier

        return try await withCheckedThrowingContinuation { continuation in
            taskStateLock.withLock {
                let state = TaskState()
                state.continuation = continuation
                taskStates[taskId] = state
            }

            eventContinuation?.yield(.taskCreated(taskId))
            task.resume()
        }
    }

    // MARK: - Task Management

    /// Cancels all outstanding tasks.
    public func cancelAllTasks() {
        session.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    /// Gets all current tasks.
    ///
    /// - Returns: An array of current session tasks.
    public func getAllTasks() async -> [URLSessionTask] {
        await session.allTasks
    }

    /// Gets the metrics for a completed task.
    ///
    /// - Parameter taskIdentifier: The task identifier.
    /// - Returns: The task metrics if available.
    public func metrics(for taskIdentifier: Int) -> URLSessionTaskMetrics? {
        metricsLock.withLock { taskMetrics[taskIdentifier] }
    }

    // MARK: - Event Stream

    /// An async stream of session events for monitoring.
    public var events: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }
}

// MARK: - URLSessionDataDelegate

extension NetworkSession: URLSessionDataDelegate {

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        taskStateLock.withLock {
            taskStates[dataTask.taskIdentifier]?.data.append(data)
        }
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        taskStateLock.withLock {
            taskStates[dataTask.taskIdentifier]?.response = response
        }
        completionHandler(.allow)
    }
}

// MARK: - URLSessionDownloadDelegate

extension NetworkSession: URLSessionDownloadDelegate {

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier

        // Copy file to temp location before it's removed
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.copyItem(at: location, to: tempURL)

            taskStateLock.withLock {
                if let state = taskStates[taskId],
                   let response = downloadTask.response {
                    state.downloadContinuation?.resume(returning: (tempURL, response))
                    taskStates[taskId] = nil
                }
            }
        } catch {
            taskStateLock.withLock {
                if let state = taskStates[taskId] {
                    state.downloadContinuation?.resume(throwing: error)
                    taskStates[taskId] = nil
                }
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        taskStateLock.withLock {
            taskStates[taskId]?.progress = progress
        }

        eventContinuation?.yield(.taskProgress(taskId: taskId, progress: progress))
    }
}

// MARK: - URLSessionTaskDelegate

extension NetworkSession: URLSessionTaskDelegate {

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let taskId = task.taskIdentifier

        let completion = TaskCompletion(
            taskIdentifier: taskId,
            currentRequest: task.currentRequest,
            response: task.response,
            error: error,
            metrics: metricsLock.withLock { taskMetrics[taskId] }
        )

        eventContinuation?.yield(.taskCompleted(completion))

        taskStateLock.withLock {
            guard let state = taskStates[taskId] else { return }

            if let error = error {
                state.continuation?.resume(throwing: error)
                state.downloadContinuation?.resume(throwing: error)
            } else if let response = state.response ?? task.response {
                state.continuation?.resume(returning: (state.data, response))
            } else {
                state.continuation?.resume(throwing: NetworkError.noData)
            }

            taskStates[taskId] = nil
        }

        // Clean up metrics after a delay
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            metricsLock.withLock {
                taskMetrics[taskId] = nil
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        let taskId = task.taskIdentifier
        metricsLock.withLock {
            taskMetrics[taskId] = metrics
        }

        taskStateLock.withLock {
            taskStates[taskId]?.metrics = metrics
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let originalURL = task.originalRequest?.url,
           let newURL = request.url {
            eventContinuation?.yield(.redirected(
                taskId: task.taskIdentifier,
                from: originalURL,
                to: newURL
            ))
        }

        completionHandler(request)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let taskId = task.taskIdentifier
        let progress = totalBytesExpectedToSend > 0
            ? Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            : 0

        taskStateLock.withLock {
            taskStates[taskId]?.progress = progress
        }

        eventContinuation?.yield(.taskProgress(taskId: taskId, progress: progress))
    }
}

// MARK: - URLSessionDelegate

extension NetworkSession: URLSessionDelegate {

    public func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: Error?
    ) {
        isInvalidated = true
        eventContinuation?.yield(.invalidated)
        eventContinuation?.finish()
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Background session completed all events
    }
}
