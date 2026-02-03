import Foundation
import Compression

/// An interceptor that handles request and response compression.
///
/// `CompressionInterceptor` automatically compresses request bodies and
/// decompresses response bodies using gzip or other supported algorithms.
///
/// ```swift
/// let compression = CompressionInterceptor(
///     compressRequests: true,
///     decompressResponses: true
/// )
///
/// let client = NetworkClient(
///     baseURL: url,
///     interceptors: [compression]
/// )
/// ```
public struct CompressionInterceptor: NetworkInterceptor {

    // MARK: - Types

    /// Supported compression algorithms.
    public enum Algorithm: String, Sendable {
        case gzip = "gzip"
        case deflate = "deflate"
        case lz4 = "lz4"
        case lzma = "lzma"
        case zlib = "zlib"

        var compressionAlgorithm: compression_algorithm {
            switch self {
            case .gzip, .deflate, .zlib:
                return COMPRESSION_ZLIB
            case .lz4:
                return COMPRESSION_LZ4
            case .lzma:
                return COMPRESSION_LZMA
            }
        }
    }

    // MARK: - Properties

    /// Whether to compress request bodies.
    public let compressRequests: Bool

    /// Whether to decompress response bodies.
    public let decompressResponses: Bool

    /// The compression algorithm to use for requests.
    public let requestAlgorithm: Algorithm

    /// Minimum request body size to trigger compression (in bytes).
    public let minCompressSize: Int

    /// Content types that should be compressed.
    public let compressibleContentTypes: Set<String>

    // MARK: - Initialization

    /// Creates a compression interceptor.
    ///
    /// - Parameters:
    ///   - compressRequests: Whether to compress requests. Defaults to true.
    ///   - decompressResponses: Whether to decompress responses. Defaults to true.
    ///   - algorithm: The compression algorithm. Defaults to gzip.
    ///   - minCompressSize: Minimum size for compression. Defaults to 1024 bytes.
    ///   - compressibleContentTypes: Content types to compress.
    public init(
        compressRequests: Bool = true,
        decompressResponses: Bool = true,
        algorithm: Algorithm = .gzip,
        minCompressSize: Int = 1024,
        compressibleContentTypes: Set<String> = [
            "application/json",
            "application/xml",
            "text/plain",
            "text/html",
            "text/xml"
        ]
    ) {
        self.compressRequests = compressRequests
        self.decompressResponses = decompressResponses
        self.requestAlgorithm = algorithm
        self.minCompressSize = minCompressSize
        self.compressibleContentTypes = compressibleContentTypes
    }

    // MARK: - NetworkInterceptor

    public func intercept(request: URLRequest) async throws -> URLRequest {
        var modified = request

        // Add Accept-Encoding header
        if decompressResponses {
            modified.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        }

        // Compress request body if applicable
        guard compressRequests,
              let body = request.httpBody,
              body.count >= minCompressSize,
              shouldCompress(contentType: request.value(forHTTPHeaderField: "Content-Type")) else {
            return modified
        }

        do {
            let compressed = try compress(body, algorithm: requestAlgorithm)

            // Only use compressed data if it's smaller
            if compressed.count < body.count {
                modified.httpBody = compressed
                modified.setValue(requestAlgorithm.rawValue, forHTTPHeaderField: "Content-Encoding")
                modified.setValue(String(compressed.count), forHTTPHeaderField: "Content-Length")
            }
        } catch {
            // If compression fails, send uncompressed
        }

        return modified
    }

    public func intercept(response: NetworkResponse) async throws -> NetworkResponse {
        guard decompressResponses,
              let encoding = response.headers["Content-Encoding"]?.lowercased(),
              !response.data.isEmpty else {
            return response
        }

        let algorithm: Algorithm?
        if encoding.contains("gzip") {
            algorithm = .gzip
        } else if encoding.contains("deflate") {
            algorithm = .deflate
        } else {
            algorithm = nil
        }

        guard let algo = algorithm else {
            return response
        }

        do {
            let decompressed = try decompress(response.data, algorithm: algo)

            var newHeaders = response.headers
            newHeaders.removeValue(forKey: "Content-Encoding")
            newHeaders["Content-Length"] = String(decompressed.count)

            return NetworkResponse(
                data: decompressed,
                statusCode: response.statusCode,
                headers: newHeaders,
                originalRequest: response.originalRequest,
                httpResponse: response.httpResponse
            )
        } catch {
            // Return original response if decompression fails
            return response
        }
    }

