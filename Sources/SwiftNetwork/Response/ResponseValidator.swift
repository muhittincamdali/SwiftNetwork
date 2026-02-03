import Foundation

/// A protocol for validating network responses.
///
/// Response validators check responses for expected conditions and can
/// transform errors into more meaningful types.
///
/// ```swift
/// let validator = CompositeValidator([
///     StatusCodeValidator(200...299),
///     ContentTypeValidator(expected: "application/json")
/// ])
///
/// try await validator.validate(response)
/// ```
public protocol ResponseValidator: Sendable {

    /// Validates a network response.
    ///
    /// - Parameter response: The response to validate.
    /// - Throws: A ``NetworkError`` if validation fails.
    func validate(_ response: NetworkResponse) async throws
}

// MARK: - Status Code Validator

/// Validates that the response status code falls within an acceptable range.
public struct StatusCodeValidator: ResponseValidator {

    /// The acceptable status codes.
    public let acceptableStatusCodes: Set<Int>

    /// Creates a validator for a range of status codes.
    ///
    /// - Parameter range: The range of acceptable status codes.
    public init(_ range: ClosedRange<Int>) {
        self.acceptableStatusCodes = Set(range)
    }

    /// Creates a validator for a half-open range of status codes.
    ///
    /// - Parameter range: The range of acceptable status codes.
    public init(_ range: Range<Int>) {
        self.acceptableStatusCodes = Set(range)
    }

    /// Creates a validator for specific status codes.
    ///
    /// - Parameter codes: The acceptable status codes.
    public init(_ codes: Int...) {
        self.acceptableStatusCodes = Set(codes)
    }

    /// Creates a validator for a set of status codes.
    ///
    /// - Parameter codes: The set of acceptable status codes.
    public init(_ codes: Set<Int>) {
        self.acceptableStatusCodes = codes
    }

    public func validate(_ response: NetworkResponse) async throws {
        guard acceptableStatusCodes.contains(response.statusCode) else {
            throw NetworkError.httpError(
                statusCode: response.statusCode,
                data: response.data
            )
        }
    }
}

// MARK: - Content Type Validator

/// Validates that the response has an expected content type.
public struct ContentTypeValidator: ResponseValidator {

    /// The expected content types.
    public let expectedContentTypes: [String]

    /// Whether to allow missing content type headers.
    public let allowMissingContentType: Bool

    /// Creates a content type validator.
    ///
    /// - Parameters:
    ///   - expected: The expected content type(s).
    ///   - allowMissing: Whether to allow missing content type. Defaults to false.
    public init(expected: String..., allowMissing: Bool = false) {
        self.expectedContentTypes = expected
        self.allowMissingContentType = allowMissing
    }

    /// Creates a content type validator from an array.
    ///
    /// - Parameters:
    ///   - expected: The expected content types.
    ///   - allowMissing: Whether to allow missing content type.
    public init(expected: [String], allowMissing: Bool = false) {
        self.expectedContentTypes = expected
        self.allowMissingContentType = allowMissing
    }

    public func validate(_ response: NetworkResponse) async throws {
        guard let contentType = response.headers["Content-Type"] else {
            if !allowMissingContentType {
                throw ResponseValidationError.missingContentType
            }
            return
        }

        // Extract the MIME type without parameters
        let mimeType = contentType.split(separator: ";").first.map(String.init) ?? contentType

        let isValid = expectedContentTypes.contains { expected in
            mimeType.lowercased() == expected.lowercased() ||
            mimeType.lowercased().hasPrefix(expected.lowercased())
        }

        guard isValid else {
            throw ResponseValidationError.unexpectedContentType(
                received: mimeType,
                expected: expectedContentTypes
            )
        }
    }
}

// MARK: - Content Length Validator

/// Validates that the response content length is within acceptable bounds.
public struct ContentLengthValidator: ResponseValidator {

    /// The minimum acceptable content length.
    public let minimumLength: Int?

    /// The maximum acceptable content length.
    public let maximumLength: Int?

    /// Creates a content length validator.
    ///
    /// - Parameters:
    ///   - minimum: The minimum length (inclusive). Defaults to nil.
    ///   - maximum: The maximum length (inclusive). Defaults to nil.
    public init(minimum: Int? = nil, maximum: Int? = nil) {
        self.minimumLength = minimum
        self.maximumLength = maximum
    }

    public func validate(_ response: NetworkResponse) async throws {
        let length = response.data.count

        if let minimum = minimumLength, length < minimum {
            throw ResponseValidationError.contentTooSmall(
                actual: length,
                minimum: minimum
            )
        }

        if let maximum = maximumLength, length > maximum {
            throw ResponseValidationError.contentTooLarge(
                actual: length,
                maximum: maximum
            )
        }
    }
}

// MARK: - Empty Response Validator

