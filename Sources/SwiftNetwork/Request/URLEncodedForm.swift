import Foundation

/// Represents URL-encoded form data for HTTP request bodies.
///
/// `URLEncodedForm` handles the encoding of key-value pairs into the standard
/// `application/x-www-form-urlencoded` format used by HTML forms.
///
/// ```swift
/// let form = URLEncodedForm()
///     .add("username", "john_doe")
///     .add("password", "secret123")
///     .add("remember", "true")
///
/// var request = URLRequest(url: url)
/// request.httpBody = form.encode()
/// request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
/// ```
public struct URLEncodedForm: Sendable {

    // MARK: - Types

    /// Encoding options for URL-encoded form data.
    public struct EncodingOptions: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Encode spaces as `+` instead of `%20`.
        public static let spacesAsPlus = EncodingOptions(rawValue: 1 << 0)

        /// Sort parameters alphabetically by key.
        public static let sortedKeys = EncodingOptions(rawValue: 1 << 1)

        /// Skip nil values entirely.
        public static let skipNilValues = EncodingOptions(rawValue: 1 << 2)

        /// Encode arrays with bracket notation (key[]=value).
        public static let arrayBrackets = EncodingOptions(rawValue: 1 << 3)

        /// Encode booleans as "1" and "0" instead of "true" and "false".
        public static let numericBooleans = EncodingOptions(rawValue: 1 << 4)