    // MARK: - Compression Utilities

    private func shouldCompress(contentType: String?) -> Bool {
        guard let contentType = contentType else { return false }
        let mimeType = contentType.split(separator: ";").first.map(String.init) ?? contentType
        return compressibleContentTypes.contains { mimeType.lowercased().contains($0) }
    }

    private func compress(_ data: Data, algorithm: Algorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipCompress(data)
        case .deflate, .zlib:
            return try zlibCompress(data)
        case .lz4:
            return try performCompression(data, algorithm: COMPRESSION_LZ4)
        case .lzma:
            return try performCompression(data, algorithm: COMPRESSION_LZMA)
        }
    }

    private func decompress(_ data: Data, algorithm: Algorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipDecompress(data)
        case .deflate, .zlib:
            return try zlibDecompress(data)
        case .lz4:
            return try performDecompression(data, algorithm: COMPRESSION_LZ4)
        case .lzma:
            return try performDecompression(data, algorithm: COMPRESSION_LZMA)
        }
    }

    // MARK: - GZIP Implementation

    private func gzipCompress(_ data: Data) throws -> Data {
        var compressed = Data()

        // GZIP header
        compressed.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00]) // Magic, method, flags
        compressed.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Modification time
        compressed.append(contentsOf: [0x00, 0x03]) // Extra flags, OS (Unix)

        // Compress the data using deflate
        let deflated = try performCompression(data, algorithm: COMPRESSION_ZLIB)
        compressed.append(deflated)

        // CRC32 and original size
        let crc = crc32(data)
        compressed.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
        let size = UInt32(data.count)
        compressed.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })

        return compressed
    }

    private func gzipDecompress(_ data: Data) throws -> Data {
        guard data.count >= 10 else {
            throw CompressionError.invalidInput
        }

        // Verify GZIP header
        guard data[0] == 0x1f, data[1] == 0x8b else {
            throw CompressionError.invalidGzipHeader
        }

        // Find the start of compressed data (after header)
        var dataStart = 10

        let flags = data[3]

        // Skip extra field
        if flags & 0x04 != 0 {
            guard data.count >= dataStart + 2 else { throw CompressionError.invalidInput }
            let extraLen = Int(data[dataStart]) | (Int(data[dataStart + 1]) << 8)
            dataStart += 2 + extraLen
        }

        // Skip original file name
        if flags & 0x08 != 0 {
            while dataStart < data.count && data[dataStart] != 0 {
                dataStart += 1
            }
            dataStart += 1
        }

        // Skip comment
        if flags & 0x10 != 0 {
            while dataStart < data.count && data[dataStart] != 0 {
                dataStart += 1
            }
            dataStart += 1
        }

        // Skip header CRC
        if flags & 0x02 != 0 {
            dataStart += 2
        }

        guard data.count >= dataStart + 8 else {
            throw CompressionError.invalidInput
        }

        // Extract compressed data (excluding trailer)
        let compressedData = data.subdata(in: dataStart..<(data.count - 8))

        return try performDecompression(compressedData, algorithm: COMPRESSION_ZLIB)
    }

    // MARK: - ZLIB Implementation

    private func zlibCompress(_ data: Data) throws -> Data {
        try performCompression(data, algorithm: COMPRESSION_ZLIB)
    }

    private func zlibDecompress(_ data: Data) throws -> Data {
        try performDecompression(data, algorithm: COMPRESSION_ZLIB)
    }

    // MARK: - Core Compression

    private func performCompression(_ data: Data, algorithm: compression_algorithm) throws -> Data {
        let destinationBufferSize = data.count + 512
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        let compressedSize = data.withUnsafeBytes { sourcePointer -> Int in
            guard let sourceBase = sourcePointer.baseAddress else { return 0 }
            return compression_encode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourceBase.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                algorithm
            )
        }

        guard compressedSize > 0 else {
            throw CompressionError.compressionFailed
        }

        return Data(destinationBuffer.prefix(compressedSize))
    }

    private func performDecompression(_ data: Data, algorithm: compression_algorithm) throws -> Data {
        // Start with 4x the compressed size
        var destinationBufferSize = data.count * 4
        var destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

        var decompressedSize = data.withUnsafeBytes { sourcePointer -> Int in
            guard let sourceBase = sourcePointer.baseAddress else { return 0 }
            return compression_decode_buffer(
                &destinationBuffer,
                destinationBufferSize,
                sourceBase.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                algorithm
            )
        }

        // If buffer was too small, try with larger buffer
        while decompressedSize == destinationBufferSize {
            destinationBufferSize *= 2
            destinationBuffer = [UInt8](repeating: 0, count: destinationBufferSize)

            decompressedSize = data.withUnsafeBytes { sourcePointer -> Int in
                guard let sourceBase = sourcePointer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    &destinationBuffer,
                    destinationBufferSize,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    algorithm
                )
            }
        }

        guard decompressedSize > 0 else {
            throw CompressionError.decompressionFailed
        }

        return Data(destinationBuffer.prefix(decompressedSize))
    }

    // MARK: - CRC32

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        let polynomial: UInt32 = 0xEDB88320

        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ polynomial
                } else {
                    crc >>= 1
                }
            }
        }

        return ~crc
    }
}

