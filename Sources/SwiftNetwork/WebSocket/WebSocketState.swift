import Foundation

/// Represents the current state of a WebSocket connection.
///
/// `WebSocketState` provides detailed information about the connection
/// lifecycle including timing and error information.
///
/// ```swift
/// switch client.state {
/// case .connected(let info):
///     print("Connected since \(info.connectedAt)")
/// case .disconnected(let reason):
///     print("Disconnected: \(reason)")
/// case .connecting:
///     print("Connecting...")
/// }
/// ```
public enum WebSocketState: Sendable {

    /// Connection information for connected state.
    public struct ConnectionInfo: Sendable {
        /// When the connection was established.
        public let connectedAt: Date

        /// The negotiated protocol, if any.
        public let subprotocol: String?

        /// The selected extensions.
        public let extensions: [String]

        /// The response headers from the handshake.
        public let handshakeHeaders: [String: String]

        /// Duration since connection in seconds.
        public var connectionDuration: TimeInterval {
            Date().timeIntervalSince(connectedAt)
        }

        /// Creates connection info.
        public init(
            connectedAt: Date = Date(),
            subprotocol: String? = nil,
            extensions: [String] = [],
            handshakeHeaders: [String: String] = [:]
        ) {
            self.connectedAt = connectedAt
            self.subprotocol = subprotocol
            self.extensions = extensions
            self.handshakeHeaders = handshakeHeaders
        }
    }

    /// Disconnection reason.
    public enum DisconnectReason: Sendable, Equatable {
        /// Normal closure.
        case normal

        /// Connection was cancelled.
        case cancelled

        /// Server closed the connection.
        case serverClosed(code: Int, reason: String?)

        /// An error occurred.
        case error(String)

        /// Network connectivity lost.
        case networkLost

        /// Ping timeout.
        case pingTimeout

        /// Description of the reason.
        public var description: String {
            switch self {
            case .normal:
                return "Normal closure"
            case .cancelled:
                return "Connection cancelled"
            case .serverClosed(let code, let reason):
                if let reason = reason {
                    return "Server closed (\(code)): \(reason)"
                }
                return "Server closed (\(code))"
            case .error(let message):
                return "Error: \(message)"
            case .networkLost:
                return "Network connectivity lost"
            case .pingTimeout:
                return "Ping timeout"
            }
        }
    }

    /// Not connected.
    case disconnected(reason: DisconnectReason?)

    /// Connection in progress.
    case connecting

    /// Connected and ready.
    case connected(ConnectionInfo)

    /// Disconnection in progress.
    case disconnecting

    /// Reconnection in progress.
    case reconnecting(attempt: Int, maxAttempts: Int)

    // MARK: - Convenience Properties

    /// Whether the state is connected.
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Whether the state is disconnected.
    public var isDisconnected: Bool {
        if case .disconnected = self { return true }
        return false
    }

    /// Whether the state is connecting or reconnecting.
    public var isConnecting: Bool {
        switch self {
        case .connecting, .reconnecting:
            return true
        default:
            return false
        }
    }

    /// Whether the state is disconnecting.
    public var isDisconnecting: Bool {
        if case .disconnecting = self { return true }
        return false
    }

    /// The connection info if connected.
    public var connectionInfo: ConnectionInfo? {
        if case .connected(let info) = self { return info }
        return nil
    }

    /// The disconnect reason if disconnected.
    public var disconnectReason: DisconnectReason? {
        if case .disconnected(let reason) = self { return reason }
        return nil
    }

    /// The current reconnection attempt if reconnecting.
    public var reconnectAttempt: Int? {
        if case .reconnecting(let attempt, _) = self { return attempt }
        return nil
    }
}

// MARK: - CustomStringConvertible

extension WebSocketState: CustomStringConvertible {

    public var description: String {
        switch self {
        case .disconnected(let reason):
            if let reason = reason {
                return "Disconnected: \(reason.description)"
            }
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected(let info):
            return "Connected (duration: \(Int(info.connectionDuration))s)"
        case .disconnecting:
            return "Disconnecting"
        case .reconnecting(let attempt, let max):
            return "Reconnecting (\(attempt)/\(max))"
        }
    }
}

