import Foundation

/// A protocol for decoding network responses into typed values.
///
/// Response decoders handle the transformation of raw response data
/// into Swift types, supporting different formats and error handling.
///
/// ```swift
/// let decoder = JSONResponseDecoder()
/// let user: User = try await decoder.decode(response)
/// ```
public protocol ResponseDecoder: Sendable {

    /// Decodes a response into the specified type.
    ///
    /// - Parameters:
    ///   - type: The type to decode into.
    ///   - response: The network response to decode.
    /// - Returns: The decoded value.
    /// - Throws: Decoding errors.
    func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T
}

// MARK: - JSON Response Decoder

/// Decodes JSON responses using `JSONDecoder`.
public final class JSONResponseDecoder: ResponseDecoder, @unchecked Sendable {

    /// The underlying JSON decoder.
    public let jsonDecoder: JSONDecoder

    /// Whether to throw for empty responses.
    public let throwsOnEmptyData: Bool

    /// Creates a JSON response decoder.
    ///
    /// - Parameters:
    ///   - decoder: The JSON decoder to use. Defaults to a new instance.
    ///   - throwsOnEmptyData: Whether to throw for empty data. Defaults to true.
    public init(
        decoder: JSONDecoder = JSONDecoder(),
        throwsOnEmptyData: Bool = true
    ) {
        self.jsonDecoder = decoder
        self.throwsOnEmptyData = throwsOnEmptyData
    }

    /// Creates a JSON response decoder with custom configuration.
    ///
    /// - Parameters:
    ///   - keyDecodingStrategy: The key decoding strategy.
    ///   - dateDecodingStrategy: The date decoding strategy.
    ///   - dataDecodingStrategy: The data decoding strategy.
    public convenience init(
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate,
        dataDecodingStrategy: JSONDecoder.DataDecodingStrategy = .base64
    ) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = keyDecodingStrategy
        decoder.dateDecodingStrategy = dateDecodingStrategy
        decoder.dataDecodingStrategy = dataDecodingStrategy
        self.init(decoder: decoder)
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        guard !response.data.isEmpty else {
            if throwsOnEmptyData {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Response data is empty"
                    )
                )
            }
            // Try to decode empty JSON object/array
            let emptyJSON = "{}".data(using: .utf8)!
            return try jsonDecoder.decode(type, from: emptyJSON)
        }

        do {
            return try jsonDecoder.decode(type, from: response.data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
}

// MARK: - Property List Response Decoder

/// Decodes property list responses using `PropertyListDecoder`.
public final class PropertyListResponseDecoder: ResponseDecoder, @unchecked Sendable {

    /// The underlying property list decoder.
    public let plistDecoder: PropertyListDecoder

    /// Creates a property list response decoder.
    ///
    /// - Parameter decoder: The property list decoder to use.
    public init(decoder: PropertyListDecoder = PropertyListDecoder()) {
        self.plistDecoder = decoder
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        guard !response.data.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Response data is empty"
                )
            )
        }

        do {
            return try plistDecoder.decode(type, from: response.data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
}

// MARK: - String Response Decoder

/// Decodes responses as strings.
public struct StringResponseDecoder: ResponseDecoder {

    /// The string encoding to use.
    public let encoding: String.Encoding

    /// Creates a string response decoder.
    ///
    /// - Parameter encoding: The string encoding. Defaults to UTF-8.
    public init(encoding: String.Encoding = .utf8) {
        self.encoding = encoding
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        guard type == String.self else {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "StringResponseDecoder only supports String type"
                )
            )
        }

        guard let string = String(data: response.data, encoding: encoding) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Could not decode string with encoding \(encoding)"
                )
            )
        }

        return string as! T
    }
}

// MARK: - Raw Data Decoder

/// Returns the raw response data without decoding.
public struct DataResponseDecoder: ResponseDecoder {

    /// Creates a raw data response decoder.
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        guard type == Data.self else {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "DataResponseDecoder only supports Data type"
                )
            )
        }

        return response.data as! T
    }
}

// MARK: - Void Response Decoder

/// A decoder that ignores the response body entirely.
public struct VoidResponseDecoder: ResponseDecoder {

    /// Creates a void response decoder.
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        guard type == EmptyResponse.self else {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "VoidResponseDecoder only supports EmptyResponse type"
                )
            )
        }

        return EmptyResponse() as! T
    }
}

/// A placeholder type for empty responses.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}

// MARK: - Automatic Response Decoder

/// Automatically selects a decoder based on the response content type.
public final class AutomaticResponseDecoder: ResponseDecoder, @unchecked Sendable {

    /// The JSON decoder to use for JSON content.
    public let jsonDecoder: JSONDecoder

    /// The property list decoder to use for plist content.
    public let plistDecoder: PropertyListDecoder

    /// The default encoding for text content.
    public let textEncoding: String.Encoding