// MARK: - Compression Errors

/// Errors that can occur during compression operations.
public enum CompressionError: Error, Sendable {
    case invalidInput
    case invalidGzipHeader
    case compressionFailed
    case decompressionFailed
    case unsupportedAlgorithm
}

extension CompressionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid compression input data"
        case .invalidGzipHeader:
            return "Invalid GZIP header"
        case .compressionFailed:
            return "Compression operation failed"
        case .decompressionFailed:
            return "Decompression operation failed"
        case .unsupportedAlgorithm:
            return "Unsupported compression algorithm"
        }
    }
}

// MARK: - Data Extensions

extension Data {

    /// Compresses the data using gzip.
    ///
    /// - Returns: The compressed data.
    /// - Throws: If compression fails.
    public func gzipCompressed() throws -> Data {
        let interceptor = CompressionInterceptor()
        return try interceptor.compress(self, algorithm: .gzip)
    }

    /// Decompresses gzip data.
    ///
    /// - Returns: The decompressed data.
    /// - Throws: If decompression fails.
    public func gzipDecompressed() throws -> Data {
        let interceptor = CompressionInterceptor()
        return try interceptor.decompress(self, algorithm: .gzip)
    }

    /// Whether this data appears to be gzip compressed.
    public var isGzipCompressed: Bool {
        guard count >= 2 else { return false }
        return self[0] == 0x1f && self[1] == 0x8b
    }
}

// MARK: - Private Extension for Interceptor Access

private extension CompressionInterceptor {
    func compress(_ data: Data, algorithm: Algorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipCompress(data)
        case .deflate, .zlib:
            return try zlibCompress(data)
        case .lz4:
            return try performCompression(data, algorithm: COMPRESSION_LZ4)
        case .lzma:
            return try performCompression(data, algorithm: COMPRESSION_LZMA)
        }
    }

    func decompress(_ data: Data, algorithm: Algorithm) throws -> Data {
        switch algorithm {
        case .gzip:
            return try gzipDecompress(data)
        case .deflate, .zlib:
            return try zlibDecompress(data)
        case .lz4:
            return try performDecompression(data, algorithm: COMPRESSION_LZ4)
        case .lzma:
            return try performDecompression(data, algorithm: COMPRESSION_LZMA)
        }
    }
}
