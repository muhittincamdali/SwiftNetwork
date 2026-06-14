import Foundation

/// SwiftNetwork: High-performance WebSocket Multiplexer
public actor WebSocketMultiplexer {
    public init() {}
    public func subscribe(channel: String) async -> AsyncStream<Data> {
        return AsyncStream { continuation in }
    }
}
