import Foundation

/// An async/await WebSocket client with automatic reconnection support.
///
/// ```swift
/// let ws = WebSocketClient(url: URL(string: "wss://echo.example.com/ws")!)
/// try await ws.connect()
///
/// try await ws.send(text: "Hello!")
///
/// for try await message in ws.messages {
///     switch message {
///     case .text(let string):
///         print("Received: \(string)")
///     case .data(let data):
///         print("Received \(data.count) bytes")
///     }
/// }
/// ```
public final class WebSocketClient: @unchecked Sendable {

    // MARK: - Types

    /// A message received from the WebSocket.
    public enum Message: Sendable {
        /// A text message.
        case text(String)
        /// A binary data message.
        case data(Data)
    }

    /// The current connection state.
    public enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }

    // MARK: - Properties

    /// The WebSocket server URL.
    public let url: URL

    /// Additional headers to include in the handshake.
    public let headers: [String: String]

    /// Whether automatic reconnection is enabled.
    public let autoReconnect: Bool

    /// Maximum number of reconnection attempts.
    public let maxReconnectAttempts: Int

    /// Base delay between reconnection attempts in seconds.
    public let reconnectBaseDelay: TimeInterval

    /// The current connection state.
    public private(set) var state: State = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    private var messageContinuation: AsyncThrowingStream<Message, Error>.Continuation?
    private var reconnectAttempts = 0
    private var receiveTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a new WebSocket client.
    ///
    /// - Parameters:
    ///   - url: The WebSocket server URL.
    ///   - headers: Additional handshake headers. Defaults to empty.
    ///   - autoReconnect: Whether to reconnect automatically. Defaults to `true`.
    ///   - maxReconnectAttempts: Maximum reconnect tries. Defaults to 5.
    ///   - reconnectBaseDelay: Base delay for reconnection backoff. Defaults to 1.0 seconds.
    ///   - session: The URL session to use. Defaults to `.shared`.
    public init(
        url: URL,
        headers: [String: String] = [:],
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 5,
        reconnectBaseDelay: TimeInterval = 1.0,
        session: URLSession = .shared
    ) {
        self.url = url
        self.headers = headers
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBaseDelay = reconnectBaseDelay
        self.session = session
    }

    // MARK: - Connection

    /// Opens the WebSocket connection.
    ///
    /// - Throws: If the connection cannot be established.
    public func connect() async throws {
        state = .connecting
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = session.webSocketTask(with: request)
        task.resume()
        webSocketTask = task
        state = .connected
        reconnectAttempts = 0
    }

    /// Closes the WebSocket connection gracefully.
    ///
    /// - Parameters:
    ///   - closeCode: The close code. Defaults to `.normalClosure`.
    ///   - reason: Optional close reason data.
    public func disconnect(
        closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure,
        reason: Data? = nil
    ) {
        state = .disconnecting
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: closeCode, reason: reason)
        webSocketTask = nil
        messageContinuation?.finish()
        messageContinuation = nil
        state = .disconnected
    }

    // MARK: - Sending

    /// Sends a text message.
    ///
    /// - Parameter text: The text string to send.
    /// - Throws: If the message cannot be sent.
    public func send(text: String) async throws {
        guard let task = webSocketTask else {
            throw NetworkError.noConnection
        }
        try await task.send(.string(text))
    }

    /// Sends binary data.
    ///
    /// - Parameter data: The data to send.
    /// - Throws: If the message cannot be sent.
    public func send(data: Data) async throws {
        guard let task = webSocketTask else {
            throw NetworkError.noConnection
        }
        try await task.send(.data(data))
    }

    /// Sends an encodable value as JSON text.
    ///
    /// - Parameters:
    ///   - value: The encodable value.
    ///   - encoder: The JSON encoder. Defaults to a standard instance.
    /// - Throws: If encoding or sending fails.
    public func send<T: Encodable>(_ value: T, encoder: JSONEncoder = .init()) async throws {
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NetworkError.noData
        }
        try await send(text: text)
    }

    // MARK: - Receiving

    /// An async stream of incoming messages.
    ///
    /// Iterate over this stream to receive messages as they arrive:
    /// ```swift
    /// for try await message in ws.messages {
    ///     // handle message
    /// }
    /// ```
    public var messages: AsyncThrowingStream<Message, Error> {
        AsyncThrowingStream { continuation in
            self.messageContinuation = continuation
            self.receiveTask = Task { [weak self] in
                guard let self else { return }
                await self.receiveLoop()
            }

            continuation.onTermination = { [weak self] _ in
                self?.receiveTask?.cancel()
            }
        }
    }

    // MARK: - Private

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let task = webSocketTask else { break }

            do {
                let wsMessage = try await task.receive()
                let message: Message = switch wsMessage {
                case .string(let text): .text(text)
                case .data(let data): .data(data)
                @unknown default: .data(Data())
                }
                messageContinuation?.yield(message)
            } catch {
                messageContinuation?.finish(throwing: error)
                if autoReconnect {
                    await attemptReconnect()
                }
                break
            }
        }
    }

    private func attemptReconnect() async {
        guard reconnectAttempts < maxReconnectAttempts else {
            state = .disconnected
            return
        }

        reconnectAttempts += 1
        let delay = reconnectBaseDelay * pow(2.0, Double(reconnectAttempts - 1))

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            try await connect()
        } catch {
            await attemptReconnect()
        }
    }
}
