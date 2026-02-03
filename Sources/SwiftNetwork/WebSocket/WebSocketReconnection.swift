import Foundation

/// Manages automatic reconnection for WebSocket connections.
///
/// `WebSocketReconnectionStrategy` defines how and when to attempt
/// reconnection after a connection is lost.
///
/// ```swift
/// let strategy = WebSocketReconnectionStrategy(
///     maxAttempts: 5,
///     baseDelay: 1.0,
///     maxDelay: 30.0,
///     backoffMultiplier: 2.0
/// )
///
/// let delay = strategy.delay(forAttempt: 3)
/// ```
public struct WebSocketReconnectionStrategy: Sendable {

    // MARK: - Types

    /// Backoff algorithm for calculating delays.
    public enum BackoffType: Sendable {
        /// Constant delay between attempts.
        case constant

        /// Linear increase (baseDelay * attempt).
        case linear

        /// Exponential backoff (baseDelay * multiplier^attempt).
        case exponential

        /// Exponential with jitter.
        case exponentialJitter
    }

    // MARK: - Properties

    /// Maximum number of reconnection attempts.
    public let maxAttempts: Int

    /// Base delay between attempts in seconds.
    public let baseDelay: TimeInterval

    /// Maximum delay cap in seconds.
    public let maxDelay: TimeInterval

    /// Multiplier for exponential backoff.
    public let backoffMultiplier: Double

    /// The backoff algorithm to use.
    public let backoffType: BackoffType

    /// Whether to reconnect on server close.
    public let reconnectOnServerClose: Bool

    /// Close codes that should trigger reconnection.
    public let reconnectableCodes: Set<Int>

    /// Whether to reset attempts on successful connection.
    public let resetOnConnect: Bool

    // MARK: - Initialization

    /// Creates a reconnection strategy.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum attempts. Defaults to 5.
    ///   - baseDelay: Base delay in seconds. Defaults to 1.0.
    ///   - maxDelay: Maximum delay cap. Defaults to 30.0.
    ///   - backoffMultiplier: Exponential multiplier. Defaults to 2.0.
    ///   - backoffType: The backoff algorithm. Defaults to exponential.
    ///   - reconnectOnServerClose: Reconnect on server close. Defaults to true.
    ///   - reconnectableCodes: Close codes to reconnect on.
    ///   - resetOnConnect: Reset attempts on connect. Defaults to true.
    public init(
        maxAttempts: Int = 5,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        backoffMultiplier: Double = 2.0,
        backoffType: BackoffType = .exponential,
        reconnectOnServerClose: Bool = true,
        reconnectableCodes: Set<Int> = [1001, 1006, 1011, 1012, 1013, 1014],
        resetOnConnect: Bool = true
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.backoffType = backoffType
        self.reconnectOnServerClose = reconnectOnServerClose
        self.reconnectableCodes = reconnectableCodes
        self.resetOnConnect = resetOnConnect
    }

    // MARK: - Delay Calculation

    /// Calculates the delay for a given attempt.
    ///
    /// - Parameter attempt: The attempt number (1-based).
    /// - Returns: The delay in seconds.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return baseDelay }

        let calculatedDelay: TimeInterval

        switch backoffType {
        case .constant:
            calculatedDelay = baseDelay

        case .linear:
            calculatedDelay = baseDelay * Double(attempt)

        case .exponential:
            calculatedDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))

        case .exponentialJitter:
            let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
            let jitter = Double.random(in: 0...1) * baseDelay
            calculatedDelay = exponentialDelay + jitter
        }

        return min(calculatedDelay, maxDelay)
    }

    /// Whether reconnection should be attempted for a close code.
    ///
    /// - Parameter code: The WebSocket close code.
    /// - Returns: True if reconnection should be attempted.
    public func shouldReconnect(forCloseCode code: Int) -> Bool {
        // Normal closure (1000) should not reconnect
        if code == 1000 { return false }

        // Check reconnectable codes
        return reconnectableCodes.contains(code) || reconnectOnServerClose
    }

    // MARK: - Presets

    /// Default reconnection strategy.
    public static let `default` = WebSocketReconnectionStrategy()

    /// Aggressive reconnection for critical connections.
    public static let aggressive = WebSocketReconnectionStrategy(
        maxAttempts: 10,
        baseDelay: 0.5,
        maxDelay: 10.0,
        backoffMultiplier: 1.5,
        backoffType: .exponentialJitter
    )

    /// Conservative reconnection for non-critical connections.
    public static let conservative = WebSocketReconnectionStrategy(
        maxAttempts: 3,
        baseDelay: 5.0,
        maxDelay: 60.0,
        backoffMultiplier: 2.0,
        backoffType: .exponential
    )

    /// No reconnection.
    public static let none = WebSocketReconnectionStrategy(
        maxAttempts: 0,
        baseDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1,
        reconnectOnServerClose: false
    )
}

// MARK: - Reconnection Manager