        /// Default encoding options.
        public static let `default`: EncodingOptions = []
    }

    /// A single form field.
    public struct Field: Sendable, Equatable {
        /// The field name.
        public let name: String

        /// The field value.
        public let value: String?

        /// Creates a new form field.
        public init(name: String, value: String?) {
            self.name = name
            self.value = value
        }
    }

    // MARK: - Properties

    /// The content type header value for URL-encoded forms.
    public static let contentTypeHeader = "application/x-www-form-urlencoded"

    /// The content type for this form.
    public var contentType: String { Self.contentTypeHeader }

    /// The encoding options to use.
    public let options: EncodingOptions

    /// The form fields.
    public private(set) var fields: [Field]

    /// Character set allowed in URL-encoded form values.
    private static let allowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    // MARK: - Initialization

    /// Creates an empty URL-encoded form.
    ///
    /// - Parameter options: Encoding options to use. Defaults to `.default`.
    public init(options: EncodingOptions = .default) {
        self.options = options
        self.fields = []
    }

    /// Creates a URL-encoded form from a dictionary.
    ///
    /// - Parameters:
    ///   - dictionary: Key-value pairs to encode.
    ///   - options: Encoding options to use.
    public init(dictionary: [String: Any], options: EncodingOptions = .default) {
        self.options = options
        self.fields = []
        addDictionary(dictionary)
    }

    /// Creates a URL-encoded form from an Encodable value.
    ///
    /// - Parameters:
    ///   - value: The encodable value.
    ///   - options: Encoding options to use.
    /// - Throws: Encoding errors.
    public init<T: Encodable>(from value: T, options: EncodingOptions = .default) throws {
        self.options = options
        self.fields = []

        let encoder = FormURLEncoder()
        let encoded = try encoder.encode(value)
        for (key, value) in encoded {
            fields.append(Field(name: key, value: value))
        }
    }

    // MARK: - Adding Fields

    /// Adds a string field to the form.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The field value.
    /// - Returns: A new form with the added field.
    public func add(_ name: String, _ value: String) -> URLEncodedForm {
        var copy = self
        copy.fields.append(Field(name: name, value: value))
        return copy
    }

    /// Adds an optional string field to the form.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The optional field value.
    /// - Returns: A new form with the added field.
    public func add(_ name: String, _ value: String?) -> URLEncodedForm {
        if options.contains(.skipNilValues) && value == nil {
            return self
        }
        var copy = self
        copy.fields.append(Field(name: name, value: value))
        return copy
    }

    /// Adds an integer field to the form.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The integer value.
    /// - Returns: A new form with the added field.
    public func add(_ name: String, _ value: Int) -> URLEncodedForm {
        add(name, String(value))
    }

    /// Adds a double field to the form.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The double value.
    /// - Returns: A new form with the added field.
    public func add(_ name: String, _ value: Double) -> URLEncodedForm {
        add(name, String(value))
    }

    /// Adds a boolean field to the form.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The boolean value.
    /// - Returns: A new form with the added field.
    public func add(_ name: String, _ value: Bool) -> URLEncodedForm {
        let stringValue: String
        if options.contains(.numericBooleans) {
            stringValue = value ? "1" : "0"
        } else {
            stringValue = value ? "true" : "false"
        }
        return add(name, stringValue)
    }

    /// Adds an array of values with the same name.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - values: The array of values.
    /// - Returns: A new form with the added fields.
    public func add(_ name: String, _ values: [String]) -> URLEncodedForm {
        var copy = self
        let fieldName = options.contains(.arrayBrackets) ? "\(name)[]" : name
        for value in values {
            copy.fields.append(Field(name: fieldName, value: value))
        }
        return copy
    }

    /// Adds a date field to the form.
    ///
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The date value.
    ///   - formatter: The date formatter to use. Defaults to ISO8601.
    /// - Returns: A new form with the added field.
    public func add(_ name: String, _ value: Date, formatter: DateFormatter? = nil) -> URLEncodedForm {
        let dateFormatter = formatter ?? {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            f.timeZone = TimeZone(identifier: "UTC")
            return f
        }()
        return add(name, dateFormatter.string(from: value))
    }

    // MARK: - Dictionary Support

    /// Adds all key-value pairs from a dictionary.
    ///
    /// - Parameter dictionary: The dictionary to add.
    private mutating func addDictionary(_ dictionary: [String: Any]) {
        for (key, value) in dictionary {
            addValue(value, forKey: key)
        }
    }

    private mutating func addValue(_ value: Any, forKey key: String) {
        switch value {
        case let string as String:
            fields.append(Field(name: key, value: string))
        case let int as Int:
            fields.append(Field(name: key, value: String(int)))
        case let double as Double:
            fields.append(Field(name: key, value: String(double)))
        case let bool as Bool:
            let stringValue = options.contains(.numericBooleans) ? (bool ? "1" : "0") : (bool ? "true" : "false")
            fields.append(Field(name: key, value: stringValue))
        case let array as [Any]:
            let fieldName = options.contains(.arrayBrackets) ? "\(key)[]" : key
            for item in array {
                addValue(item, forKey: fieldName)
            }
        case let dict as [String: Any]:
            for (nestedKey, nestedValue) in dict {
                addValue(nestedValue, forKey: "\(key)[\(nestedKey)]")
            }
        case is NSNull:
            if !options.contains(.skipNilValues) {
                fields.append(Field(name: key, value: nil))
            }
        default:
            fields.append(Field(name: key, value: String(describing: value)))
        }
    }

    // MARK: - Encoding

    /// Encodes the form to data.
    ///
    /// - Returns: The encoded form data.
    public func encode() -> Data {
        let string = encodeToString()
        return string.data(using: .utf8) ?? Data()
    }

    /// Encodes the form to a string.
    ///
    /// - Returns: The encoded form string.
    public func encodeToString() -> String {
        var fieldsToEncode = fields

        if options.contains(.sortedKeys) {
            fieldsToEncode.sort { $0.name < $1.name }
        }

        let pairs = fieldsToEncode.compactMap { field -> String? in
            guard let encodedName = percentEncode(field.name) else { return nil }

            if let value = field.value {
                guard let encodedValue = percentEncode(value) else { return nil }
                return "\(encodedName)=\(encodedValue)"
            } else {
                return "\(encodedName)="
            }
        }

        return pairs.joined(separator: "&")
    }

    /// Percent-encodes a string for URL form encoding.
    ///
    /// - Parameter string: The string to encode.
    /// - Returns: The encoded string, or nil if encoding fails.
    private func percentEncode(_ string: String) -> String? {
        var encoded = string.addingPercentEncoding(withAllowedCharacters: Self.allowedCharacters)

        if options.contains(.spacesAsPlus) {
            encoded = encoded?.replacingOccurrences(of: "%20", with: "+")
        }

        return encoded
    }

    // MARK: - Decoding

    /// Decodes a URL-encoded string into field pairs.
    ///
    /// - Parameter string: The URL-encoded string.
    /// - Returns: A new form with the decoded fields.
    public static func decode(_ string: String) -> URLEncodedForm {
        var form = URLEncodedForm()

        let pairs = string.split(separator: "&")
        for pair in pairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            guard let name = components.first else { continue }

            let decodedName = String(name)
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? String(name)

            let value: String?
            if components.count > 1 {
                let rawValue = String(components[1])
                value = rawValue
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? rawValue
            } else {
                value = nil
            }

            form.fields.append(Field(name: decodedName, value: value))
        }

        return form
    }

    /// Decodes a URL-encoded form into a dictionary.
    ///
    /// - Parameter string: The URL-encoded string.
    /// - Returns: A dictionary of the decoded values.
    public static func decodeToDictionary(_ string: String) -> [String: Any] {
        let form = decode(string)
        var result: [String: Any] = [:]
        var arrays: [String: [String]] = [:]

        for field in form.fields {
            let name = field.name
            let value = field.value ?? ""

            // Handle array notation
            if name.hasSuffix("[]") {
                let baseName = String(name.dropLast(2))
                arrays[baseName, default: []].append(value)
            } else if let existing = result[name] {
                // Multiple values for same key become array
                if var array = existing as? [String] {
                    array.append(value)
                    result[name] = array
                } else if let string = existing as? String {
                    result[name] = [string, value]
                }
            } else {
                result[name] = value
            }
        }

        // Merge arrays into result
        for (key, values) in arrays {
            result[key] = values
        }

        return result
    }
}

