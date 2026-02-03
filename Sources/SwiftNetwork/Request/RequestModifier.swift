import Foundation

/// A protocol for modifying URL requests before they are sent.
///
/// Request modifiers provide a composable way to transform requests,
/// allowing you to add headers, modify URLs, or inject authentication.
///
/// ```swift
/// struct APIKeyModifier: RequestModifier {
///     let apiKey: String
///
///     func modify(_ request: URLRequest) -> URLRequest {
///         var modified = request
///         modified.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
///         return modified
///     }
/// }
/// ```
public protocol RequestModifier: Sendable {

    /// Modifies the given request.
    ///
    /// - Parameter request: The request to modify.
    /// - Returns: The modified request.
    /// - Throws: If modification fails.
    func modify(_ request: URLRequest) async throws -> URLRequest
}

// MARK: - Built-in Modifiers

/// Adds headers to a request.
public struct HeaderModifier: RequestModifier {

    /// The headers to add.
    public let headers: [String: String]

    /// Whether to overwrite existing headers.
    public let overwrite: Bool

    /// Creates a header modifier.
    ///
    /// - Parameters:
    ///   - headers: The headers to add.
    ///   - overwrite: Whether to overwrite existing headers. Defaults to true.
    public init(headers: [String: String], overwrite: Bool = true) {
        self.headers = headers
        self.overwrite = overwrite
    }

    /// Creates a single header modifier.
    ///
    /// - Parameters:
    ///   - key: The header name.
    ///   - value: The header value.
    ///   - overwrite: Whether to overwrite existing headers.
    public init(_ key: String, _ value: String, overwrite: Bool = true) {
        self.headers = [key: value]
        self.overwrite = overwrite
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        for (key, value) in headers {
            if overwrite || modified.value(forHTTPHeaderField: key) == nil {
                modified.setValue(value, forHTTPHeaderField: key)
            }
        }
        return modified
    }
}

/// Sets the timeout interval for a request.
public struct TimeoutModifier: RequestModifier {

    /// The timeout interval in seconds.
    public let timeout: TimeInterval

    /// Creates a timeout modifier.
    ///
    /// - Parameter timeout: The timeout in seconds.
    public init(_ timeout: TimeInterval) {
        self.timeout = timeout
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.timeoutInterval = timeout
        return modified
    }
}

/// Sets the cache policy for a request.
public struct CachePolicyModifier: RequestModifier {

    /// The cache policy to apply.
    public let policy: URLRequest.CachePolicy

    /// Creates a cache policy modifier.
    ///
    /// - Parameter policy: The cache policy.
    public init(_ policy: URLRequest.CachePolicy) {
        self.policy = policy
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.cachePolicy = policy
        return modified
    }
}

/// Adds query parameters to a request URL.
public struct QueryParameterModifier: RequestModifier {

    /// The query parameters to add.
    public let parameters: [String: String]

    /// Creates a query parameter modifier.
    ///
    /// - Parameter parameters: The query parameters to add.
    public init(_ parameters: [String: String]) {
        self.parameters = parameters
    }

    /// Creates a single query parameter modifier.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - value: The parameter value.
    public init(_ name: String, _ value: String) {
        self.parameters = [name: value]
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        guard var components = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: true) }) else {
            return request
        }

        var queryItems = components.queryItems ?? []
        for (name, value) in parameters {
            queryItems.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = queryItems

        var modified = request
        modified.url = components.url
        return modified
    }
}

/// Adds bearer token authentication to a request.
public struct BearerTokenModifier: RequestModifier {

    /// The token provider closure.
    private let tokenProvider: @Sendable () async throws -> String

    /// Creates a bearer token modifier with a static token.
    ///
    /// - Parameter token: The bearer token.
    public init(token: String) {
        self.tokenProvider = { token }
    }

    /// Creates a bearer token modifier with a dynamic token provider.
    ///
    /// - Parameter provider: A closure that returns the token.
    public init(provider: @escaping @Sendable () async throws -> String) {
        self.tokenProvider = provider
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        let token = try await tokenProvider()
        var modified = request
        modified.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return modified
    }
}

/// Adds basic authentication to a request.
public struct BasicAuthModifier: RequestModifier {

    /// The encoded credentials.
    private let credentials: String

    /// Creates a basic auth modifier.
    ///
    /// - Parameters:
    ///   - username: The username.
    ///   - password: The password.
    public init(username: String, password: String) {
        let combined = "\(username):\(password)"
        self.credentials = Data(combined.utf8).base64EncodedString()
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return modified
    }
}

/// Sets the content type header.
public struct ContentTypeModifier: RequestModifier {

    /// Common content types.
    public enum ContentType: String, Sendable {
        case json = "application/json"
        case xml = "application/xml"
        case formURLEncoded = "application/x-www-form-urlencoded"
        case multipartFormData = "multipart/form-data"
        case plainText = "text/plain"
        case html = "text/html"
        case octetStream = "application/octet-stream"
    }

    /// The content type value.
    public let contentType: String

    /// Creates a content type modifier.
    ///
    /// - Parameter type: The content type.
    public init(_ type: ContentType) {
        self.contentType = type.rawValue
    }

    /// Creates a content type modifier with a custom value.
    ///
    /// - Parameter value: The content type string.
    public init(custom value: String) {
        self.contentType = value
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.setValue(contentType, forHTTPHeaderField: "Content-Type")
        return modified
    }
}

