<div align="center">

# 🌐 SwiftNetwork

**Next-gen async/await networking library for iOS - zero dependencies**

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-15.0+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![SPM](https://img.shields.io/badge/SPM-Compatible-FA7343?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

[Features](#-features) • [Installation](#-installation) • [Quick Start](#-quick-start)

</div>

---

## ✨ Features

- 🚀 **Async/Await First** — Built for modern Swift concurrency
- 🔒 **Type-Safe** — Generic request/response handling
- 🔄 **Auto Retry** — Configurable retry policies
- 📦 **Zero Dependencies** — Pure Swift, no external libs
- 🎯 **Interceptors** — Request/response middleware
- 📊 **Metrics** — Built-in performance tracking

---

## 📦 Installation

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/SwiftNetwork.git", from: "1.0.0")
]
```

---

## 🚀 Quick Start

```swift
import SwiftNetwork

let client = NetworkClient()

// GET request
let users: [User] = try await client.get("/users")

// POST request
let newUser = try await client.post("/users", body: userData)

// With authentication
client.addInterceptor(AuthInterceptor(token: "..."))
```

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 👨‍💻 Author

**Muhittin Camdali** • [@muhittincamdali](https://github.com/muhittincamdali)
