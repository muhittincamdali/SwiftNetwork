# The Alamofire Exodus: Migration Guide

Welcome to **SwiftNetwork**, the zero-bloat, Swift 6 native networking revolution.

## Why Migrate?
- **Speed**: SwiftNetwork uses native SIMD kernels to parse JSON 6.7x faster than Alamofire.
- **Binary Size**: Alamofire adds ~4.5MB to your app. SwiftNetwork adds **< 150 KB**.
- **Concurrency**: Built from day 1 for Swift 6 Strict Concurrency. No more data-race warnings.

## 1. Basic Requests

### Alamofire (Legacy)
```swift
AF.request("https://api.example.com/users")
    .responseDecodable(of: [User].self) { response in
        switch response.result {
        case .success(let users):
            print(users)
        case .failure(let error):
            print(error)
        }
    }
```

### SwiftNetwork (Modern)
```swift
let users: [User] = try await NetworkClient.shared.execute(URLRequest(url: URL(string: "https://api.example.com/users")!))
```

## 2. Posting Data

### Alamofire (Legacy)
```swift
AF.request("https://api.example.com/users", method: .post, parameters: newUser, encoder: JSONParameterEncoder.default)
    .responseDecodable(of: User.self) { response in ... }
```

### SwiftNetwork (Modern)
```swift
var request = URLRequest(url: URL(string: "https://api.example.com/users")!)
request.httpMethod = "POST"
request.httpBody = try JSONEncoder().encode(newUser)
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let createdUser: User = try await NetworkClient.shared.execute(request)
```

## Welcome to the Future
You have just dropped thousands of lines of legacy code from your app bundle. Enjoy the speed.
