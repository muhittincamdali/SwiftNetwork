import Foundation

// MARK: - HTTPURLResponse Extensions

extension HTTPURLResponse {

    // MARK: - Status Code Categories

    /// Whether the response indicates success (2xx).
    public var isSuccess: Bool {
        (200...299).contains(statusCode)
    }

    /// Whether the response indicates a redirect (3xx).
    public var isRedirect: Bool {
        (300...399).contains(statusCode)
    }

    /// Whether the response indicates a client error (4xx).
    public var isClientError: Bool {
        (400...499).contains(statusCode)
    }

    /// Whether the response indicates a server error (5xx).
    public var isServerError: Bool {
        (500...599).contains(statusCode)
    }

    /// Whether the response indicates any error (4xx or 5xx).
    public var isError: Bool {
        isClientError || isServerError
    }

    // MARK: - Common Status Codes

    /// Whether the response is 200 OK.
    public var isOK: Bool {
        statusCode == 200
    }

    /// Whether the response is 201 Created.
    public var isCreated: Bool {
        statusCode == 201
    }

    /// Whether the response is 204 No Content.
    public var isNoContent: Bool {
        statusCode == 204
    }

    /// Whether the response is 304 Not Modified.
    public var isNotModified: Bool {
        statusCode == 304
    }

    /// Whether the response is 400 Bad Request.
    public var isBadRequest: Bool {
        statusCode == 400
    }

    /// Whether the response is 401 Unauthorized.
    public var isUnauthorized: Bool {
        statusCode == 401
    }

    /// Whether the response is 403 Forbidden.
    public var isForbidden: Bool {
        statusCode == 403
    }

    /// Whether the response is 404 Not Found.
    public var isNotFound: Bool {
        statusCode == 404
    }

    /// Whether the response is 429 Too Many Requests.
    public var isTooManyRequests: Bool {
        statusCode == 429
    }

    /// Whether the response is 500 Internal Server Error.
    public var isInternalServerError: Bool {
        statusCode == 500
    }

    /// Whether the response is 503 Service Unavailable.
    public var isServiceUnavailable: Bool {
        statusCode == 503
    }

    // MARK: - Header Accessors

    /// The Content-Type header value.
    public var contentType: String? {
        value(forHTTPHeaderField: "Content-Type")
    }

    /// The Content-Length header value as an integer.
    public var contentLength: Int64? {
        guard let value = value(forHTTPHeaderField: "Content-Length") else { return nil }
        return Int64(value)
    }

    /// The Content-Encoding header value.
    public var contentEncoding: String? {
        value(forHTTPHeaderField: "Content-Encoding")
    }

    /// The ETag header value.
    public var etag: String? {
        value(forHTTPHeaderField: "ETag")
    }

    /// The Last-Modified header value.
    public var lastModified: String? {
        value(forHTTPHeaderField: "Last-Modified")
    }

    /// The Last-Modified header as a Date.
    public var lastModifiedDate: Date? {
        guard let lastModified = lastModified else { return nil }
        return httpDateFormatter.date(from: lastModified)
    }

    /// The Cache-Control header value.
    public var cacheControl: String? {
        value(forHTTPHeaderField: "Cache-Control")
    }

    /// The Retry-After header value.
    public var retryAfter: String? {
        value(forHTTPHeaderField: "Retry-After")
    }

    /// The Retry-After header as a TimeInterval.
    public var retryAfterInterval: TimeInterval? {
        guard let retryAfter = retryAfter else { return nil }

        // Try parsing as seconds
        if let seconds = TimeInterval(retryAfter) {
            return seconds
        }

        // Try parsing as HTTP date
        if let date = httpDateFormatter.date(from: retryAfter) {
            return date.timeIntervalSinceNow
        }

        return nil
    }

    /// The Location header value.
    public var location: String? {
        value(forHTTPHeaderField: "Location")
    }

    /// The Location header as a URL.
    public var locationURL: URL? {
        guard let location = location else { return nil }
        return URL(string: location)
    }

    /// The WWW-Authenticate header value.
    public var wwwAuthenticate: String? {
        value(forHTTPHeaderField: "WWW-Authenticate")
    }

    /// The X-Request-ID header value.
    public var requestId: String? {
        value(forHTTPHeaderField: "X-Request-ID")
    }

    // MARK: - Content Type Parsing

    /// The MIME type from Content-Type (without parameters).
    public var mimeType: String? {
        guard let contentType = contentType else { return nil }
        return contentType.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
    }

