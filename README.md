<p align="center">
  <img src="https://raw.githubusercontent.com/muhittincamdali/SwiftNetwork/main/Assets/logo.png" alt="SwiftNetwork Logo" width="200">
</p>

<h1 align="center">SwiftNetwork</h1>

<p align="center">
  <strong>🌐 Modern, type-safe networking layer for Swift</strong>
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-blue?style=flat-square" alt="Platforms"></a>
  <a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-Compatible-brightgreen?style=flat-square&logo=swift" alt="SPM Compatible"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" alt="License: MIT"></a>
  <br>
  <a href="https://github.com/muhittincamdali/SwiftNetwork/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/muhittincamdali/SwiftNetwork/ci.yml?branch=main&style=flat-square&logo=github&label=CI" alt="CI Status"></a>
  <a href="https://github.com/muhittincamdali/SwiftNetwork/stargazers"><img src="https://img.shields.io/github/stars/muhittincamdali/SwiftNetwork?style=flat-square&logo=github" alt="Stars"></a>
  <a href="https://github.com/muhittincamdali/SwiftNetwork/graphs/contributors"><img src="https://img.shields.io/github/contributors/muhittincamdali/SwiftNetwork?style=flat-square" alt="Contributors"></a>
  <a href="https://github.com/muhittincamdali/SwiftNetwork/issues"><img src="https://img.shields.io/github/issues/muhittincamdali/SwiftNetwork?style=flat-square" alt="Issues"></a>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#documentation">Documentation</a> •
  <a href="#contributing">Contributing</a>
</p>

---

## ✨ Features

- **🚀 Async/Await Native** — Built from the ground up with Swift Concurrency
- **🔒 Type-Safe** — Leverage Swift's type system for compile-time safety
- **🔄 Interceptors** — Request and response interceptors for authentication, logging, and more
- **📦 Response Caching** — Flexible caching with configurable policies
- **🔐 SSL Pinning** — Built-in certificate pinning for enhanced security
- **🔁 Automatic Retry** — Exponential backoff retry mechanism
- **📊 Progress Tracking** — Monitor upload and download progress
- **📝 Comprehensive Logging** — Debug your network calls with detailed logs
- **🧩 Protocol-Oriented** — Easy to extend and customize

## 📋 Requirements

| Platform | Minimum Version |
|----------|----------------|
| iOS      | 15.0+          |
| macOS    | 12.0+          |
| tvOS     | 15.0+          |
| watchOS  | 8.0+           |
| visionOS | 1.0+           |
| Swift    | 5.9+           |
| Xcode    | 15.0+          |

## 📦 Installation

### Swift Package Manager

Add SwiftNetwork to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/SwiftNetwork.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. **File** → **Add Package Dependencies...**
2. Enter: `https://github.com/muhittincamdali/SwiftNetwork.git`
3. Select version and click **Add Package**

### CocoaPods

```ruby
pod 'SwiftNetwork', '~> 1.0'
```

### Manual Installation

1. Download the latest release
2. Drag `Sources/SwiftNetwork` into your Xcode project
3. Ensure "Copy items if needed" is checked

## 🚀 Quick Start

### Basic Request

```swift
import SwiftNetwork

// Define your API endpoint
enum UserAPI: Endpoint {
    case getUser(id: Int)
    case createUser(name: String, email: String)
    
    var path: String {
        switch self {
        case .getUser(let id): return "/users/\(id)"
        case .createUser: return "/users"
        }
    }
    
    var method: HTTPMethod {
        switch self {
        case .getUser: return .get
        case .createUser: return .post
        }
    }
    
    var body: Encodable? {
        switch self {
        case .createUser(let name, let email):
            return ["name": name, "email": email]
        default:
            return nil
        }
    }
}

// Create network client
let client = NetworkClient(baseURL: URL(string: "https://api.example.com")!)

// Make a request
let user: User = try await client.request(UserAPI.getUser(id: 1))
print("Fetched user: \(user.name)")
```

### With Interceptors

```swift
// Add authentication
let authInterceptor = AuthInterceptor(token: "your-token")

let client = NetworkClient(baseURL: baseURL)
    .addInterceptor(authInterceptor)
    .addInterceptor(LoggingInterceptor())
```

### Response Caching

```swift
let client = NetworkClient(baseURL: baseURL)
    .withCache(policy: .returnCacheDataElseLoad, duration: 300)
```

### Retry Configuration

```swift
let client = NetworkClient(baseURL: baseURL)
    .withRetry(maxAttempts: 3, delay: 1.0, multiplier: 2.0)
```

## 📖 Documentation

For full documentation, see the [Documentation](Documentation/) folder.

## 🛡️ Security

See [SECURITY.md](SECURITY.md) for security guidelines.

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a PR.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Muhittin Camdali**

- GitHub: [@muhittincamdali](https://github.com/muhittincamdali)

---

<p align="center">
  <sub>Built with ❤️ for the Swift community</sub>
</p>