/// Sets the accept header.
public struct AcceptModifier: RequestModifier {

    /// The accept value.
    public let accept: String

    /// Creates an accept modifier.
    ///
    /// - Parameter type: The content type to accept.
    public init(_ type: ContentTypeModifier.ContentType) {
        self.accept = type.rawValue
    }

    /// Creates an accept modifier with a custom value.
    ///
    /// - Parameter value: The accept string.
    public init(custom value: String) {
        self.accept = value
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.setValue(accept, forHTTPHeaderField: "Accept")
        return modified
    }
}

/// Adds a request ID header for tracing.
public struct RequestIDModifier: RequestModifier {

    /// The header name.
    public let headerName: String

    /// The ID generator.
    private let idGenerator: @Sendable () -> String

    /// Creates a request ID modifier.
    ///
    /// - Parameters:
    ///   - headerName: The header name to use. Defaults to "X-Request-ID".
    ///   - generator: The ID generator. Defaults to UUID.
    public init(
        headerName: String = "X-Request-ID",
        generator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.headerName = headerName
        self.idGenerator = generator
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.setValue(idGenerator(), forHTTPHeaderField: headerName)
        return modified
    }
}

/// Adds user-agent header.
public struct UserAgentModifier: RequestModifier {

    /// The user agent string.
    public let userAgent: String

    /// Creates a user agent modifier.
    ///
    /// - Parameter userAgent: The user agent string.
    public init(_ userAgent: String) {
        self.userAgent = userAgent
    }

    /// Creates a default user agent modifier with app info.
    ///
    /// - Parameters:
    ///   - appName: The application name.
    ///   - appVersion: The application version.
    public init(appName: String, appVersion: String) {
        #if os(iOS)
        let os = "iOS"
        #elseif os(macOS)
        let os = "macOS"
        #elseif os(tvOS)
        let os = "tvOS"
        #elseif os(watchOS)
        let os = "watchOS"
        #else
        let os = "Unknown"
        #endif

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.userAgent = "\(appName)/\(appVersion) (\(os); \(osVersion))"
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var modified = request
        modified.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return modified
    }
}

// MARK: - Composite Modifier

/// Combines multiple modifiers into one.
public struct CompositeModifier: RequestModifier {

    /// The modifiers to apply in order.
    public let modifiers: [any RequestModifier]

    /// Creates a composite modifier.
    ///
    /// - Parameter modifiers: The modifiers to combine.
    public init(_ modifiers: [any RequestModifier]) {
        self.modifiers = modifiers
    }

    /// Creates a composite modifier from variadic modifiers.
    ///
    /// - Parameter modifiers: The modifiers to combine.
    public init(_ modifiers: any RequestModifier...) {
        self.modifiers = modifiers
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        var current = request
        for modifier in modifiers {
            current = try await modifier.modify(current)
        }
        return current
    }
}

// MARK: - Conditional Modifier

/// Applies a modifier conditionally.
public struct ConditionalModifier: RequestModifier {

    /// The condition to check.
    private let condition: @Sendable () async -> Bool

    /// The modifier to apply when condition is true.
    private let modifier: any RequestModifier

    /// Creates a conditional modifier.
    ///
    /// - Parameters:
    ///   - condition: The condition closure.
    ///   - modifier: The modifier to apply.
    public init(
        if condition: @escaping @Sendable () async -> Bool,
        then modifier: any RequestModifier
    ) {
        self.condition = condition
        self.modifier = modifier
    }

    public func modify(_ request: URLRequest) async throws -> URLRequest {
        if await condition() {
            return try await modifier.modify(request)
        }
        return request
    }
}

// MARK: - Request Modifier Builder

/// A result builder for composing request modifiers.
@resultBuilder
public struct RequestModifierBuilder {

    public static func buildBlock(_ components: any RequestModifier...) -> [any RequestModifier] {
        components
    }

    public static func buildOptional(_ component: [any RequestModifier]?) -> [any RequestModifier] {
        component ?? []
    }

    public static func buildEither(first component: [any RequestModifier]) -> [any RequestModifier] {
        component
    }

    public static func buildEither(second component: [any RequestModifier]) -> [any RequestModifier] {
        component
    }

    public static func buildArray(_ components: [[any RequestModifier]]) -> [any RequestModifier] {
        components.flatMap { $0 }
    }
}

// MARK: - URLRequest Extensions

extension URLRequest {

    /// Applies a modifier to this request.
    ///
    /// - Parameter modifier: The modifier to apply.
    /// - Returns: The modified request.
    /// - Throws: If modification fails.
    public func applying(_ modifier: any RequestModifier) async throws -> URLRequest {
        try await modifier.modify(self)
    }

    /// Applies multiple modifiers to this request.
    ///
    /// - Parameter modifiers: The modifiers to apply.
    /// - Returns: The modified request.
    /// - Throws: If any modification fails.
    public func applying(_ modifiers: [any RequestModifier]) async throws -> URLRequest {
        var current = self
        for modifier in modifiers {
            current = try await modifier.modify(current)
        }
        return current
    }

    /// Applies modifiers using the result builder syntax.
    ///
    /// - Parameter modifiers: The modifiers to apply.
    /// - Returns: The modified request.
    /// - Throws: If any modification fails.
    public func applying(
        @RequestModifierBuilder _ modifiers: () -> [any RequestModifier]
    ) async throws -> URLRequest {
        try await applying(modifiers())
    }
}
