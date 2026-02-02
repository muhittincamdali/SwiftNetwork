import Foundation

/// Represents standard HTTP methods.
public enum HTTPMethod: String, Sendable, Hashable {
    /// GET method for retrieving resources.
    case get = "GET"
    /// POST method for creating resources.
    case post = "POST"
    /// PUT method for replacing resources.
    case put = "PUT"
    /// PATCH method for partial updates.
    case patch = "PATCH"
    /// DELETE method for removing resources.
    case delete = "DELETE"
    /// HEAD method for retrieving headers only.
    case head = "HEAD"
    /// OPTIONS method for describing communication options.
    case options = "OPTIONS"
}
