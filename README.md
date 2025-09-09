# ProdiaxSDK for iOS

A comprehensive event tracking SDK for iOS applications with automatic tracking capabilities.

[![Swift Version](https://img.shields.io/badge/Swift-5.7+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2013.0+-blue.svg)](https://developer.apple.com/ios/)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🚀 Features

- **Automatic Screen Tracking** - Tracks screen views automatically
- **Session Management** - Handles user sessions with timeout logic  
- **App State Tracking** - Monitors app foreground/background events
- **Error Tracking** - Captures crashes and exceptions automatically
- **Network Resilience** - Batches events and retries failed requests
- **Privacy First** - No PII collection, anonymous by default
- **Lightweight** - Minimal performance impact
- **Thread Safe** - All operations are thread-safe

## 📦 Installation

### Swift Package Manager (Recommended)

Add ProdiaxSDK to your project using Xcode:

1. File → Add Package Dependencies
2. Enter: `https://github.com/prodiax/prodiax-ios-sdk.git`
3. Select version and add to your target

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/prodiax/prodiax-ios-sdk.git", from: "1.0.0")
]
```

### CocoaPods

```ruby
pod 'ProdiaxSDK', '~> 1.0'
```

### Carthage

```
github "prodiax/prodiax-ios-sdk" ~> 1.0
```

## 🎯 Quick Start

### 1. Initialize in AppDelegate

```swift
import ProdiaxSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize ProdiaxSDK
        let config = ProdiaxConfig(
            productId: "your-product-id",
            debugMode: true, // Enable in development
            enableAutomaticScreenTracking: true,
            enableAutomaticAppStateTracking: true,
            enableAutomaticErrorTracking: true
        )
        
        ProdiaxSDK.shared.initialize(config: config)
        
        return true
    }
}
```

### 2. For SwiftUI Apps

```swift
import SwiftUI
import ProdiaxSDK

@main
struct MyApp: App {
    init() {
        // Initialize ProdiaxSDK
        let config = ProdiaxConfig(
            productId: "your-product-id",
            debugMode: true,
            enableAutomaticScreenTracking: true
        )
        
        ProdiaxSDK.shared.initialize(config: config)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 3. Track Events in Your Code

```swift
import ProdiaxSDK

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Track custom events
        ProdiaxSDK.shared.track("screen_loaded", properties: [
            "screen_name": "home",
            "load_time_ms": 250
        ])
    }
    
    @IBAction func buttonTapped(_ sender: UIButton) {
        // Track user interactions
        ProdiaxSDK.shared.track("button_clicked", properties: [
            "button_name": "search_hotels",
            "screen": "home"
        ])
    }
    
    func userLoggedIn(userId: String) {
        // Identify users
        ProdiaxSDK.shared.identify(userId, traits: [
            "email": "user@example.com",
            "plan": "premium",
            "signup_date": "2024-01-15"
        ])
    }
}
```

## ⚙️ Configuration Options

```swift
let config = ProdiaxConfig(
    productId: "your-product-id",                    // Required: Your product ID
    apiEndpoint: "https://api.prodiax.com/track",    // Default API endpoint
    environment: .production,                        // .development or .production
    debugMode: false,                               // Enable debug logging
    enableAutomaticScreenTracking: true,            // Auto-track screen views
    enableAutomaticAppStateTracking: true,          // Auto-track app state changes
    enableAutomaticErrorTracking: true,             // Auto-track errors/crashes
    sessionTimeoutMs: 30 * 60 * 1000,              // 30 minutes session timeout
    maxSessionDurationMs: 24 * 60 * 60 * 1000,     // 24 hours max session
    batchSize: 20,                                  // Events per batch
    batchIntervalMs: 3000                          // 3 seconds batch interval
)
```

## 📊 API Reference

### Core Methods

```swift
// Track custom events
ProdiaxSDK.shared.track("event_name", properties: [String: Any])

// Track screen views manually
ProdiaxSDK.shared.trackScreen("screen_name", screenTitle: "Screen Title", params: [String: Any])

// Identify users
ProdiaxSDK.shared.identify("user_id", traits: [String: Any])

// Force send queued events
await ProdiaxSDK.shared.flush()

// Reset SDK state (logout)
ProdiaxSDK.shared.reset()

// Get current session info
let session = ProdiaxSDK.