// MARK: - Form URL Encoder

/// Internal encoder for converting Encodable values to form fields.
private class FormURLEncoder {

    func encode<T: Encodable>(_ value: T) throws -> [(String, String)] {
        let encoder = _FormEncoder()
        try value.encode(to: encoder)
        return encoder.result
    }
}

private class _FormEncoder: Encoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var result: [(String, String)] = []

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(_FormKeyedContainer(encoder: self, codingPath: codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        _FormUnkeyedContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        _FormSingleValueContainer(encoder: self, codingPath: codingPath)
    }

    func keyPath() -> String {
        codingPath.map { $0.stringValue }.joined(separator: ".")
    }
}

private struct _FormKeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: _FormEncoder
    var codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws {}

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, value ? "true" : "false"))
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, value))
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        let keyPath = buildKeyPath(key)
        encoder.result.append((keyPath, String(value)))
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        try value.encode(to: encoder)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        encoder.codingPath.append(key)
        return KeyedEncodingContainer(_FormKeyedContainer<NestedKey>(encoder: encoder, codingPath: encoder.codingPath))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        encoder.codingPath.append(key)
        return _FormUnkeyedContainer(encoder: encoder, codingPath: encoder.codingPath)
    }

    mutating func superEncoder() -> Encoder { encoder }
    mutating func superEncoder(forKey key: Key) -> Encoder { encoder }

    private func buildKeyPath(_ key: Key) -> String {
        if codingPath.isEmpty {
            return key.stringValue
        }
        return (codingPath.map { $0.stringValue } + [key.stringValue]).joined(separator: ".")
    }
}

private struct _FormUnkeyedContainer: UnkeyedEncodingContainer {
    let encoder: _FormEncoder
    var codingPath: [CodingKey]
    var count: Int = 0

    mutating func encodeNil() throws {}
    mutating func encode(_ value: Bool) throws { try encodeValue(value ? "true" : "false") }
    mutating func encode(_ value: String) throws { try encodeValue(value) }
    mutating func encode(_ value: Double) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: Float) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: Int) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: Int8) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: Int16) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: Int32) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: Int64) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: UInt) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: UInt8) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: UInt16) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: UInt32) throws { try encodeValue(String(value)) }
    mutating func encode(_ value: UInt64) throws { try encodeValue(String(value)) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        defer { count += 1 }
        try value.encode(to: encoder)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(_FormKeyedContainer<NestedKey>(encoder: encoder, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        _FormUnkeyedContainer(encoder: encoder, codingPath: codingPath)
    }

    mutating func superEncoder() -> Encoder { encoder }

    private mutating func encodeValue(_ value: String) throws {
        let keyPath = codingPath.map { $0.stringValue }.joined(separator: ".") + "[\(count)]"
        encoder.result.append((keyPath, value))
        count += 1
    }
}

private struct _FormSingleValueContainer: SingleValueEncodingContainer {
    let encoder: _FormEncoder
    var codingPath: [CodingKey]

    mutating func encodeNil() throws {}
    mutating func encode(_ value: Bool) throws { encodeValue(value ? "true" : "false") }
    mutating func encode(_ value: String) throws { encodeValue(value) }
    mutating func encode(_ value: Double) throws { encodeValue(String(value)) }
    mutating func encode(_ value: Float) throws { encodeValue(String(value)) }
    mutating func encode(_ value: Int) throws { encodeValue(String(value)) }
    mutating func encode(_ value: Int8) throws { encodeValue(String(value)) }
    mutating func encode(_ value: Int16) throws { encodeValue(String(value)) }
    mutating func encode(_ value: Int32) throws { encodeValue(String(value)) }
    mutating func encode(_ value: Int64) throws { encodeValue(String(value)) }
    mutating func encode(_ value: UInt) throws { encodeValue(String(value)) }
    mutating func encode(_ value: UInt8) throws { encodeValue(String(value)) }
    mutating func encode(_ value: UInt16) throws { encodeValue(String(value)) }
    mutating func encode(_ value: UInt32) throws { encodeValue(String(value)) }
    mutating func encode(_ value: UInt64) throws { encodeValue(String(value)) }
    mutating func encode<T: Encodable>(_ value: T) throws { try value.encode(to: encoder) }

    private func encodeValue(_ value: String) {
        let keyPath = codingPath.map { $0.stringValue }.joined(separator: ".")
        encoder.result.append((keyPath, value))
    }
}
