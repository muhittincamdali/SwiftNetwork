# SwiftNetwork

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2015+%20|%20macOS%2013+-blue.svg)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A modern, lightweight networking library for Swift built entirely on `async/await` and `Sendable` concurrency. Designed for real-world production apps with interceptors, retry logic, certificate pinning, WebSocket support, and a clean fluent API.

---

## Features

- **Async/Await Native** — No completion handlers, no Combine wrappers. Pure structured concurrency.
- **Interceptor Chain** — Auth, logging, retry, or build your own. Intercept requests and responses at every stage.
- **Automatic Token Refresh** — `AuthInterceptor` handles expired tokens and replays failed requests seamlessly.
- **Exponential Backoff Retry** — Configurable retry with jitter for transient failures.
- **Certificate Pinning** — Pin SSL certificates or public keys for enhanced transport security.
- **WebSocket Client** — Full async/await WebSocket with automatic reconnection.
- **Multipart Upload** — Stream large files with multipart/form-data support.
- **Fluent Request Builder** — Chain `.path()`, `.method()`, `.header()`, `.query()` calls for readable request construction.
- **Mock Client** — Drop-in mock for unit testing without hitting the network.
- **Sendable Throughout** — Thread-safe by design, no data races.
- **Zero Dependencies** — Built entirely on Foundation and URLSession.

---

## Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| macOS    | 13.0+          |
| Swift    | 5.9+           |

---

## Installation

### Swift Package Manager

Add SwiftNetwork to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/SwiftNetwork.git", from: "1.0.0")
]
```

Then add `"SwiftNetwork"` to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["SwiftNetwork"]
)
```

Or in Xcode: **File → Add Package Dependencies** → paste the repo URL.

---

## Quick Start

### Basic GET Request

```swift
import SwiftNetwork

let client = NetworkClient(baseURL: "https://api.example.com")

struct User: Decodable {
    let id: Int
    let name: String
    let email: String
}

// Simple GET
let users: [User] = try await client.request(
    Endpoint(path: "/users", method: .get)
)
print(users)
```

### POST with Body

```swift
struct CreateUser: Encodable {
    let name: String
    let email: String
}

let body = CreateUser(name: "Muhittin", email: "hello@example.com")
let endpoint = Endpoint(
    path: "/users",
    method: .post,
    body: try JSONEncoder().encode(body)
)

let created: User = try await client.request(endpoint)
```

### Using the Request Builder

```swift
let endpoint = RequestBuilder()
    .path("/users")
    .method(.get)
    .header("Accept", "application/json")
    .query("page", "1")
    .query("limit", "20")
    .build()

let users: [User] = try await client.request(endpoint)
```

### Adding Interceptors

```swift
let client = NetworkClient(
    baseURL: "https://api.example.com",
    interceptors: [
        AuthInterceptor(tokenProvider: { await TokenStore.shared.accessToken }),
        LoggingInterceptor(),
        RetryInterceptor(maxRetries: 3)
    ]
)
```

### Auth Interceptor with Token Refresh

```swift
let auth = AuthInterceptor(
    tokenProvider: { await TokenStore.shared.accessToken },
    tokenRefresher: {
        let newToken = try await AuthService.refreshToken()
        await TokenStore.shared.update(newToken)
    }
)

let client = NetworkClient(
    baseURL: "https://api.example.com",
    interceptors: [auth, LoggingInterceptor()]
)
```

### File Upload with Multipart

```swift
var multipart = MultipartFormData()
multipart.append(
    data: imageData,
    name: "avatar",
    fileName: "profile.jpg",
    mimeType: "image/jpeg"
)
multipart.append(value: "Muhittin", name: "username")

let response: UploadResponse = try await client.upload(
    path: "/upload",
    multipart: multipart
)
```

### File Download

```swift
let fileURL = try await client.download(
    endpoint: Endpoint(path: "/files/report.pdf", method: .get),
    destination: FileManager.default.temporaryDirectory.appendingPathComponent("report.pdf")
)
print("Downloaded to: \(fileURL.path)")
```

### WebSocket

```swift
let ws = WebSocketClient(url: URL(string: "wss://echo.example.com/ws")!)

try await ws.connect()

// Send messages
try await ws.send(text: "Hello, server!")
try await ws.send(data: someData)

// Receive messages
for try await message in ws.messages {
    switch message {
    case .text(let string):
        print("Received: \(string)")
    case .data(let data):
        print("Received \(data.count) bytes")
    }
}

ws.disconnect()
```

### Certificate Pinning

