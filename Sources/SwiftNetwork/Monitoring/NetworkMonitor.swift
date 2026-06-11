import Foundation
import Network

/// Monitors network connectivity and conditions.
///
/// `NetworkMonitor` provides real-time updates about network availability,
/// connection type, and path characteristics.
///
/// ```swift
/// let monitor = NetworkMonitor()
/// await monitor.start()
///
/// for await status in monitor.statusStream {
///     print("Network: \(status.isConnected ? "Connected" : "Disconnected")")
///     print("Type: \(status.connectionType)")
/// }
/// ```
public final class NetworkMonitor: Sendable {

    // MARK: - Types
    // ... (rest of types)

    /// Network connection type.
    public enum ConnectionType: String, Sendable {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case wired = "Wired"
        case loopback = "Loopback"
        case other = "Other"
        case none = "None"
    }

    /// Network status information.
    public struct NetworkStatus: Sendable {
        /// Whether the network is reachable.
        public let isConnected: Bool

        /// The connection type.
        public let connectionType: ConnectionType

        /// Whether the connection is expensive (e.g., cellular).
        public let isExpensive: Bool

        /// Whether the connection is constrained (e.g., Low Data Mode).
        public let isConstrained: Bool

        /// Whether the path supports DNS.
        public let supportsDNS: Bool

        /// Whether the path supports IPv4.
        public let supportsIPv4: Bool

        /// Whether the path supports IPv6.
        public let supportsIPv6: Bool

        /// The network interface name.
        public let interfaceName: String?

        /// Timestamp of this status.
        public let timestamp: Date

        /// Creates a disconnected status.
        public static let disconnected = NetworkStatus(
            isConnected: false,
            connectionType: .none,
            isExpensive: false,
            isConstrained: false,
            supportsDNS: false,
            supportsIPv4: false,
            supportsIPv6: false,
            interfaceName: nil,
            timestamp: Date()
        )
    }

    /// Network event types.
    public enum NetworkEvent: Sendable {
        case becameConnected(NetworkStatus)
        case becameDisconnected
        case connectionTypeChanged(from: ConnectionType, to: ConnectionType)
        case constraintChanged(isConstrained: Bool)
    }

    // MARK: - Properties

    /// The underlying NWPathMonitor.
    private let pathMonitor: NWPathMonitor

    /// The dispatch queue for monitoring.
    private let queue: DispatchQueue

    /// Current network status.
    private let _currentStatus = Locked(NetworkStatus.disconnected)
    public var currentStatus: NetworkStatus { _currentStatus.withLock { $0 } }

    /// Status stream continuation.
    private let statusContinuation = Locked<AsyncStream<NetworkStatus>.Continuation?>(nil)

    /// Event stream continuation.
    private let eventContinuation = Locked<AsyncStream<NetworkEvent>.Continuation?>(nil)

    /// Whether monitoring is active.
    private let _isMonitoring = Locked(false)
    public var isMonitoring: Bool { _isMonitoring.withLock { $0 } }

    /// Required interface type (nil for any).
    public let requiredInterfaceType: NWInterface.InterfaceType?

    // MARK: - Initialization

    /// Creates a network monitor.
    ///
    /// - Parameter requiredInterfaceType: Specific interface to monitor, or nil for all.
    public init(requiredInterfaceType: NWInterface.InterfaceType? = nil) {
        self.requiredInterfaceType = requiredInterfaceType

        if let interfaceType = requiredInterfaceType {
            self.pathMonitor = NWPathMonitor(requiredInterfaceType: interfaceType)
        } else {
            self.pathMonitor = NWPathMonitor()
        }

        self.queue = DispatchQueue(label: "com.swiftnetwork.monitor", qos: .utility)
    }

    deinit {
        stop()
    }

    // MARK: - Monitoring Control

    /// Starts network monitoring.
    public func start() async {
        guard _isMonitoring.withLock({ monitoring in
            if monitoring { return true }
            monitoring = true
            return false
        }) == false else { return }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }

