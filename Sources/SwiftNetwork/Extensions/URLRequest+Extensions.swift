import Foundation

extension URLRequest {

    /// Sets the `Content-Type` header to `application/json`.
    ///
    /// - Returns: The modified request.
    public mutating func setJSONContentType() {
        setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    /// Sets the `Accept` header to `application/json`.
    ///
    /// - Returns: The modified request.
    public mutating func setJSONAccept() {
        setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// Sets the `Authorization` header with a Bearer token.
    ///
    /// - Parameter token: The bearer token string.
    public mutating func setBearerToken(_ token: String) {
        setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Adds multiple headers from a dictionary.
    ///
    /// - Parameter headers: A dictionary of header key-value pairs.
    public mutating func addHeaders(_ headers: [String: String]) {
        for (key, value) in headers {
            setValue(value, forHTTPHeaderField: key)
        }
    }

    /// A human-readable description of the request for debugging.
    public var debugDescription: String {
        var parts: [String] = []
        parts.append("\(httpMethod ?? "GET") \(url?.absoluteString ?? "nil")")

        if let headers = allHTTPHeaderFields, !headers.isEmpty {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                parts.append("  \(key): \(value)")
            }
        }

        if let body = httpBody, let bodyString = String(data: body, encoding: .utf8) {
            parts.append("  Body: \(bodyString)")
        }

        return parts.joined(separator: "\n")
    }
}
