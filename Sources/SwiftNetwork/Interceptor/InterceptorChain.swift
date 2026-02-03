import Foundation

/// Manages a chain of interceptors for request/response processing.
///
/// `InterceptorChain` provides an ordered pipeline through which all
/// network requests and responses flow, enabling cross-cutting concerns
/// like authentication, logging, and caching.
///
/// ```swift
/// let chain = InterceptorChain()
///     .add(LoggingInterceptor())
///     .add(AuthInterceptor(token: token))
///     .add(RetryInterceptor(maxAttempts: 3))
///
/// let client = NetworkClient(baseURL: url, chain: chain)
/// ```
public final class InterceptorChain: @unchecked Sendable {

    // MARK: - Types

    /// The execution phase of the interceptor chain.
    public enum Phase: Sendable {
        case request
        case response
    }

    /// Context passed through the interceptor chain.
    public struct Context: Sendable {
        /// The current phase of execution.
        public let phase: Phase

        /// The original request before any modifications.
        public let originalRequest: URLRequest

        /// Custom metadata passed through the chain.
        public var metadata: [String: Any] {
            get { _metadata }
            set { _metadata = newValue }
        }

        private var _metadata: [String: Any]

        /// The current attempt number (for retries).
        public let attemptNumber: Int

        /// Creates a new interceptor context.
        public init(
            phase: Phase,
            originalRequest: URLRequest,
            metadata: [String: Any] = [:],
            attemptNumber: Int = 1
        ) {
            self.phase = phase
            self.originalRequest = originalRequest
            self._metadata = metadata
            self.attemptNumber = attemptNumber
        }

        /// Creates a copy with updated metadata.
        public func with(metadata: [String: Any]) -> Context {
            Context(
                phase: phase,
                originalRequest: originalRequest,
                metadata: metadata,
                attemptNumber: attemptNumber
            )
        }
    }

    /// Result of interceptor chain execution.
    public enum ChainResult: Sendable {
        case proceed(URLRequest)
        case shortCircuit(NetworkResponse)
        case fail(Error)
    }

    // MARK: - Properties

    /// The ordered list of interceptors.
    public private(set) var interceptors: [any NetworkInterceptor]

    /// Whether the chain is frozen (no more modifications allowed).
    public private(set) var isFrozen: Bool = false

    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates an empty interceptor chain.
    public init() {
        self.interceptors = []
    }

    /// Creates an interceptor chain with initial interceptors.
    ///
    /// - Parameter interceptors: The initial interceptors.
    public init(_ interceptors: [any NetworkInterceptor]) {
        self.interceptors = interceptors
    }

    /// Creates an interceptor chain from variadic interceptors.
    ///
    /// - Parameter interceptors: The interceptors to add.
    public convenience init(_ interceptors: any NetworkInterceptor...) {
        self.init(interceptors)
    }

    // MARK: - Chain Building

    /// Adds an interceptor to the end of the chain.
    ///
    /// - Parameter interceptor: The interceptor to add.
    /// - Returns: Self for chaining.
    @discardableResult
    public func add(_ interceptor: any NetworkInterceptor) -> InterceptorChain {
        lock.withLock {
            guard !isFrozen else { return }
            interceptors.append(interceptor)
        }
        return self
    }

    /// Adds multiple interceptors to the end of the chain.
    ///
    /// - Parameter newInterceptors: The interceptors to add.
    /// - Returns: Self for chaining.
    @discardableResult
    public func add(_ newInterceptors: [any NetworkInterceptor]) -> InterceptorChain {
        lock.withLock {
            guard !isFrozen else { return }
            interceptors.append(contentsOf: newInterceptors)
        }
        return self
    }