    /// The charset from Content-Type.
    public var charset: String? {
        guard let contentType = contentType else { return nil }

        let components = contentType.split(separator: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("charset=") {
                return String(trimmed.dropFirst(8)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        return nil
    }

    /// The encoding from charset.
    public var textEncoding: String.Encoding? {
        guard let charset = charset?.lowercased() else { return nil }

        switch charset {
        case "utf-8", "utf8":
            return .utf8
        case "iso-8859-1", "latin1":
            return .isoLatin1
        case "iso-8859-2", "latin2":
            return .isoLatin2
        case "ascii", "us-ascii":
            return .ascii
        case "utf-16", "utf16":
            return .utf16
        case "utf-32", "utf32":
            return .utf32
        default:
            return nil
        }
    }

    /// Whether the content type is JSON.
    public var isJSON: Bool {
        guard let mime = mimeType?.lowercased() else { return false }
        return mime == "application/json" || mime.hasSuffix("+json")
    }

    /// Whether the content type is XML.
    public var isXML: Bool {
        guard let mime = mimeType?.lowercased() else { return false }
        return mime == "application/xml" || mime == "text/xml" || mime.hasSuffix("+xml")
    }

    /// Whether the content type is HTML.
    public var isHTML: Bool {
        mimeType?.lowercased() == "text/html"
    }

    /// Whether the content type is plain text.
    public var isPlainText: Bool {
        mimeType?.lowercased() == "text/plain"
    }

    // MARK: - Cache Control Parsing

    /// Parsed cache control directives.
    public var cacheControlDirectives: [String: String?] {
        guard let cacheControl = cacheControl else { return [:] }

        var directives: [String: String?] = [:]
        let components = cacheControl.split(separator: ",")

        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1)

            let key = String(parts[0]).lowercased()
            let value = parts.count > 1 ? String(parts[1]) : nil

            directives[key] = value
        }

        return directives
    }

    /// Max-age from Cache-Control.
    public var maxAge: TimeInterval? {
        guard let value = cacheControlDirectives["max-age"] as? String else { return nil }
        return TimeInterval(value)
    }

    /// Whether Cache-Control contains no-cache.
    public var isNoCache: Bool {
        cacheControlDirectives.keys.contains("no-cache")
    }

    /// Whether Cache-Control contains no-store.
    public var isNoStore: Bool {
        cacheControlDirectives.keys.contains("no-store")
    }

    /// Whether the response can be cached.
    public var isCacheable: Bool {
        guard isSuccess else { return false }
        return !isNoStore && !isNoCache
    }

    // MARK: - Helpers

    /// HTTP date formatter.
    private var httpDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(identifier: "GMT")
        return formatter
    }

    /// Gets a header value case-insensitively.
    public func header(_ name: String) -> String? {
        value(forHTTPHeaderField: name)
    }

    /// Gets all headers as a dictionary.
    public var headerDictionary: [String: String] {
        allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
    }

    // MARK: - Status Code Description

    /// Human-readable description of the status code.
    public var statusDescription: String {
        HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }

    /// Detailed description including status code and description.
    public var statusText: String {
        "\(statusCode) \(statusDescription)"
    }
}

// MARK: - Status Code Enum

/// Common HTTP status codes.
public enum HTTPStatusCode: Int, Sendable {
    // 2xx Success
    case ok = 200
    case created = 201
    case accepted = 202
    case noContent = 204
    case resetContent = 205
    case partialContent = 206

    // 3xx Redirection
    case multipleChoices = 300
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case temporaryRedirect = 307
    case permanentRedirect = 308

    // 4xx Client Error
    case badRequest = 400
    case unauthorized = 401
    case paymentRequired = 402
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case notAcceptable = 406
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case lengthRequired = 411
    case preconditionFailed = 412
    case payloadTooLarge = 413
    case uriTooLong = 414
    case unsupportedMediaType = 415
    case rangeNotSatisfiable = 416
    case expectationFailed = 417
    case imATeapot = 418
    case unprocessableEntity = 422
    case tooManyRequests = 429

    // 5xx Server Error
    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504
    case httpVersionNotSupported = 505

    /// Whether this is a success code.
    public var isSuccess: Bool {
        (200...299).contains(rawValue)
    }

    /// Whether this is a redirect code.
    public var isRedirect: Bool {
        (300...399).contains(rawValue)
    }

    /// Whether this is a client error code.
    public var isClientError: Bool {
        (400...499).contains(rawValue)
    }

    /// Whether this is a server error code.
    public var isServerError: Bool {
        (500...599).contains(rawValue)
    }
}
