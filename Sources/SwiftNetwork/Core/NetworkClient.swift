import Foundation

/// The main networking client that handles HTTP requests, uploads, and downloads.
///
/// `NetworkClient` is designed to be created once and shared across your application.
/// It is fully `Sendable` and safe to use from any actor or task context.
///
/// ```swift
/// let client = NetworkClient(
///     baseURL: "https://api.example.com",
///     interceptors: [AuthInterceptor(tokenProvider: { token })]
/// )
///
/// let users: [User] = try await client.request(
///     Endpoint(path: "/users", method: .get)
/// )
/// ```
public final class NetworkClient: @unchecked Sendable {

    // MARK: - Properties

    /// The base URL prepended to all endpoint paths.
    public let baseURL: String

    /// The URLSession used for all network operations.
    private let session: URLSession

    /// The ordered chain of interceptors applied to every request.
    private let interceptors: [any NetworkInterceptor]

    /// The JSON decoder used for response deserialization.
    private let decoder: JSONDecoder

    /// Default timeout interval for requests.
    private let defaultTimeout: TimeInterval

    /// Optional certificate pinning delegate.
    private let certificatePinning: CertificatePinning?

    // MARK: - Initialization

    /// Creates a new network client.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL for all requests.
    ///   - interceptors: Interceptors applied in order to each request. Defaults to empty.
    ///   - decoder: The JSON decoder for response parsing. Defaults to a standard instance.
    ///   - defaultTimeout: Default timeout in seconds. Defaults to 30.
    ///   - certificatePinning: Optional certificate pinning configuration.
    ///   - sessionConfiguration: URLSession configuration. Defaults to `.default`.
    public init(
        baseURL: String,
        interceptors: [any NetworkInterceptor] = [],
        decoder: JSONDecoder = .init(),
        defaultTimeout: TimeInterval = 30,
        certificatePinning: CertificatePinning? = nil,
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.baseURL = baseURL
        self.interceptors = interceptors
        self.decoder = decoder
        self.defaultTimeout = defaultTimeout
        self.certificatePinning = certificatePinning

        if let pinning = certificatePinning {
            self.session = URLSession(
                configuration: sessionConfiguration,
                delegate: pinning,
                delegateQueue: nil
            )
        } else {
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    // MARK: - Request

    /// Performs an HTTP request and decodes the response into the specified type.
    ///
    /// The request passes through all registered interceptors before execution,
    /// and the response passes back through interceptors in reverse order.
    ///
    /// - Parameter endpoint: The endpoint describing the request.
    /// - Returns: The decoded response object.
    /// - Throws: ``NetworkError`` if the request fails at any stage.
    public func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let response = try await performRequest(endpoint)
        return try decodeResponse(response)
    }

    /// Performs an HTTP request and returns the raw ``NetworkResponse``.
    ///
    /// Useful when you need access to headers, status codes, or raw data
    /// without automatic decoding.
    ///
    /// - Parameter endpoint: The endpoint describing the request.
    /// - Returns: The raw network response.
    /// - Throws: ``NetworkError`` if the request fails.
    public func rawRequest(_ endpoint: Endpoint) async throws -> NetworkResponse {
        try await performRequest(endpoint)
    }

    /// Performs an HTTP request expecting no response body.
    ///
    /// Validates the status code but does not attempt to decode a response.
    ///
    /// - Parameter endpoint: The endpoint describing the request.
    /// - Throws: ``NetworkError`` if the request fails.
    public func requestVoid(_ endpoint: Endpoint) async throws {
        _ = try await performRequest(endpoint)
    }

    // MARK: - Upload

    /// Uploads multipart form data to the specified path.
    ///
    /// - Parameters:
    ///   - path: The relative path for the upload endpoint.
    ///   - multipart: The multipart form data to upload.
    ///   - headers: Additional headers to include.
    /// - Returns: The decoded response object.
    /// - Throws: ``NetworkError`` if the upload fails.
    public func upload<T: Decodable>(
        path: String,
        multipart: MultipartFormData,
        headers: [String: String] = [:]
    ) async throws -> T {
        var mergedHeaders = headers
        mergedHeaders["Content-Type"] = multipart.contentType

        let endpoint = Endpoint(
            path: path,
            method: .post,
            headers: mergedHeaders,
            body: multipart.encode()
        )

        let response = try await performRequest(endpoint)
        return try decodeResponse(response)
    }

    /// Uploads raw data to the specified path.
    ///
    /// - Parameters:
    ///   - path: The relative path for the upload endpoint.
    ///   - data: The raw data to upload.
    ///   - contentType: The MIME type of the data.
    ///   - headers: Additional headers.
    /// - Returns: The decoded response object.
    /// - Throws: ``NetworkError`` if the upload fails.
    public func upload<T: Decodable>(
        path: String,
        data: Data,
        contentType: String,
        headers: [String: String] = [:]
    ) async throws -> T {
        var mergedHeaders = headers
        mergedHeaders["Content-Type"] = contentType

        let endpoint = Endpoint(
            path: path,
            method: .post,
            headers: mergedHeaders,
            body: data
        )

        let response = try await performRequest(endpoint)
        return try decodeResponse(response)
    }

    // MARK: - Download

    /// Downloads a file from the specified endpoint to a local destination.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint to download from.
    ///   - destination: The local file URL where the download should be saved.
    /// - Returns: The local file URL of the downloaded file.
    /// - Throws: ``NetworkError`` if the download fails.
    @discardableResult
    public func download(
        endpoint: Endpoint,
        destination: URL
    ) async throws -> URL {
        var request = try endpoint.urlRequest(baseURL: baseURL)
        request.timeoutInterval = endpoint.timeoutInterval ?? defaultTimeout

        let modifiedRequest = try await applyRequestInterceptors(request)
        let (tempURL, response) = try await performDownload(modifiedRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        let statusCode = httpResponse.statusCode
        guard (200...299).contains(statusCode) else {
            throw NetworkError.httpError(statusCode: statusCode, data: nil)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempURL, to: destination)

        return destination
    }

    // MARK: - Private Helpers

    private func performRequest(_ endpoint: Endpoint) async throws -> NetworkResponse {
        var request = try endpoint.urlRequest(baseURL: baseURL)
        request.timeoutInterval = endpoint.timeoutInterval ?? defaultTimeout

        let modifiedRequest = try await applyRequestInterceptors(request)

        do {
            let (data, response) = try await session.data(for: modifiedRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(URLError(.badServerResponse))
            }

            let networkResponse = NetworkResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields as? [String: String] ?? [:],
                originalRequest: modifiedRequest,
                httpResponse: httpResponse
            )

            let processedResponse = try await applyResponseInterceptors(networkResponse)

            guard (200...299).contains(processedResponse.statusCode) else {
                throw NetworkError.httpError(
                    statusCode: processedResponse.statusCode,
                    data: processedResponse.data
                )
            }

            return processedResponse
        } catch let error as NetworkError {
            throw error
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw NetworkError.unknown(error)
        }
    }

    private func performDownload(_ request: URLRequest) async throws -> (URL, URLResponse) {
        try await session.download(for: request)
    }

    private func applyRequestInterceptors(_ request: URLRequest) async throws -> URLRequest {
        var current = request
        for interceptor in interceptors {
            current = try await interceptor.intercept(request: current)
        }
        return current
    }

    private func applyResponseInterceptors(_ response: NetworkResponse) async throws -> NetworkResponse {
        var current = response
        for interceptor in interceptors.reversed() {
            current = try await interceptor.intercept(response: current)
        }
        return current
    }

    private func decodeResponse<T: Decodable>(_ response: NetworkResponse) throws -> T {
        guard !response.data.isEmpty else {
            throw NetworkError.noData
        }
        do {
            return try decoder.decode(T.self, from: response.data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    private func mapURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .noConnection
        case .cancelled:
            return .cancelled
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return .certificatePinningFailed
        default:
            return .unknown(error)
        }
    }
}