```swift
let pinning = CertificatePinning(pins: [
    "api.example.com": [
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" // SHA-256 hash of public key
    ]
])

let client = NetworkClient(
    baseURL: "https://api.example.com",
    certificatePinning: pinning
)
```

### Mock Client for Testing

```swift
let mock = MockNetworkClient()
mock.stub(path: "/users", response: [
    User(id: 1, name: "Test User", email: "test@example.com")
])

let users: [User] = try await mock.request(
    Endpoint(path: "/users", method: .get)
)
// Returns stubbed data without network call
```

---

## API Overview

### Core Types

| Type | Description |
|------|-------------|
| `NetworkClient` | Main entry point. Manages requests, uploads, downloads. |
| `Endpoint` | Describes an HTTP endpoint: path, method, headers, body, query items. |
| `NetworkError` | Typed error enum covering all failure modes. |
| `HTTPMethod` | HTTP verbs: `.get`, `.post`, `.put`, `.patch`, `.delete`, `.head`, `.options`. |
| `NetworkResponse` | Wraps raw response data, status code, and headers. |

### Request Building

| Type | Description |
|------|-------------|
| `RequestBuilder` | Fluent API for constructing `Endpoint` instances. |
| `MultipartFormData` | Build multipart/form-data payloads for file uploads. |

### Interceptors

| Type | Description |
|------|-------------|
| `NetworkInterceptor` | Protocol for intercepting requests and responses. |
| `AuthInterceptor` | Adds bearer tokens, auto-refreshes on 401. |
| `LoggingInterceptor` | Logs request/response details to console. |
| `RetryInterceptor` | Retries failed requests with exponential backoff. |

### Utilities

| Type | Description |
|------|-------------|
| `WebSocketClient` | Async/await WebSocket client with reconnection. |
| `CertificatePinning` | SSL certificate/public key pinning delegate. |
| `MockNetworkClient` | Stub responses for unit tests. |

---

## Error Handling

```swift
do {
    let user: User = try await client.request(endpoint)
} catch let error as NetworkError {
    switch error {
    case .invalidURL:
        print("Bad URL")
    case .httpError(let statusCode, let data):
        print("HTTP \(statusCode): \(String(data: data ?? Data(), encoding: .utf8) ?? "")")
    case .decodingFailed(let underlying):
        print("JSON decode error: \(underlying)")
    case .noData:
        print("Empty response")
    case .timeout:
        print("Request timed out")
    case .noConnection:
        print("No internet connection")
    case .certificatePinningFailed:
        print("SSL pinning failed — possible MITM")
    case .cancelled:
        print("Request was cancelled")
    case .unknown(let underlying):
        print("Unexpected: \(underlying)")
    }
}
```

---

## Architecture

```
SwiftNetwork/
├── Core/
│   ├── NetworkClient.swift        # Main client with request/upload/download
│   ├── Endpoint.swift             # Request endpoint descriptor
│   ├── NetworkError.swift         # Typed error cases
│   └── HTTPMethod.swift           # HTTP verb enum
├── Request/
│   ├── RequestBuilder.swift       # Fluent endpoint builder
│   └── MultipartFormData.swift    # Multipart form construction
├── Response/
│   └── NetworkResponse.swift      # Response wrapper
├── Interceptor/
│   ├── InterceptorProtocol.swift  # Interceptor contract
│   ├── AuthInterceptor.swift      # Token injection + refresh
│   ├── LoggingInterceptor.swift   # Request/response logging
│   └── RetryInterceptor.swift     # Retry with backoff
├── Mock/
│   └── MockNetworkClient.swift    # Test double
├── WebSocket/
│   └── WebSocketClient.swift      # Async WebSocket
├── Security/
│   └── CertificatePinning.swift   # SSL pinning
└── Extensions/
    └── URLRequest+Extensions.swift
```

---

## Thread Safety

SwiftNetwork is fully `Sendable`. The `NetworkClient` can be safely shared across actors, tasks, and threads. All mutable state is protected with actors or locks internally.

---

## Performance Tips

- **Reuse `NetworkClient`** — Create one instance and share it. URLSession handles connection pooling.
- **Use interceptors wisely** — Each interceptor adds a small overhead per request. Keep the chain lean.
- **Prefer `Endpoint` over `RequestBuilder`** for simple requests — the builder is convenient but allocates more.

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`swift test`)
5. Commit with conventional messages (`feat:`, `fix:`, `docs:`)
6. Push and open a Pull Request

---

## License

SwiftNetwork is released under the **MIT License**. See [LICENSE](LICENSE) for details.

---

**Made with ❤️ for the Swift community**
