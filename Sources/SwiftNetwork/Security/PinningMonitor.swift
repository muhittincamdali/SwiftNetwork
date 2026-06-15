import Foundation

/// SwiftNetwork: Certificate Pinning Monitor.
/// 
/// Provides real-time visibility into the SSL/TLS trust evaluation status.
public actor PinningMonitor {
    public static let shared = PinningMonitor()
    
    public enum TrustStatus: Sendable {
        case pending, trusted, untrusted, bypassed
    }
    
    private var statusLog: [String: TrustStatus] = [:]
    
    private init() {}
    
    /// Records the trust evaluation of a specific domain.
    public func record(domain: String, status: TrustStatus) {
        statusLog[domain] = status
        print("🛡️ [SwiftNetwork] Security: \\(domain) is now \\(status)")
    }
    
    public func getStatus(for domain: String) -> TrustStatus {
        return statusLog[domain] ?? .pending
    }
}