/// Validates that the response is not empty when data is expected.
public struct NonEmptyValidator: ResponseValidator {

    /// Creates a non-empty response validator.
    public init() {}

    public func validate(_ response: NetworkResponse) async throws {
        guard !response.data.isEmpty else {
            throw NetworkError.noData
        }
    }
}

// MARK: - Header Validator

/// Validates that specific headers are present in the response.
public struct HeaderValidator: ResponseValidator {

    /// The required headers and their expected values.
    public let requiredHeaders: [String: String?]

    /// Creates a header validator requiring specific header presence.
    ///
    /// - Parameter headers: The required headers. Value is optional for presence-only checks.
    public init(headers: [String: String?]) {
        self.requiredHeaders = headers
    }

    /// Creates a header validator requiring a header with a specific value.
    ///
    /// - Parameters:
    ///   - name: The header name.
    ///   - value: The expected value. Pass nil for presence-only check.
    public init(_ name: String, _ value: String? = nil) {
        self.requiredHeaders = [name: value]
    }

    public func validate(_ response: NetworkResponse) async throws {
        for (name, expectedValue) in requiredHeaders {
            guard let actualValue = response.headers[name] else {
                throw ResponseValidationError.missingHeader(name)
            }

            if let expected = expectedValue, actualValue != expected {
                throw ResponseValidationError.invalidHeaderValue(
                    header: name,
                    expected: expected,
                    actual: actualValue
                )
            }
        }
    }
}

// MARK: - JSON Validator

/// Validates that the response is valid JSON.
public struct JSONValidator: ResponseValidator {

    /// Whether the response must be a JSON object (vs array or primitive).
    public let requireObject: Bool

    /// Creates a JSON validator.
    ///
    /// - Parameter requireObject: Whether to require a JSON object. Defaults to false.
    public init(requireObject: Bool = false) {
        self.requireObject = requireObject
    }

    public func validate(_ response: NetworkResponse) async throws {
        guard !response.data.isEmpty else {
            throw ResponseValidationError.invalidJSON("Empty response")
        }

        do {
            let json = try JSONSerialization.jsonObject(with: response.data)

            if requireObject && !(json is [String: Any]) {
                throw ResponseValidationError.invalidJSON("Expected JSON object, got \(type(of: json))")
            }
        } catch let error as ResponseValidationError {
            throw error
        } catch {
            throw ResponseValidationError.invalidJSON(error.localizedDescription)
        }
    }
}

// MARK: - Schema Validator

/// Validates JSON responses against a simple schema.
public struct SchemaValidator: ResponseValidator {

    /// Schema definition for validation.
    public enum SchemaField: Sendable {
        case required(String)
        case optional(String)
        case requiredType(String, ExpectedType)
        case optionalType(String, ExpectedType)
    }

    /// Expected JSON types.
    public enum ExpectedType: Sendable {
        case string
        case number
        case boolean
        case object
        case array
        case null
    }

    /// The schema fields to validate.
    public let fields: [SchemaField]

    /// Creates a schema validator.
    ///
    /// - Parameter fields: The schema field definitions.
    public init(fields: [SchemaField]) {
        self.fields = fields
    }

    public func validate(_ response: NetworkResponse) async throws {
        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw ResponseValidationError.invalidJSON("Expected JSON object")
        }

        for field in fields {
            switch field {
            case .required(let name):
                guard json[name] != nil else {
                    throw ResponseValidationError.schemaMismatch("Missing required field: \(name)")
                }

            case .requiredType(let name, let expectedType):
                guard let value = json[name] else {
                    throw ResponseValidationError.schemaMismatch("Missing required field: \(name)")
                }
                try validateType(value, expected: expectedType, field: name)

            case .optional(let name):
                // Field is optional, no validation needed for presence
                break

            case .optionalType(let name, let expectedType):
                if let value = json[name] {
                    try validateType(value, expected: expectedType, field: name)
                }
            }
        }
    }

    private func validateType(_ value: Any, expected: ExpectedType, field: String) throws {
        let isValid: Bool = switch expected {
        case .string:
            value is String
        case .number:
            value is NSNumber
        case .boolean:
            value is Bool
        case .object:
            value is [String: Any]
        case .array:
            value is [Any]
        case .null:
            value is NSNull
        }

        guard isValid else {
            throw ResponseValidationError.schemaMismatch(
                "Field '\(field)' expected \(expected), got \(type(of: value))"
            )
        }
    }
}

// MARK: - Composite Validator

/// Combines multiple validators into one.
public struct CompositeValidator: ResponseValidator {

    /// The validators to run.
    public let validators: [any ResponseValidator]

    /// Whether to stop on first failure.
    public let stopOnFirstFailure: Bool

