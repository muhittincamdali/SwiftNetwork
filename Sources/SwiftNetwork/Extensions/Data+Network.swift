import Foundation
import CommonCrypto

// MARK: - Data Network Extensions

extension Data {

    // MARK: - JSON Conversion

    /// Converts data to a JSON object.
    ///
    /// - Parameter options: JSON reading options.
    /// - Returns: The JSON object.
    /// - Throws: JSON serialization errors.
    public func toJSON(options: JSONSerialization.ReadingOptions = []) throws -> Any {
        try JSONSerialization.jsonObject(with: self, options: options)
    }

    /// Converts data to a JSON dictionary.
    ///
    /// - Returns: The JSON dictionary, or nil if not a dictionary.
    public func toJSONDictionary() -> [String: Any]? {
        try? toJSON() as? [String: Any]
    }

    /// Converts data to a JSON array.
    ///
    /// - Returns: The JSON array, or nil if not an array.
    public func toJSONArray() -> [Any]? {
        try? toJSON() as? [Any]
    }

    /// Creates data from a JSON object.
    ///
    /// - Parameters:
    ///   - json: The JSON object.
    ///   - options: JSON writing options.
    /// - Returns: The encoded data.
    /// - Throws: JSON serialization errors.
    public static func fromJSON(
        _ json: Any,
        options: JSONSerialization.WritingOptions = []
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: options)
    }

    /// Pretty-printed JSON string representation.
    public var prettyPrintedJSONString: String? {
        guard let json = try? toJSON() else { return nil }
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - String Conversion

    /// Converts data to a UTF-8 string.
    public var utf8String: String? {
        String(data: self, encoding: .utf8)
    }

    /// Converts data to a string with the specified encoding.
    ///
    /// - Parameter encoding: The string encoding.
    /// - Returns: The string, or nil if conversion fails.
    public func toString(encoding: String.Encoding = .utf8) -> String? {
        String(data: self, encoding: encoding)
    }

    // MARK: - Hex Conversion

    /// Hexadecimal string representation.
    public var hexString: String {
        map { String(format: "%02hhx", $0) }.joined()
    }

    /// Creates data from a hexadecimal string.
    ///
    /// - Parameter hex: The hex string.
    /// - Returns: The data, or nil if invalid hex.
    public static func fromHex(_ hex: String) -> Data? {
        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        return data
    }

    // MARK: - Base64

    /// URL-safe base64 encoded string.
    public var base64URLEncodedString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Creates data from a URL-safe base64 string.
    ///
    /// - Parameter string: The base64url string.
    /// - Returns: The decoded data, or nil if invalid.
    public static func fromBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        return Data(base64Encoded: base64)
    }

    // MARK: - Hashing

    /// MD5 hash of the data.
    public var md5: Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(count), &hash)
        }
        return Data(hash)
    }

    /// SHA1 hash of the data.
    public var sha1: Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(count), &hash)
        }
        return Data(hash)
    }

    /// SHA256 hash of the data.
    public var sha256: Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(count), &hash)
        }
        return Data(hash)
    }

    /// SHA512 hash of the data.
    public var sha512: Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        withUnsafeBytes { bytes in
            _ = CC_SHA512(bytes.baseAddress, CC_LONG(count), &hash)
        }
        return Data(hash)
    }

    /// MD5 hash as a hex string.
    public var md5String: String {
        md5.hexString
    }

    /// SHA256 hash as a hex string.
    public var sha256String: String {
        sha256.hexString
    }

    // MARK: - HMAC

    /// Computes HMAC-SHA256.
    ///
    /// - Parameter key: The HMAC key.
    /// - Returns: The HMAC digest.
    public func hmacSHA256(key: Data) -> Data {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBytes.baseAddress,
                    key.count,
                    dataBytes.baseAddress,
                    count,
                    &hmac
                )
            }
        }

        return Data(hmac)
    }

    // MARK: - Size Information

    /// Human-readable size string.
    public var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// Whether the data is empty.
    public var isNotEmpty: Bool {
        !isEmpty
    }

    // MARK: - Content Detection

    /// Whether data appears to be UTF-8 text.
    public var isUTF8Text: Bool {
        String(data: self, encoding: .utf8) != nil
    }

    /// Whether data appears to be JSON.
    public var isJSON: Bool {
        guard let _ = try? JSONSerialization.jsonObject(with: self) else {
            return false
        }
        return true
    }

    /// Whether data appears to be a JPEG image.
    public var isJPEG: Bool {
        guard count >= 3 else { return false }
        return self[0] == 0xFF && self[1] == 0xD8 && self[2] == 0xFF
    }

    /// Whether data appears to be a PNG image.
    public var isPNG: Bool {
        guard count >= 8 else { return false }
        let header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return self.prefix(8).elementsEqual(header)
    }

    /// Whether data appears to be a GIF image.
    public var isGIF: Bool {
        guard count >= 6 else { return false }
        let gif87a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]
        let gif89a: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]
        return self.prefix(6).elementsEqual(gif87a) || self.prefix(6).elementsEqual(gif89a)
    }

    /// Whether data appears to be a PDF.
    public var isPDF: Bool {
        guard count >= 5 else { return false }
        let header: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D]
        return self.prefix(5).elementsEqual(header)
    }

    /// Detects the MIME type based on magic bytes.
    public var detectedMIMEType: String? {
        if isJPEG { return "image/jpeg" }
        if isPNG { return "image/png" }
        if isGIF { return "image/gif" }
        if isPDF { return "application/pdf" }
        if isJSON { return "application/json" }
        if isUTF8Text { return "text/plain" }
        return nil
    }

    // MARK: - Chunking

    /// Splits data into chunks of specified size.
    ///
    /// - Parameter size: The chunk size.
    /// - Returns: An array of data chunks.
    public func chunked(size: Int) -> [Data] {
        guard size > 0 else { return [self] }

        var chunks: [Data] = []
        var offset = 0

        while offset < count {
            let chunkSize = min(size, count - offset)
            let chunk = self.subdata(in: offset..<(offset + chunkSize))
            chunks.append(chunk)
            offset += chunkSize
        }

        return chunks
    }

    // MARK: - Encoding/Decoding Helpers

    /// Decodes data to a Decodable type.
    ///
    /// - Parameters:
    ///   - type: The type to decode to.
    ///   - decoder: The JSON decoder.
    /// - Returns: The decoded value.
    /// - Throws: Decoding errors.
    public func decoded<T: Decodable>(
        as type: T.Type,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        try decoder.decode(type, from: self)
    }

    /// Encodes an Encodable value to data.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - encoder: The JSON encoder.
    /// - Returns: The encoded data.
    /// - Throws: Encoding errors.
    public static func encoded<T: Encodable>(
        _ value: T,
        using encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try encoder.encode(value)
    }
}

// MARK: - Codable Data

/// A wrapper for Data that provides Codable support with base64 encoding.
public struct CodableData: Codable, Sendable, Equatable {

    /// The underlying data.
    public let data: Data

    /// Creates a CodableData wrapper.
    public init(_ data: Data) {
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let base64String = try container.decode(String.self)
        guard let data = Data(base64Encoded: base64String) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid base64 string"
            )
        }
        self.data = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data.base64EncodedString())
    }
}
