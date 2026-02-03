import Foundation

/// Represents a WebSocket message with type information and utilities.
///
/// `WebSocketMessage` provides a rich interface for working with
/// WebSocket messages including serialization and type conversion.
///
/// ```swift
/// let message = WebSocketMessage.text("Hello, World!")
/// let jsonMessage = try WebSocketMessage.json(["action": "ping"])
///
/// switch message {
/// case .text(let string):
///     print("Received text: \(string)")
/// case .binary(let data):
///     print("Received \(data.count) bytes")
/// }
/// ```
public enum WebSocketMessage: Sendable, Equatable {

    /// A text message.
    case text(String)

    /// A binary data message.
    case binary(Data)

    // MARK: - Initialization

    /// Creates a text message.
    ///
    /// - Parameter string: The text content.
    /// - Returns: A text message.
    public static func text(_ string: String) -> WebSocketMessage {
        .text(string)
    }

    /// Creates a binary message.
    ///
    /// - Parameter data: The binary content.
    /// - Returns: A binary message.
    public static func binary(_ data: Data) -> WebSocketMessage {
        .binary(data)
    }

    /// Creates a JSON message from an encodable value.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - encoder: The JSON encoder.
    /// - Returns: A text message containing JSON.
    /// - Throws: Encoding errors.
    public static func json<T: Encodable>(
        _ value: T,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> WebSocketMessage {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WebSocketMessageError.encodingFailed
        }
        return .text(string)
    }

    /// Creates a JSON message from a dictionary.
    ///
    /// - Parameter dictionary: The dictionary to encode.
    /// - Returns: A text message containing JSON.
    /// - Throws: Encoding errors.
    public static func json(_ dictionary: [String: Any]) throws -> WebSocketMessage {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        guard let string = String(data: data, encoding: .utf8) else {
            throw WebSocketMessageError.encodingFailed
        }
        return .text(string)
    }

    // MARK: - Properties

    /// Whether this is a text message.
    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    /// Whether this is a binary message.
    public var isBinary: Bool {
        if case .binary = self { return true }
        return false
    }

    /// The text content if this is a text message.
    public var textValue: String? {
        if case .text(let string) = self { return string }
        return nil
    }

    /// The binary content if this is a binary message.
    public var binaryValue: Data? {
        if case .binary(let data) = self { return data }
        return nil
    }

    /// The message size in bytes.
    public var size: Int {
        switch self {
        case .text(let string):
            return string.utf8.count
        case .binary(let data):
            return data.count
        }
    }

    // MARK: - Conversion

    /// Converts the message to data.
    public var data: Data {
        switch self {
        case .text(let string):
            return string.data(using: .utf8) ?? Data()
        case .binary(let data):
            return data
        }
    }

    /// Converts the message to a string.
    ///
    /// For binary messages, attempts UTF-8 decoding.
    public var string: String? {
        switch self {
        case .text(let string):
            return string
        case .binary(let data):
            return String(data: data, encoding: .utf8)
        }
    }

    /// Decodes the message as JSON.
    ///
    /// - Parameter type: The type to decode to.
    /// - Returns: The decoded value.
    /// - Throws: Decoding errors.
    public func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let messageData: Data
        switch self {
        case .text(let string):
            guard let data = string.data(using: .utf8) else {
                throw WebSocketMessageError.decodingFailed
            }
            messageData = data
        case .binary(let data):
            messageData = data
        }
        return try decoder.decode(type, from: messageData)
    }

    /// Decodes the message as a JSON dictionary.
    ///
    /// - Returns: The JSON dictionary.
    /// - Throws: Decoding errors.
    public func decodeDictionary() throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebSocketMessageError.invalidJSON
        }
        return json
    }

    /// Decodes the message as a JSON array.
    ///
    /// - Returns: The JSON array.
    /// - Throws: Decoding errors.
    public func decodeArray() throws -> [Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw WebSocketMessageError.invalidJSON
        }
        return json
    }
}

// MARK: - WebSocket Message Error

/// Errors related to WebSocket message handling.
public enum WebSocketMessageError: Error, Sendable {
    case encodingFailed
    case decodingFailed
    case invalidJSON
    case messageTooLarge
}

extension WebSocketMessageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode message"
        case .decodingFailed:
            return "Failed to decode message"
        case .invalidJSON:
            return "Message is not valid JSON"
        case .messageTooLarge:
            return "Message exceeds size limit"
        }
    }
}

// MARK: - CustomStringConvertible

extension WebSocketMessage: CustomStringConvertible {

    public var description: String {
        switch self {
        case .text(let string):
            if string.count > 100 {
                return "text(\(string.prefix(100))...)"
            }
            return "text(\(string))"
        case .binary(let data):
            return "binary(\(data.count) bytes)"
        }
    }
}

// MARK: - Message Frame

/// Represents a WebSocket frame for low-level handling.
public struct WebSocketFrame: Sendable {

    /// Frame opcode types.
    public enum Opcode: UInt8, Sendable {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    /// The frame opcode.
    public let opcode: Opcode

    /// Whether this is a final frame.
    public let isFinal: Bool

    /// The payload data.
    public let payload: Data

    /// The mask key if masked.
    public let maskKey: [UInt8]?

    /// Creates a WebSocket frame.
    public init(
        opcode: Opcode,
        isFinal: Bool = true,
        payload: Data,
        maskKey: [UInt8]? = nil
    ) {
        self.opcode = opcode
        self.isFinal = isFinal
        self.payload = payload
        self.maskKey = maskKey
    }

    /// Converts to a WebSocketMessage.
    public var message: WebSocketMessage? {
        switch opcode {
        case .text:
            guard let string = String(data: payload, encoding: .utf8) else { return nil }
            return .text(string)
        case .binary:
            return .binary(payload)
        default:
            return nil
        }
    }
}

// MARK: - Message Queue

/// A thread-safe queue for WebSocket messages.
public actor WebSocketMessageQueue {

    private var messages: [WebSocketMessage] = []
    private let maxSize: Int

    /// Creates a message queue.
    ///
    /// - Parameter maxSize: Maximum queue size. Defaults to 1000.
    public init(maxSize: Int = 1000) {
        self.maxSize = maxSize
    }

    /// Enqueues a message.
    ///
    /// - Parameter message: The message to enqueue.
    /// - Returns: True if successful, false if queue is full.
    @discardableResult
    public func enqueue(_ message: WebSocketMessage) -> Bool {
        guard messages.count < maxSize else { return false }
        messages.append(message)
        return true
    }

    /// Dequeues the next message.
    ///
    /// - Returns: The next message, or nil if empty.
    public func dequeue() -> WebSocketMessage? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }

    /// Peeks at the next message without removing it.
    public var peek: WebSocketMessage? {
        messages.first
    }

    /// The number of messages in the queue.
    public var count: Int {
        messages.count
    }

    /// Whether the queue is empty.
    public var isEmpty: Bool {
        messages.isEmpty
    }

    /// Whether the queue is full.
    public var isFull: Bool {
        messages.count >= maxSize
    }

    /// Clears all messages.
    public func clear() {
        messages.removeAll()
    }
}