        pathMonitor.start(queue: queue)
    }

    /// Stops network monitoring.
    public func stop() {
        guard _isMonitoring.withLock({ monitoring in
            if !monitoring { return false }
            monitoring = false
            return true
        }) else { return }

        pathMonitor.cancel()

        statusContinuation.withLock { $0?.finish() }
        eventContinuation.withLock { $0?.finish() }
    }

    // MARK: - Status Stream

    /// An async stream of network status updates.
    public var statusStream: AsyncStream<NetworkStatus> {
        AsyncStream { continuation in
            self.statusContinuation.withLock { $0 = continuation }

            // Emit current status immediately
            continuation.yield(currentStatus)

            continuation.onTermination = { [weak self] _ in
                self?.statusContinuation.withLock { $0 = nil }
            }
        }
    }

    /// An async stream of network events.
    public var eventStream: AsyncStream<NetworkEvent> {
        AsyncStream { continuation in
            self.eventContinuation.withLock { $0 = continuation }

            continuation.onTermination = { [weak self] _ in
                self?.eventContinuation.withLock { $0 = nil }
            }
        }
    }

    // MARK: - Path Handling

    private func handlePathUpdate(_ path: NWPath) {
        let connectionType = determineConnectionType(path)
        let interfaceName = path.availableInterfaces.first?.name

        let newStatus = NetworkStatus(
            isConnected: path.status == .satisfied,
            connectionType: connectionType,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            supportsDNS: path.supportsDNS,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6,
            interfaceName: interfaceName,
            timestamp: Date()
        )

        let previousStatus = _currentStatus.withLock {
            let old = $0
            $0 = newStatus
            return old
        }

        // Emit status update
        statusContinuation.withLock { $0?.yield(newStatus) }

        // Emit events
        emitEvents(previous: previousStatus, current: newStatus)
    }

    private func determineConnectionType(_ path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else { return .none }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wired
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else {
            return .other
        }
    }

    private func emitEvents(previous: NetworkStatus, current: NetworkStatus) {
        // Connection state changes
        if !previous.isConnected && current.isConnected {
            eventContinuation.withLock { $0?.yield(.becameConnected(current)) }
        } else if previous.isConnected && !current.isConnected {
            eventContinuation.withLock { $0?.yield(.becameDisconnected) }
        }

        // Connection type changes
        if previous.connectionType != current.connectionType && current.isConnected {
            eventContinuation.withLock { $0?.yield(.connectionTypeChanged(
                from: previous.connectionType,
                to: current.connectionType
            )) }
        }

        // Constraint changes
        if previous.isConstrained != current.isConstrained {
            eventContinuation.withLock { $0?.yield(.constraintChanged(isConstrained: current.isConstrained)) }
        }
    }

    // MARK: - Convenience Methods

    /// Whether the network is currently connected.
    public var isConnected: Bool {
        _currentStatus.withLock { $0.isConnected }
    }

    /// Whether the current connection is WiFi.
    public var isOnWiFi: Bool {
        _currentStatus.withLock { $0.connectionType == .wifi }
    }

    /// Whether the current connection is cellular.
    public var isOnCellular: Bool {
        _currentStatus.withLock { $0.connectionType == .cellular }
    }

    /// Whether the current connection is expensive.
    public var isExpensive: Bool {
        _currentStatus.withLock { $0.isExpensive }
    }

    /// Whether the current connection is constrained.
    public var isConstrained: Bool {
        _currentStatus.withLock { $0.isConstrained }
    }

    /// Waits for the network to become available.
    ///
    /// - Parameter timeout: Maximum time to wait.
    /// - Returns: True if network became available, false if timed out.
    public func waitForConnection(timeout: TimeInterval = 30) async -> Bool {
        if isConnected { return true }

        return await withCheckedContinuation { continuation in
            Task {
                let deadline = Date().addingTimeInterval(timeout)

                for await status in statusStream {
                    if status.isConnected {
                        continuation.resume(returning: true)
                        return
                    }

                    if Date() > deadline {
                        continuation.resume(returning: false)
                        return
                    }
                }

                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - NetworkStatus Extensions

extension NetworkMonitor.NetworkStatus: CustomStringConvertible {

    public var description: String {
        if isConnected {
            var parts = [connectionType.rawValue]

            if isExpensive {
                parts.append("Expensive")
            }

            if isConstrained {
                parts.append("Constrained")
            }

            if let name = interfaceName {
                parts.append("(\(name))")
            }

            return parts.joined(separator: ", ")
        } else {
            return "Disconnected"
        }
    }
}

// MARK: - Reachability Helper

/// Simple reachability checker for one-off checks.
public struct Reachability: Sendable {

    /// Checks if a host is reachable.
    ///
    /// - Parameters:
    ///   - host: The host to check.
    ///   - port: The port. Defaults to 80.
    ///   - timeout: Connection timeout.
    /// - Returns: True if reachable.
    public static func canReach(
        host: String,
        port: UInt16 = 80,
        timeout: TimeInterval = 10
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!
            )

            let connection = NWConnection(to: endpoint, using: .tcp)
            var hasResumed = false

            connection.stateUpdateHandler = { state in
                guard !hasResumed else { return }

                switch state {
                case .ready:
                    hasResumed = true
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    hasResumed = true
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard !hasResumed else { return }
                hasResumed = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }

    /// Checks if the internet is reachable.
    ///
    /// - Returns: True if internet is reachable.
    public static func isInternetReachable() async -> Bool {
        // Try common reliable hosts
        let hosts = ["1.1.1.1", "8.8.8.8", "apple.com"]

        for host in hosts {
            if await canReach(host: host, timeout: 5) {
                return true
            }
        }

        return false
    }
}