    /// Inserts an interceptor at a specific index.
    ///
    /// - Parameters:
    ///   - interceptor: The interceptor to insert.
    ///   - index: The index to insert at.
    /// - Returns: Self for chaining.
    @discardableResult
    public func insert(_ interceptor: any NetworkInterceptor, at index: Int) -> InterceptorChain {
        lock.withLock {
            guard !isFrozen, index >= 0, index <= interceptors.count else { return }
            interceptors.insert(interceptor, at: index)
        }
        return self
    }

    /// Removes an interceptor at a specific index.
    ///
    /// - Parameter index: The index to remove.
    /// - Returns: The removed interceptor, or nil.
    @discardableResult
    public func remove(at index: Int) -> (any NetworkInterceptor)? {
        lock.withLock {
            guard !isFrozen, index >= 0, index < interceptors.count else { return nil }
            return interceptors.remove(at: index)
        }
    }

    /// Removes all interceptors of a specific type.
    ///
    /// - Parameter type: The type of interceptors to remove.
    /// - Returns: Self for chaining.
    @discardableResult
    public func removeAll<T: NetworkInterceptor>(ofType type: T.Type) -> InterceptorChain {
        lock.withLock {
            guard !isFrozen else { return }
            interceptors.removeAll { $0 is T }
        }
        return self
    }

    /// Removes all interceptors.
    ///
    /// - Returns: Self for chaining.
    @discardableResult
    public func removeAll() -> InterceptorChain {
        lock.withLock {
            guard !isFrozen else { return }
            interceptors.removeAll()
        }
        return self
    }

    /// Freezes the chain, preventing further modifications.
    ///
    /// - Returns: Self for chaining.
    @discardableResult
    public func freeze() -> InterceptorChain {
        lock.withLock {
            isFrozen = true
        }
        return self
    }

    // MARK: - Chain Execution

    /// Processes a request through the interceptor chain.
    ///
    /// - Parameters:
    ///   - request: The request to process.
    ///   - context: The execution context.
    /// - Returns: The processed request.
    /// - Throws: If any interceptor fails.
    public func processRequest(
        _ request: URLRequest,
        context: Context
    ) async throws -> URLRequest {
        var current = request

        for interceptor in interceptors {
            current = try await interceptor.intercept(request: current)
        }

        return current
    }

    /// Processes a response through the interceptor chain (in reverse order).
    ///
    /// - Parameters:
    ///   - response: The response to process.
    ///   - context: The execution context.
    /// - Returns: The processed response.
    /// - Throws: If any interceptor fails.
    public func processResponse(
        _ response: NetworkResponse,
        context: Context
    ) async throws -> NetworkResponse {
        var current = response

        for interceptor in interceptors.reversed() {
            current = try await interceptor.intercept(response: current)
        }

        return current
    }

    /// Executes the complete request/response cycle.
    ///
    /// - Parameters:
    ///   - request: The initial request.
    ///   - execute: The actual network call to execute.
    /// - Returns: The final response.
    /// - Throws: If execution fails.
    public func execute(
        request: URLRequest,
        execute: (URLRequest) async throws -> NetworkResponse
    ) async throws -> NetworkResponse {
        let context = Context(phase: .request, originalRequest: request)

        // Process request through chain
        let processedRequest = try await processRequest(request, context: context)

        // Execute the actual network call
        let response = try await execute(processedRequest)

        // Process response through chain (reverse order)
        let responseContext = Context(
            phase: .response,
            originalRequest: request,
            metadata: context.metadata
        )

        return try await processResponse(response, context: responseContext)
    }

    // MARK: - Chain Inspection

    /// Returns the number of interceptors in the chain.
    public var count: Int {
        lock.withLock { interceptors.count }
    }

    /// Returns whether the chain is empty.
    public var isEmpty: Bool {
        lock.withLock { interceptors.isEmpty }
    }

    /// Checks if the chain contains an interceptor of the specified type.
    ///
    /// - Parameter type: The interceptor type to check for.
    /// - Returns: True if the chain contains the interceptor type.
    public func contains<T: NetworkInterceptor>(type: T.Type) -> Bool {
        lock.withLock {
            interceptors.contains { $0 is T }
        }
    }

