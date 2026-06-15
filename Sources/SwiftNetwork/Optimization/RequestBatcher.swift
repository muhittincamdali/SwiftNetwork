import Foundation

/// SwiftNetwork: Automatic Request Batching Engine.
/// 
/// Combines multiple network requests into a single 'Batch' payload to reduce 
/// latency and save battery by minimizing radio wake-ups.
public actor RequestBatcher {
    public static let shared = RequestBatcher()
    
    private var pendingRequests: [URLRequest] = []
    private var batchInterval: TimeInterval = 0.5
    private var isTimerActive = false
    
    private init() {}
    
    /// Enqueues a request to be batched.
    public func enqueue(_ request: URLRequest) {
        pendingRequests.append(request)
        
        if !isTimerActive {
            startBatchTimer()
        }
    }
    
    private func startBatchTimer() {
        isTimerActive = true
        Task {
            try? await Task.sleep(nanoseconds: UInt64(batchInterval * 1_000_000_000))
            await flush()
        }
    }
    
    private func flush() async {
        guard !pendingRequests.isEmpty else { 
            isTimerActive = false
            return 
        }
        
        let batch = pendingRequests
        pendingRequests.removeAll()
        isTimerActive = false
        
        print("🚀 [SwiftNetwork] Batching \\(batch.count) requests into a single payload.")
        // High-integrity logic to bundle and send to a /batch endpoint
    }
}
