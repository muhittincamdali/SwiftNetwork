import Foundation
import Security
import CommonCrypto

/// Implements SSL certificate pinning by validating server certificates
/// against a set of known public key hashes.
///
/// ```swift
/// let pinning = CertificatePinning(pins: [
///     "api.example.com": ["base64EncodedSHA256Hash=="]
/// ])
///
/// let client = NetworkClient(
///     baseURL: "https://api.example.com",
///     certificatePinning: pinning
/// )
/// ```
public final class CertificatePinning: NSObject, URLSessionDelegate, @unchecked Sendable {

    // MARK: - Properties

    /// A dictionary mapping hostnames to their expected SHA-256 public key hashes (base64 encoded).
    private let pins: [String: [String]]

    /// Whether to allow connections to unpinned hosts.
    private let allowUnpinnedHosts: Bool

    // MARK: - Initialization

    /// Creates a certificate pinning configuration.
    ///
    /// - Parameters:
    ///   - pins: A dictionary of hostname to SHA-256 public key hashes.
    ///   - allowUnpinnedHosts: Whether hosts not in the pins dictionary should be allowed.
    ///     Defaults to `true`.
    public init(pins: [String: [String]], allowUnpinnedHosts: Bool = true) {
        self.pins = pins
        self.allowUnpinnedHosts = allowUnpinnedHosts
        super.init()
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

        guard let expectedHashes = pins[host] else {
            if allowUnpinnedHosts {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        if validateServerTrust(serverTrust, against: expectedHashes) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Validation

    private func validateServerTrust(_ trust: SecTrust, against expectedHashes: [String]) -> Bool {
        let certificateCount = SecTrustGetCertificateCount(trust)

        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(trust, index) else {
                continue
            }

            if let publicKeyHash = sha256HashOfPublicKey(from: certificate) {
                let base64Hash = publicKeyHash.base64EncodedString()
                if expectedHashes.contains(base64Hash) {
                    return true
                }
            }
        }

        return false
    }

    private func sha256HashOfPublicKey(from certificate: SecCertificate) -> Data? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(publicKeyData.count), &hash)
        }

        return Data(hash)
    }
}