    /// Creates a composite validator.
    ///
    /// - Parameters:
    ///   - validators: The validators to combine.
    ///   - stopOnFirstFailure: Whether to stop at first failure. Defaults to true.
    public init(_ validators: [any ResponseValidator], stopOnFirstFailure: Bool = true) {
        self.validators = validators
        self.stopOnFirstFailure = stopOnFirstFailure
    }

    /// Creates a composite validator from variadic validators.
    ///
    /// - Parameter validators: The validators to combine.
    public init(_ validators: any ResponseValidator...) {
        self.validators = validators
        self.stopOnFirstFailure = true
    }

    public func validate(_ response: NetworkResponse) async throws {
        var errors: [Error] = []

        for validator in validators {
            do {
                try await validator.validate(response)
            } catch {
                if stopOnFirstFailure {
                    throw error
                }
                errors.append(error)
            }
        }

        if !errors.isEmpty {
            throw ResponseValidationError.multipleFailures(errors)
        }
    }
}

// MARK: - Conditional Validator

/// Applies validation conditionally.
public struct ConditionalValidator: ResponseValidator {

    /// The condition to check.
    private let condition: @Sendable (NetworkResponse) -> Bool

    /// The validator to apply when condition is true.
    private let validator: any ResponseValidator

    /// Creates a conditional validator.
    ///
    /// - Parameters:
    ///   - condition: The condition to check.
    ///   - validator: The validator to apply.
    public init(
        when condition: @escaping @Sendable (NetworkResponse) -> Bool,
        then validator: any ResponseValidator
    ) {
        self.condition = condition
        self.validator = validator
    }

    public func validate(_ response: NetworkResponse) async throws {
        if condition(response) {
            try await validator.validate(response)
        }
    }
}

// MARK: - Block Validator

/// A validator that uses a closure for custom validation.
public struct BlockValidator: ResponseValidator {

    /// The validation closure.
    private let validationBlock: @Sendable (NetworkResponse) async throws -> Void

    /// Creates a block validator.
    ///
    /// - Parameter block: The validation closure.
    public init(_ block: @escaping @Sendable (NetworkResponse) async throws -> Void) {
        self.validationBlock = block
    }

    public func validate(_ response: NetworkResponse) async throws {
        try await validationBlock(response)
    }
}

// MARK: - Validation Errors

/// Errors specific to response validation.
public enum ResponseValidationError: Error, Sendable {
    /// The content type header is missing.
    case missingContentType

    /// The content type doesn't match expected values.
    case unexpectedContentType(received: String, expected: [String])

    /// The content is smaller than the minimum allowed.
    case contentTooSmall(actual: Int, minimum: Int)

    /// The content is larger than the maximum allowed.
    case contentTooLarge(actual: Int, maximum: Int)

    /// A required header is missing.
    case missingHeader(String)

    /// A header has an unexpected value.
    case invalidHeaderValue(header: String, expected: String, actual: String)

    /// The response is not valid JSON.
    case invalidJSON(String)

    /// The response doesn't match the expected schema.
    case schemaMismatch(String)

    /// Multiple validation failures occurred.
    case multipleFailures([Error])
}

extension ResponseValidationError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .missingContentType:
            return "Response is missing Content-Type header"
        case .unexpectedContentType(let received, let expected):
            return "Expected content type \(expected.joined(separator: " or ")), got \(received)"
        case .contentTooSmall(let actual, let minimum):
            return "Content length \(actual) is below minimum \(minimum)"
        case .contentTooLarge(let actual, let maximum):
            return "Content length \(actual) exceeds maximum \(maximum)"
        case .missingHeader(let name):
            return "Missing required header: \(name)"
        case .invalidHeaderValue(let header, let expected, let actual):
            return "Header '\(header)' expected '\(expected)', got '\(actual)'"
        case .invalidJSON(let reason):
            return "Invalid JSON: \(reason)"
        case .schemaMismatch(let reason):
            return "Schema validation failed: \(reason)"
        case .multipleFailures(let errors):
            return "Multiple validation failures: \(errors.map { $0.localizedDescription }.joined(separator: "; "))"
        }
    }
}

// MARK: - Preset Validators

extension ResponseValidator where Self == StatusCodeValidator {

    /// Validates successful HTTP responses (200-299).
    public static var success: StatusCodeValidator {
        StatusCodeValidator(200...299)
    }

    /// Validates any non-error response (200-399).
    public static var nonError: StatusCodeValidator {
        StatusCodeValidator(200...399)
    }
}

extension ResponseValidator where Self == ContentTypeValidator {

    /// Validates JSON content type.
    public static var json: ContentTypeValidator {
        ContentTypeValidator(expected: "application/json", "text/json")
    }

    /// Validates HTML content type.
    public static var html: ContentTypeValidator {
        ContentTypeValidator(expected: "text/html")
    }

    /// Validates XML content type.
    public static var xml: ContentTypeValidator {
        ContentTypeValidator(expected: "application/xml", "text/xml")
    }
}
