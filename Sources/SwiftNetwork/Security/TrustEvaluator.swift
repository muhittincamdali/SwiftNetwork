import Foundation
import Security

/// Evaluates server trust for secure connections.
///
/// `TrustEvaluator` provides flexible trust evaluation policies including
/// certificate pinning, public key pinning, and custom validation.
///
/// ```swift
/// let evaluator = CompositeTrustEvaluator(evaluators: [
///     DefaultTrustEvaluator(),
///     PublicKeyTrustEvaluator(keys: trustedKeys)
/// ])
///
/// let isValid = try evaluator.evaluate(trust, host: "api.example.com")
/// ```
public protocol TrustEvaluator: Sendable {

    /// Evaluates server trust.
    ///
    /// - Parameters:
    ///   - trust: The server trust to evaluate.
    ///   - host: The host being connected to.
    /// - Returns: Whether the trust is valid.
    /// - Throws: Evaluation errors.
    func evaluate(_ trust: SecTrust, forHost host: String) throws -> Bool
}

// MARK: - Default Trust Evaluator

/// Performs default system trust evaluation.
public struct DefaultTrustEvaluator: TrustEvaluator {

    /// Whether to validate the host name.
    public let validateHost: Bool

    /// Creates a default trust evaluator.
    ///
    /// - Parameter validateHost: Whether to validate host. Defaults to true.
    public init(validateHost: Bool = true) {
        self.validateHost = validateHost
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws -> Bool {
        if validateHost {
            let policy = SecPolicyCreateSSL(true, host as CFString)
            SecTrustSetPolicies(trust, policy)
        }

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if !isValid {
            throw TrustEvaluationError.systemValidationFailed(error)
        }

        return true
    }
}

// MARK: - Disabled Trust Evaluator

/// Disables trust evaluation (for development only).
public struct DisabledTrustEvaluator: TrustEvaluator {

    /// Creates a disabled trust evaluator.
    public init() {}

    public func evaluate(_ trust: SecTrust, forHost host: String) throws -> Bool {
        #if DEBUG
        return true
        #else
        throw TrustEvaluationError.disabledInProduction
        #endif
    }
}

// MARK: - Pinned Certificates Trust Evaluator

/// Evaluates trust by comparing certificates against pinned certificates.
public struct PinnedCertificatesTrustEvaluator: TrustEvaluator {

    /// The pinned certificates.
    public let certificates: [SecCertificate]

    /// Whether to also perform standard validation.
    public let performDefaultValidation: Bool

    /// Whether to validate the certificate chain.
    public let validateCertificateChain: Bool

    /// Creates a pinned certificates trust evaluator.
    ///
    /// - Parameters:
    ///   - certificates: The certificates to pin.
    ///   - performDefaultValidation: Also do default validation. Defaults to true.
    ///   - validateCertificateChain: Validate chain. Defaults to true.
    public init(
        certificates: [SecCertificate],
        performDefaultValidation: Bool = true,
        validateCertificateChain: Bool = true
    ) {
        self.certificates = certificates
        self.performDefaultValidation = performDefaultValidation
        self.validateCertificateChain = validateCertificateChain
    }

    /// Creates from certificate data.
    ///
    /// - Parameter certificateData: Array of DER-encoded certificate data.
    public init(certificateData: [Data]) {
        self.certificates = certificateData.compactMap { data in
            SecCertificateCreateWithData(nil, data as CFData)
        }
        self.performDefaultValidation = true
        self.validateCertificateChain = true
    }

    /// Creates from bundle certificates.
    ///
    /// - Parameters:
    ///   - bundle: The bundle containing certificates.
    ///   - type: Certificate file type. Defaults to "cer".
    public init(bundle: Bundle, type: String = "cer") {
        let paths = bundle.paths(forResourcesOfType: type, inDirectory: nil)
        let certificates = paths.compactMap { path -> SecCertificate? in
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return SecCertificateCreateWithData(nil, data as CFData)
        }
        self.init(certificates: certificates)
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws -> Bool {
        guard !certificates.isEmpty else {
            throw TrustEvaluationError.noCertificates
        }

        if performDefaultValidation {
            let defaultEvaluator = DefaultTrustEvaluator()
            _ = try defaultEvaluator.evaluate(trust, forHost: host)
        }

        if validateCertificateChain {
            SecTrustSetAnchorCertificates(trust, certificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)

            var error: CFError?
            let isValid = SecTrustEvaluateWithError(trust, &error)

            if !isValid {
                throw TrustEvaluationError.certificateChainValidationFailed
            }
        }

        // Check if any server certificate matches pinned certificates
        let serverCertificates = extractCertificates(from: trust)
        let serverCertificateData = Set(serverCertificates.map { SecCertificateCopyData($0) as Data })
        let pinnedCertificateData = Set(certificates.map { SecCertificateCopyData($0) as Data })

        let hasMatch = !serverCertificateData.isDisjoint(with: pinnedCertificateData)

        if !hasMatch {
            throw TrustEvaluationError.noCertificateMatch
        }

        return true
    }

    private func extractCertificates(from trust: SecTrust) -> [SecCertificate] {
        let count = SecTrustGetCertificateCount(trust)
        return (0..<count).compactMap { SecTrustGetCertificateAtIndex(trust, $0) }
    }
}

// MARK: - Composite Trust Evaluator

/// Combines multiple trust evaluators.
public struct CompositeTrustEvaluator: TrustEvaluator {

    /// The evaluators to use.
    public let evaluators: [any TrustEvaluator]

    /// Evaluation mode.
    public enum Mode: Sendable {
        /// All evaluators must pass.
        case all
        /// At least one evaluator must pass.
        case any
    }