    /// Creates an automatic response decoder.
    ///
    /// - Parameters:
    ///   - jsonDecoder: The JSON decoder. Defaults to a new instance.
    ///   - plistDecoder: The property list decoder. Defaults to a new instance.
    ///   - textEncoding: The text encoding. Defaults to UTF-8.
    public init(
        jsonDecoder: JSONDecoder = JSONDecoder(),
        plistDecoder: PropertyListDecoder = PropertyListDecoder(),
        textEncoding: String.Encoding = .utf8
    ) {
        self.jsonDecoder = jsonDecoder
        self.plistDecoder = plistDecoder
        self.textEncoding = textEncoding
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        let contentType = response.headers["Content-Type"]?.lowercased() ?? ""

        if contentType.contains("application/json") || contentType.contains("text/json") {
            return try await JSONResponseDecoder(decoder: jsonDecoder).decode(type, from: response)
        }

        if contentType.contains("application/x-plist") || contentType.contains("application/plist") {
            return try await PropertyListResponseDecoder(decoder: plistDecoder).decode(type, from: response)
        }

        if contentType.contains("text/") {
            if type == String.self {
                return try await StringResponseDecoder(encoding: textEncoding).decode(type, from: response)
            }
        }

        // Default to JSON
        return try await JSONResponseDecoder(decoder: jsonDecoder).decode(type, from: response)
    }
}

// MARK: - Fallback Response Decoder

/// Tries multiple decoders in order until one succeeds.
public struct FallbackResponseDecoder: ResponseDecoder {

    /// The decoders to try in order.
    public let decoders: [any ResponseDecoder]

    /// Creates a fallback response decoder.
    ///
    /// - Parameter decoders: The decoders to try in order.
    public init(_ decoders: [any ResponseDecoder]) {
        self.decoders = decoders
    }

    /// Creates a fallback response decoder from variadic decoders.
    ///
    /// - Parameter decoders: The decoders to try in order.
    public init(_ decoders: any ResponseDecoder...) {
        self.decoders = decoders
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        var lastError: Error?

        for decoder in decoders {
            do {
                return try await decoder.decode(type, from: response)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? NetworkError.decodingFailed(
            DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "All decoders failed"
                )
            )
        )
    }
}

// MARK: - Transforming Response Decoder

/// A decoder that transforms data before decoding.
public struct TransformingResponseDecoder<Wrapped: ResponseDecoder>: ResponseDecoder {

    /// The wrapped decoder.
    public let decoder: Wrapped

    /// The data transformation.
    private let transform: @Sendable (Data) throws -> Data

    /// Creates a transforming response decoder.
    ///
    /// - Parameters:
    ///   - decoder: The wrapped decoder.
    ///   - transform: The data transformation to apply.
    public init(
        wrapping decoder: Wrapped,
        transform: @escaping @Sendable (Data) throws -> Data
    ) {
        self.decoder = decoder
        self.transform = transform
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: NetworkResponse) async throws -> T {
        let transformedData = try transform(response.data)

        let transformedResponse = NetworkResponse(
            data: transformedData,
            statusCode: response.statusCode,
            headers: response.headers,
            originalRequest: response.originalRequest,
            httpResponse: response.httpResponse
        )

        return try await decoder.decode(type, from: transformedResponse)
    }
}

// MARK: - Response Decoder Extensions

extension ResponseDecoder {

    /// Creates a transforming decoder that applies a data transformation.
    ///
    /// - Parameter transform: The transformation to apply.
    /// - Returns: A new transforming decoder.
    public func transforming(
        _ transform: @escaping @Sendable (Data) throws -> Data
    ) -> TransformingResponseDecoder<Self> {
        TransformingResponseDecoder(wrapping: self, transform: transform)
    }

    /// Creates a transforming decoder that trims whitespace from data.
    ///
    /// - Returns: A new transforming decoder.
    public func trimmingWhitespace() -> TransformingResponseDecoder<Self> {
        transforming { data in
            guard let string = String(data: data, encoding: .utf8) else { return data }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.data(using: .utf8) ?? data
        }
    }

    /// Creates a transforming decoder that extracts a nested JSON path.
    ///
    /// - Parameter path: The JSON key path (dot-separated).
    /// - Returns: A new transforming decoder.
    public func extractingPath(_ path: String) -> TransformingResponseDecoder<Self> {
        transforming { data in
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return data
            }

            let components = path.split(separator: ".").map(String.init)
            var current: Any = json

            for component in components {
                guard let dict = current as? [String: Any],
                      let next = dict[component] else {
                    throw DecodingError.keyNotFound(
                        AnyCodingKey(stringValue: component),
                        DecodingError.Context(
                            codingPath: [],
                            debugDescription: "Key '\(component)' not found in path '\(path)'"
                        )
                    )
                }
                current = next
            }

            return try JSONSerialization.data(withJSONObject: current)
        }
    }
}

// MARK: - Helper Types

/// A type-erased coding key.
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Preset Decoders

extension ResponseDecoder where Self == JSONResponseDecoder {

    /// A JSON decoder with snake_case to camelCase key conversion.
    public static var snakeCaseJSON: JSONResponseDecoder {
        JSONResponseDecoder(keyDecodingStrategy: .convertFromSnakeCase)
    }

    /// A JSON decoder with ISO8601 date decoding.
    public static var iso8601JSON: JSONResponseDecoder {
        JSONResponseDecoder(dateDecodingStrategy: .iso8601)
    }
}

extension ResponseDecoder where Self == AutomaticResponseDecoder {

    /// An automatic decoder with default settings.
    public static var automatic: AutomaticResponseDecoder {
        AutomaticResponseDecoder()
    }
}