/// Manages the reconnection process for a WebSocket.
public actor WebSocketReconnectionManager {

    // MARK: - Properties

    /// The reconnection strategy.
    public let strategy: WebSocketReconnectionStrategy

    /// Current attempt number.
    public private(set) var currentAttempt: Int = 0

    /// Whether reconnection is in progress.
    public private(set) var isReconnecting: Bool = false

    /// The reconnection task.
    private var reconnectionTask: Task<Void, Never>?

    /// Callback to perform the actual connection.
    private let connectCallback: @Sendable () async throws -> Void

    /// Callback when reconnection succeeds.
    private let onSuccess: (@Sendable () -> Void)?

    /// Callback when reconnection fails.
    private let onFailure: (@Sendable (Error) -> Void)?

    /// Callback for attempt updates.
    private let onAttempt: (@Sendable (Int, TimeInterval) -> Void)?

    // MARK: - Initialization

    /// Creates a reconnection manager.
    ///
    /// - Parameters:
    ///   - strategy: The reconnection strategy.
    ///   - connect: Callback to perform connection.
    ///   - onSuccess: Called when reconnection succeeds.
    ///   - onFailure: Called when all attempts fail.
    ///   - onAttempt: Called before each attempt.
    public init(
        strategy: WebSocketReconnectionStrategy = .default,
        connect: @escaping @Sendable () async throws -> Void,
        onSuccess: (@Sendable () -> Void)? = nil,
        onFailure: (@Sendable (Error) -> Void)? = nil,
        onAttempt: (@Sendable (Int, TimeInterval) -> Void)? = nil
    ) {
        self.strategy = strategy
        self.connectCallback = connect
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        self.onAttempt = onAttempt
    }

    // MARK: - Control Methods

    /// Starts the reconnection process.
    public func startReconnecting() {
        guard !isReconnecting else { return }
        guard strategy.maxAttempts > 0 else { return }

        isReconnecting = true
        currentAttempt = 0

        reconnectionTask = Task {
            await reconnectionLoop()
        }
    }

    /// Stops the reconnection process.
    public func stopReconnecting() {
        isReconnecting = false
        reconnectionTask?.cancel()
        reconnectionTask = nil
    }

    /// Resets the attempt counter.
    public func reset() {
        currentAttempt = 0
    }

    /// Called when connection succeeds.
    public func connectionSucceeded() {
        isReconnecting = false
        reconnectionTask?.cancel()
        reconnectionTask = nil

        if strategy.resetOnConnect {
            currentAttempt = 0
        }

        onSuccess?()
    }

    // MARK: - Private Methods

    private func reconnectionLoop() async {
        while isReconnecting && currentAttempt < strategy.maxAttempts {
            currentAttempt += 1
            let delay = strategy.delay(forAttempt: currentAttempt)

            onAttempt?(currentAttempt, delay)

            // Wait for the delay
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                // Task was cancelled
                return
            }

            guard isReconnecting else { return }

            // Attempt connection
            do {
                try await connectCallback()
                // Connection succeeded
                connectionSucceeded()
                return
            } catch {
                // Connection failed, continue to next attempt
                continue
            }
        }

        // All attempts exhausted
        isReconnecting = false
        onFailure?(ReconnectionError.maxAttemptsExceeded)
    }
}

// MARK: - Reconnection Errors

/// Errors related to WebSocket reconnection.
public enum ReconnectionError: Error, Sendable {
    case maxAttemptsExceeded
    case reconnectionCancelled
    case connectionFailed(Error)
}

extension ReconnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .maxAttemptsExceeded:
            return "Maximum reconnection attempts exceeded"
        case .reconnectionCancelled:
            return "Reconnection was cancelled"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Close Codes

/// Standard WebSocket close codes.
public enum WebSocketCloseCode: Int, Sendable {
    /// Normal closure.
    case normalClosure = 1000

    /// Endpoint going away.
    case goingAway = 1001

    /// Protocol error.
    case protocolError = 1002

    /// Unsupported data.
    case unsupportedData = 1003

    /// No status received.
    case noStatusReceived = 1005

    /// Abnormal closure.
    case abnormalClosure = 1006

    /// Invalid frame payload data.
    case invalidPayload = 1007

    /// Policy violation.
    case policyViolation = 1008

    /// Message too big.
    case messageTooLarge = 1009

    /// Mandatory extension missing.
    case mandatoryExtension = 1010

    /// Internal server error.
    case internalError = 1011

    /// Service restart.
    case serviceRestart = 1012

    /// Try again later.
    case tryAgainLater = 1013

    /// Bad gateway.
    case badGateway = 1014

    /// TLS handshake failure.
    case tlsHandshakeFailure = 1015

    /// Whether this code should trigger reconnection.
    public var shouldReconnect: Bool {
        switch self {
        case .normalClosure:
            return false
        case .goingAway, .abnormalClosure, .serviceRestart, .tryAgainLater, .badGateway:
            return true
        default:
            return false
        }
    }
}
