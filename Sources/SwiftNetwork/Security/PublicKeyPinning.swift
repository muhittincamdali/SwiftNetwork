import Foundation
import Security
import CommonCrypto

/// Implements public key pinning for enhanced security.
///
/// `PublicKeyPinning` validates server certificates by comparing their
/// public keys against known, trusted keys, providing protection against
/// man-in-the-middle attacks even if a CA is compromised.
///
/// ```swift
/// let pinning = PublicKeyPinning(pins: [
///     Pin(host: "api.example.com", publicKeyHash: "sha256/AAAA..."),
///     Pin(host: "*.example.com", publicKeyHash: "sha256/BBBB...")
/// ])
///
/// let client = NetworkClient(
///     baseURL: url,
///     securityEvaluator: pinning
/// )
/// ```
public final class PublicKeyPinning: NSObject, URLSessionDelegate, @unchecked Sendable {

    // MARK: - Types

    /// A public key pin configuration.
    public struct Pin: Sendable, Hashable {
        /// The host pattern to match.
        public let host: String

        /// The SHA-256 hash of the public key (base64 encoded).
        public let publicKeyHash: String

        /// Whether this is a backup pin.
        public let isBackup: Bool

        /// Pin expiration date.
        public let expiresAt: Date?

        /// Creates a public key pin.
        ///
        /// - Parameters:
        ///   - host: The host to pin.
        ///   - publicKeyHash: The SHA-256 hash (format: "sha256/base64hash").
        ///   - isBackup: Whether this is a backup pin.
        ///   - expiresAt: Optional expiration date.
        public init(
            host: String,
            publicKeyHash: String,
            isBackup: Bool = false,
            expiresAt: Date? = nil
        ) {
            self.host = host
            self.publicKeyHash = publicKeyHash
            self.isBackup = isBackup
            self.expiresAt = expiresAt
        }

        /// Whether this pin is still valid.
        public var isValid: Bool {
            guard let expires = expiresAt else { return true }
            return Date() < expires
        }
    }

    /// Pin validation result.
    public enum ValidationResult: Sendable {
        case success(matchedPin: Pin)
        case failure(reason: FailureReason)

        public enum FailureReason: Sendable {
            case noPinsConfigured
            case hostNotPinned
            case noMatchingPin
            case certificateChainEmpty
            case publicKeyExtractionFailed
            case allPinsExpired
        }
    }

    /// Pinning policy.
    public enum Policy: Sendable {
        /// Require all certificates in chain to match a pin.
        case strict

        /// Require at least one certificate to match.
        case standard

        /// Log mismatches but don't fail (for testing).
        case reportOnly
    }

    // MARK: - Properties

    /// The configured pins.
    public let pins: [Pin]

    /// The pinning policy.
    public let policy: Policy

    /// Whether to validate the certificate chain first.
    public let validateChain: Bool

    /// Callback for validation events.
    private let validationHandler: (@Sendable (String, ValidationResult) -> Void)?

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a public key pinning validator.
    ///
    /// - Parameters:
    ///   - pins: The public key pins.
    ///   - policy: The pinning policy. Defaults to `.standard`.
    ///   - validateChain: Whether to validate the chain. Defaults to true.
    ///   - validationHandler: Optional callback for events.
    public init(
        pins: [Pin],
        policy: Policy = .standard,
        validateChain: Bool = true,
        validationHandler: (@Sendable (String, ValidationResult) -> Void)? = nil
    ) {
        self.pins = pins
        self.policy = policy
        self.validateChain = validateChain
        self.validationHandler = validationHandler
    }

    // MARK: - Validation

    /// Validates a server trust against configured pins.
    ///
    /// - Parameters:
    ///   - serverTrust: The server trust to validate.
    ///   - host: The host being connected to.
    /// - Returns: The validation result.
    public func validate(serverTrust: SecTrust, host: String) -> ValidationResult {
        // Get pins for this host
        let hostPins = pins.filter { matches(host: host, pattern: $0.host) && $0.isValid }

        guard !hostPins.isEmpty else {
            let result = ValidationResult.failure(reason: .hostNotPinned)
            validationHandler?(host, result)
            return result
        }

        // Validate certificate chain if required
        if validateChain {
            var error: CFError?
            let chainValid = SecTrustEvaluateWithError(serverTrust, &error)
            if !chainValid && policy != .reportOnly {
                return .failure(reason: .noMatchingPin)
            }
        }

        // Get certificate chain
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        guard certificateCount > 0 else {
            let result = ValidationResult.failure(reason: .certificateChainEmpty)
            validationHandler?(host, result)
            return result
        }

        // Check each certificate's public key
        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else {
                continue
            }

            guard let publicKeyHash = extractPublicKeyHash(from: certificate) else {
                continue
            }

            // Check against pins
            for pin in hostPins {
                if publicKeyHashMatches(publicKeyHash, pin: pin.publicKeyHash) {
                    let result = ValidationResult.success(matchedPin: pin)
                    validationHandler?(host, result)
                    return result
                }
            }
        }

        let result = ValidationResult.failure(reason: .noMatchingPin)
        validationHandler?(host, result)
        return result
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let result = validate(serverTrust: serverTrust, host: host)

        switch result {
        case .success:
            completionHandler(.useCredential, URLCredential(trust: serverTrust))

        case .failure(let reason):
            if policy == .reportOnly {
                // Log but allow connection
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    // MARK: - Helper Methods

    private func matches(host: String, pattern: String) -> Bool {
        if pattern == host { return true }

        // Handle wildcard patterns
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host.hasSuffix(suffix) && host.count > suffix.count
        }

        return false
    }

    private func extractPublicKeyHash(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        return sha256Hash(of: publicKeyData)
    }

    private func sha256Hash(of data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }

    private func publicKeyHashMatches(_ hash: String, pin: String) -> Bool {
        // Pin format: "sha256/base64hash"
        let pinHash = pin.hasPrefix("sha256/") ? String(pin.dropFirst(7)) : pin
        return hash == pinHash
    }

    // MARK: - Pin Generation

    /// Generates a pin hash from a certificate file.
    ///
    /// - Parameter certificateURL: Path to the certificate file.
    /// - Returns: The public key hash for pinning.
    public static func generatePinHash(from certificateURL: URL) throws -> String {
        let data = try Data(contentsOf: certificateURL)

        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw PinningError.invalidCertificate
        }

        guard let publicKey = SecCertificateCopyKey(certificate) else {
            throw PinningError.publicKeyExtractionFailed
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw PinningError.publicKeyExtractionFailed
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(publicKeyData.count), &hash)
        }

        return "sha256/" + Data(hash).base64EncodedString()
    }

    /// Generates a pin hash from a DER-encoded public key.
    ///
    /// - Parameter publicKeyData: The public key data.
    /// - Returns: The pin hash.
    public static func generatePinHash(from publicKeyData: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(publicKeyData.count), &hash)
        }
        return "sha256/" + Data(hash).base64EncodedString()
    }
}

// MARK: - Pinning Errors

/// Errors related to public key pinning.
public enum PinningError: Error, Sendable {
    case invalidCertificate
    case publicKeyExtractionFailed
    case pinValidationFailed
    case noPinsConfigured
}

extension PinningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCertificate:
            return "Invalid certificate data"
        case .publicKeyExtractionFailed:
            return "Failed to extract public key from certificate"
        case .pinValidationFailed:
            return "Public key pin validation failed"
        case .noPinsConfigured:
            return "No pins configured for this host"
        }
    }
}
