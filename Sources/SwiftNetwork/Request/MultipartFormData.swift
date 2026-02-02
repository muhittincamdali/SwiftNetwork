import Foundation

/// Constructs multipart/form-data payloads for file uploads and mixed content requests.
///
/// ```swift
/// var multipart = MultipartFormData()
/// multipart.append(data: imageData, name: "photo", fileName: "pic.jpg", mimeType: "image/jpeg")
/// multipart.append(value: "Hello", name: "caption")
///
/// let response: UploadResult = try await client.upload(
///     path: "/upload",
///     multipart: multipart
/// )
/// ```
public struct MultipartFormData: Sendable {

    // MARK: - Types

    /// A single part within the multipart body.
    private struct Part: Sendable {
        let headers: String
        let body: Data
    }

    // MARK: - Properties

    /// The multipart boundary string used to separate parts.
    public let boundary: String

    /// The complete Content-Type header value including the boundary.
    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Accumulated parts.
    private var parts: [Part] = []

    // MARK: - Initialization

    /// Creates a new multipart form data builder with a unique boundary.
    ///
    /// - Parameter boundary: A custom boundary string. Defaults to a UUID-based boundary.
    public init(boundary: String = "SwiftNetwork-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    // MARK: - Appending Data

    /// Appends a file data part.
    ///
    /// - Parameters:
    ///   - data: The file data to include.
    ///   - name: The form field name.
    ///   - fileName: The original file name.
    ///   - mimeType: The MIME type of the file (e.g., "image/jpeg").
    public mutating func append(data: Data, name: String, fileName: String, mimeType: String) {
        var header = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n"
        parts.append(Part(headers: header, body: data))
    }

    /// Appends a simple text value.
    ///
    /// - Parameters:
    ///   - value: The string value.
    ///   - name: The form field name.
    public mutating func append(value: String, name: String) {
        let header = "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        let body = Data(value.utf8)
        parts.append(Part(headers: header, body: body))
    }

    /// Appends raw data with a custom content type.
    ///
    /// - Parameters:
    ///   - data: The raw data to include.
    ///   - name: The form field name.
    ///   - contentType: The MIME type of the data.
    public mutating func append(data: Data, name: String, contentType: String) {
        var header = "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        header += "Content-Type: \(contentType)\r\n"
        parts.append(Part(headers: header, body: data))
    }

    /// Appends the contents of a file at the given URL.
    ///
    /// - Parameters:
    ///   - fileURL: The local file URL to read.
    ///   - name: The form field name.
    ///   - fileName: The file name to report. Defaults to the URL's last path component.
    ///   - mimeType: The MIME type. Defaults to "application/octet-stream".
    /// - Throws: If the file cannot be read.
    public mutating func append(
        fileURL: URL,
        name: String,
        fileName: String? = nil,
        mimeType: String = "application/octet-stream"
    ) throws {
        let data = try Data(contentsOf: fileURL)
        let resolvedFileName = fileName ?? fileURL.lastPathComponent
        append(data: data, name: name, fileName: resolvedFileName, mimeType: mimeType)
    }

    // MARK: - Encoding

    /// Encodes all parts into the final multipart/form-data body.
    ///
    /// - Returns: The encoded body data ready for transmission.
    public func encode() -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        let lineBreak = "\r\n"

        for part in parts {
            body.append(Data(boundaryPrefix.utf8))
            body.append(Data(part.headers.utf8))
            body.append(Data(lineBreak.utf8))
            body.append(part.body)
            body.append(Data(lineBreak.utf8))
        }

        let closingBoundary = "--\(boundary)--\r\n"
        body.append(Data(closingBoundary.utf8))

        return body
    }

    /// Returns the total size of the encoded body in bytes.
    public var encodedSize: Int {
        encode().count
    }

    /// Whether this multipart form data has any parts.
    public var isEmpty: Bool {
        parts.isEmpty
    }

    /// The number of parts added so far.
    public var partCount: Int {
        parts.count
    }
}