// MARK: - State Machine

/// State machine for managing WebSocket state transitions.
public actor WebSocketStateMachine {

    /// Current state.
    public private(set) var state: WebSocketState = .disconnected(reason: nil)

    /// State change callbacks.
    private var observers: [UUID: (WebSocketState, WebSocketState) -> Void] = [:]

    /// Creates a state machine.
    public init() {}

    /// Transitions to connecting state.
    ///
    /// - Returns: True if transition was valid.
    @discardableResult
    public func connect() -> Bool {
        guard case .disconnected = state else { return false }
        transition(to: .connecting)
        return true
    }

    /// Transitions to connected state.
    ///
    /// - Parameter info: Connection information.
    /// - Returns: True if transition was valid.
    @discardableResult
    public func connected(info: WebSocketState.ConnectionInfo = .init()) -> Bool {
        guard case .connecting = state else {
            if case .reconnecting = state {
                transition(to: .connected(info))
                return true
            }
            return false
        }
        transition(to: .connected(info))
        return true
    }

    /// Transitions to disconnecting state.
    ///
    /// - Returns: True if transition was valid.
    @discardableResult
    public func disconnect() -> Bool {
        guard case .connected = state else { return false }
        transition(to: .disconnecting)
        return true
    }

    /// Transitions to disconnected state.
    ///
    /// - Parameter reason: The disconnect reason.
    /// - Returns: True if transition was valid.
    @discardableResult
    public func disconnected(reason: WebSocketState.DisconnectReason?) -> Bool {
        transition(to: .disconnected(reason: reason))
        return true
    }

    /// Transitions to reconnecting state.
    ///
    /// - Parameters:
    ///   - attempt: Current attempt number.
    ///   - maxAttempts: Maximum attempts.
    /// - Returns: True if transition was valid.
    @discardableResult
    public func reconnect(attempt: Int, maxAttempts: Int) -> Bool {
        guard case .disconnected = state else {
            if case .reconnecting = state {
                transition(to: .reconnecting(attempt: attempt, maxAttempts: maxAttempts))
                return true
            }
            return false
        }
        transition(to: .reconnecting(attempt: attempt, maxAttempts: maxAttempts))
        return true
    }

    /// Adds a state change observer.
    ///
    /// - Parameter callback: Called when state changes.
    /// - Returns: Observer ID for removal.
    @discardableResult
    public func observe(_ callback: @escaping (WebSocketState, WebSocketState) -> Void) -> UUID {
        let id = UUID()
        observers[id] = callback
        return id
    }

    /// Removes an observer.
    ///
    /// - Parameter id: The observer ID.
    public func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    private func transition(to newState: WebSocketState) {
        let oldState = state
        state = newState

        for callback in observers.values {
            callback(oldState, newState)
        }
    }
}

// MARK: - Connection Statistics

/// Statistics about a WebSocket connection.
public struct WebSocketStatistics: Sendable {

    /// Total messages sent.
    public var messagesSent: Int = 0

    /// Total messages received.
    public var messagesReceived: Int = 0

    /// Total bytes sent.
    public var bytesSent: Int64 = 0

    /// Total bytes received.
    public var bytesReceived: Int64 = 0

    /// Number of pings sent.
    public var pingsSent: Int = 0

    /// Number of pongs received.
    public var pongsReceived: Int = 0

    /// Connection start time.
    public var connectionStartTime: Date?

    /// Number of reconnections.
    public var reconnectionCount: Int = 0

    /// Last error message.
    public var lastError: String?

    /// Creates empty statistics.
    public init() {}

    /// Duration of current connection.
    public var connectionDuration: TimeInterval? {
        guard let start = connectionStartTime else { return nil }
        return Date().timeIntervalSince(start)
    }

    /// Average messages per second.
    public var messagesPerSecond: Double? {
        guard let duration = connectionDuration, duration > 0 else { return nil }
        return Double(messagesReceived + messagesSent) / duration
    }
}