    /// The evaluation mode.
    public let mode: Mode

    /// Creates a composite trust evaluator.
    ///
    /// - Parameters:
    ///   - evaluators: The evaluators to combine.
    ///   - mode: The evaluation mode. Defaults to `.all`.
    public init(evaluators: [any TrustEvaluator], mode: Mode = .all) {
        self.evaluators = evaluators
        self.mode = mode
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws -> Bool {
        var errors: [Error] = []

        for evaluator in evaluators {
            do {
                let result = try evaluator.evaluate(trust, forHost: host)
                if result && mode == .any {
                    return true
                }
            } catch {
                errors.append(error)
                if mode == .all {
                    throw error
                }
            }
        }

        if mode == .any && !errors.isEmpty {
            throw TrustEvaluationError.allEvaluatorsFailed(errors)
        }

        return true
    }
}

// MARK: - Revocation Trust Evaluator

/// Adds revocation checking to trust evaluation.
public struct RevocationTrustEvaluator: TrustEvaluator {

    /// Revocation checking options.
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Check OCSP.
        public static let ocsp = Options(rawValue: 1 << 0)
        /// Check CRL.
        public static let crl = Options(rawValue: 1 << 1)
        /// Require positive response.
        public static let requirePositiveResponse = Options(rawValue: 1 << 2)
        /// Prefer network check over cached.
        public static let networkAccessDisallowed = Options(rawValue: 1 << 3)

        /// Default options.
        public static let `default`: Options = [.ocsp]
    }

    /// The revocation options.
    public let options: Options

    /// Creates a revocation trust evaluator.
    ///
    /// - Parameter options: The revocation options.
    public init(options: Options = .default) {
        self.options = options
    }

    public func evaluate(_ trust: SecTrust, forHost host: String) throws -> Bool {
        var revocationFlags: CFOptionFlags = 0

        if options.contains(.ocsp) {
            revocationFlags |= kSecRevocationOCSPMethod
        }

        if options.contains(.crl) {
            revocationFlags |= kSecRevocationCRLMethod
        }

        if options.contains(.requirePositiveResponse) {
            revocationFlags |= kSecRevocationRequirePositiveResponse
        }

        if options.contains(.networkAccessDisallowed) {
            revocationFlags |= kSecRevocationNetworkAccessDisabled
        }

        let revocationPolicy = SecPolicyCreateRevocation(revocationFlags)
        SecTrustSetPolicies(trust, [SecPolicyCreateSSL(true, host as CFString), revocationPolicy] as CFArray)

        var error: CFError?
        let isValid = SecTrustEvaluateWithError(trust, &error)

        if !isValid {
            throw TrustEvaluationError.revocationCheckFailed(error)
        }

        return true
    }
}

// MARK: - Trust Evaluation Errors

/// Errors that can occur during trust evaluation.
public enum TrustEvaluationError: Error, Sendable {
    case systemValidationFailed(CFError?)
    case disabledInProduction
    case noCertificates
    case certificateChainValidationFailed
    case noCertificateMatch
    case publicKeyExtractionFailed
    case noPublicKeyMatch
    case revocationCheckFailed(CFError?)
    case allEvaluatorsFailed([Error])
}

extension TrustEvaluationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .systemValidationFailed(let error):
            return "System trust validation failed: \(error?.localizedDescription ?? "unknown")"
        case .disabledInProduction:
            return "Disabled trust evaluator cannot be used in production"
        case .noCertificates:
            return "No certificates configured for pinning"
        case .certificateChainValidationFailed:
            return "Certificate chain validation failed"
        case .noCertificateMatch:
            return "No server certificate matches pinned certificates"
        case .publicKeyExtractionFailed:
            return "Failed to extract public key from certificate"
        case .noPublicKeyMatch:
            return "No public key matches pinned keys"
        case .revocationCheckFailed(let error):
            return "Revocation check failed: \(error?.localizedDescription ?? "unknown")"
        case .allEvaluatorsFailed:
            return "All trust evaluators failed"
        }
    }
}

// MARK: - Host-based Evaluator Manager

/// Manages trust evaluators for different hosts.
public final class TrustEvaluatorManager: @unchecked Sendable {

    /// Evaluators by host pattern.
    private var evaluators: [String: any TrustEvaluator] = [:]

    /// Default evaluator for unmatched hosts.
    public var defaultEvaluator: any TrustEvaluator

    /// Lock for thread safety.
    private let lock = NSLock()

    /// Creates a trust evaluator manager.
    ///
    /// - Parameter defaultEvaluator: Default evaluator. Defaults to system.
    public init(defaultEvaluator: any TrustEvaluator = DefaultTrustEvaluator()) {
        self.defaultEvaluator = defaultEvaluator
    }

    /// Registers an evaluator for a host pattern.
    ///
    /// - Parameters:
    ///   - evaluator: The evaluator to use.
    ///   - hostPattern: The host pattern (supports wildcards).
    public func register(_ evaluator: any TrustEvaluator, for hostPattern: String) {
        lock.withLock {
            evaluators[hostPattern] = evaluator
        }
    }

    /// Gets the evaluator for a host.
    ///
    /// - Parameter host: The host.
    /// - Returns: The appropriate evaluator.
    public func evaluator(for host: String) -> any TrustEvaluator {
        lock.withLock {
            for (pattern, evaluator) in evaluators {
                if matches(host: host, pattern: pattern) {
                    return evaluator
                }
            }
            return defaultEvaluator
        }
    }

    private func matches(host: String, pattern: String) -> Bool {
        if pattern == host { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return host.hasSuffix(suffix)
        }
        return false
    }
}