    /// Returns the first interceptor of the specified type.
    ///
    /// - Parameter type: The interceptor type to find.
    /// - Returns: The first matching interceptor, or nil.
    public func first<T: NetworkInterceptor>(ofType type: T.Type) -> T? {
        lock.withLock {
            interceptors.first { $0 is T } as? T
        }
    }

    /// Returns all interceptors of the specified type.
    ///
    /// - Parameter type: The interceptor type to find.
    /// - Returns: All matching interceptors.
    public func all<T: NetworkInterceptor>(ofType type: T.Type) -> [T] {
        lock.withLock {
            interceptors.compactMap { $0 as? T }
        }
    }

    // MARK: - Chain Copying

    /// Creates a copy of this chain.
    ///
    /// - Returns: A new chain with the same interceptors.
    public func copy() -> InterceptorChain {
        let newChain = InterceptorChain()
        lock.withLock {
            newChain.interceptors = interceptors
        }
        return newChain
    }
}

// MARK: - ExpressibleByArrayLiteral

extension InterceptorChain: ExpressibleByArrayLiteral {
    public convenience init(arrayLiteral elements: any NetworkInterceptor...) {
        self.init(elements)
    }
}

// MARK: - Chain Builder

/// A result builder for constructing interceptor chains.
@resultBuilder
public struct InterceptorChainBuilder {

    public static func buildBlock(_ components: any NetworkInterceptor...) -> [any NetworkInterceptor] {
        components
    }

    public static func buildOptional(_ component: [any NetworkInterceptor]?) -> [any NetworkInterceptor] {
        component ?? []
    }

    public static func buildEither(first component: [any NetworkInterceptor]) -> [any NetworkInterceptor] {
        component
    }

    public static func buildEither(second component: [any NetworkInterceptor]) -> [any NetworkInterceptor] {
        component
    }

    public static func buildArray(_ components: [[any NetworkInterceptor]]) -> [any NetworkInterceptor] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: any NetworkInterceptor) -> [any NetworkInterceptor] {
        [expression]
    }

    public static func buildExpression(_ expression: [any NetworkInterceptor]) -> [any NetworkInterceptor] {
        expression
    }
}

extension InterceptorChain {

    /// Creates an interceptor chain using a result builder.
    ///
    /// - Parameter builder: The builder closure.
    public convenience init(@InterceptorChainBuilder _ builder: () -> [any NetworkInterceptor]) {
        self.init(builder())
    }
}

// MARK: - Preset Chains

extension InterceptorChain {

    /// Creates a basic chain with logging.
    ///
    /// - Parameter level: The logging level.
    /// - Returns: A chain with logging enabled.
    public static func withLogging(level: LoggingInterceptor.LogLevel = .info) -> InterceptorChain {
        InterceptorChain([LoggingInterceptor(level: level)])
    }

    /// Creates a chain with authentication and logging.
    ///
    /// - Parameters:
    ///   - tokenProvider: The authentication token provider.
    ///   - logLevel: The logging level.
    /// - Returns: A configured chain.
    public static func standard(
        tokenProvider: @escaping @Sendable () async -> String?,
        logLevel: LoggingInterceptor.LogLevel = .info
    ) -> InterceptorChain {
        InterceptorChain([
            LoggingInterceptor(level: logLevel),
            AuthInterceptor(tokenProvider: tokenProvider)
        ])
    }

    /// Creates a robust chain with retry and logging.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts.
    ///   - logLevel: The logging level.
    /// - Returns: A configured chain.
    public static func robust(
        maxRetries: Int = 3,
        logLevel: LoggingInterceptor.LogLevel = .info
    ) -> InterceptorChain {
        InterceptorChain([
            LoggingInterceptor(level: logLevel),
            RetryInterceptor(maxAttempts: maxRetries)
        ])
    }
}
