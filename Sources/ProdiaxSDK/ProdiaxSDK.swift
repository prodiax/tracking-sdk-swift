import Foundation
import UIKit
import Network

// MARK: - Configuration
public struct ProdiaxConfig {
    public let productId: String
    public let apiEndpoint: String
    public let environment: Environment
    public let debugMode: Bool
    public let enableAutomaticScreenTracking: Bool
    public let enableAutomaticAppStateTracking: Bool
    public let enableAutomaticErrorTracking: Bool
    public let sessionTimeoutMs: Int
    public let maxSessionDurationMs: Int
    public let batchSize: Int
    public let batchIntervalMs: Int
    
    public enum Environment: String {
        case development = "development"
        case production = "production"
    }
    
    public init(
        productId: String,
        apiEndpoint: String = "https://api.prodiax.com/track",
        environment: Environment = .production,
        debugMode: Bool = false,
        enableAutomaticScreenTracking: Bool = true,
        enableAutomaticAppStateTracking: Bool = true,
        enableAutomaticErrorTracking: Bool = true,
        sessionTimeoutMs: Int = 30 * 60 * 1000, // 30 minutes
        maxSessionDurationMs: Int = 24 * 60 * 60 * 1000, // 24 hours
        batchSize: Int = 20,
        batchIntervalMs: Int = 3000
    ) {
        self.productId = productId
        self.apiEndpoint = apiEndpoint
        self.environment = environment
        self.debugMode = debugMode
        self.enableAutomaticScreenTracking = enableAutomaticScreenTracking
        self.enableAutomaticAppStateTracking = enableAutomaticAppStateTracking
        self.enableAutomaticErrorTracking = enableAutomaticErrorTracking
        self.sessionTimeoutMs = sessionTimeoutMs
        self.maxSessionDurationMs = maxSessionDurationMs
        self.batchSize = batchSize
        self.batchIntervalMs = batchIntervalMs
    }
}

// MARK: - Session Model
struct ProdiaxSession: Codable {
    let sessionId: String
    let startTimestamp: String
    var eventCount: Int
    var screenViews: Int
    var interactions: Int
    
    init() {
        self.sessionId = UUID().uuidString
        self.startTimestamp = ISO8601DateFormatter().string(from: Date())
        self.eventCount = 0
        self.screenViews = 0
        self.interactions = 0
    }
}

// MARK: - Event Model
struct ProdiaxEvent: Codable {
    let eventId: String
    let timestamp: String
    let eventType: String
    let data: [String: Any]
    
    private enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case timestamp = "timestamp_utc"
        case eventType = "event_type"
        case data
    }
    
    init(eventType: String, data: [String: Any] = [:]) {
        self.eventId = UUID().uuidString
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.eventType = eventType
        self.data = data
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(data.compactMapValues { $0 as? Codable }, forKey: .data)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decode(String.self, forKey: .eventId)
        timestamp = try container.decode(String.self, forKey: .timestamp)
        eventType = try container.decode(String.self, forKey: .eventType)
        data = try container.decode([String: AnyCodable].self, forKey: .data)
            .mapValues { $0.value }
    }
}

// MARK: - Helper for Any Codable
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        default:
            try container.encode(String(describing: value))
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
}

// MARK: - Main SDK Class
public class ProdiaxSDK {
    public static let shared = ProdiaxSDK()
    
    private var config: ProdiaxConfig?
    private var eventQueue: [ProdiaxEvent] = []
    private var failedEvents: [ProdiaxEvent] = []
    private var currentSession: ProdiaxSession?
    private var lastActivityTimestamp = Date()
    private var isInitialized = false
    private var currentScreen: [String: Any]?
    private var screenHistory: [[String: Any]] = []
    private let appStartTime = Date()
    private var userId: String?
    private let anonymousId = UUID().uuidString
    
    private var batchTimer: Timer?
    private var retryTimer: Timer?
    private let networkMonitor = NWPathMonitor()
    private var isOnline = true
    
    private let queue = DispatchQueue(label: "com.prodiax.sdk", qos: .background)
    
    private init() {}
    
    // MARK: - Public API
    public func initialize(config: ProdiaxConfig) {
        guard !isInitialized else {
            log("SDK already initialized.")
            return
        }
        
        guard !config.productId.isEmpty else {
            error("Initialization failed: productId is mandatory.")
            return
        }
        
        self.config = config
        self.isInitialized = true
        
        log("Prodiax iOS SDK v1.0 Initialized for product: \(config.productId)")
        
        setupNetworkMonitoring()
        startNewSession()
        trackAppStart()
        setupAppStateTracking()
        setupErrorTracking()
        setupScreenTracking()
        
        log("Prodiax SDK initialization complete")
    }
    
    public func track(_ eventName: String, properties: [String: Any] = [:]) {
        guard isInitialized else { return }
        
        trackEvent(
            eventType: "custom_event",
            data: [
                "custom_event_name": eventName,
                "custom_properties": properties
            ]
        )
    }
    
    public func trackScreen(_ screenName: String, screenTitle: String? = nil, params: [String: Any] = [:]) {
        guard isInitialized else { return }
        
        currentScreen = [
            "name": screenName,
            "title": screenTitle ?? screenName,
            "params": params
        ]
        
        screenHistory.append(currentScreen!)
        if screenHistory.count > 10 {
            screenHistory.removeFirst()
        }
        
        trackScreenView(screenName: screenName, screenTitle: screenTitle, params: params)
    }
    
    public func identify(_ userId: String, traits: [String: Any] = [:]) {
        guard isInitialized else { return }
        
        self.userId = userId
        trackEvent(
            eventType: "identify",
            data: [
                "user_id": userId,
                "user_traits": traits
            ]
        )
    }
    
    public func flush() async {
        await sendBatch()
    }
    
    public func reset() {
        eventQueue.removeAll()
        failedEvents.removeAll()
        batchTimer?.invalidate()
        retryTimer?.invalidate()
        batchTimer = nil
        retryTimer = nil
        userId = nil
    }
    
    public func getSession() -> [String: Any]? {
        guard let session = currentSession else { return nil }
        
        return [
            "session_id": session.sessionId,
            "start_timestamp": session.startTimestamp,
            "event_count": session.eventCount,
            "screen_views": session.screenViews,
            "interactions": session.interactions
        ]
    }
    
    public func getCurrentScreen() -> [String: Any]? {
        return currentScreen
    }
    
    // MARK: - Private Methods
    private func log(_ message: String) {
        if config?.debugMode == true {
            print("[ProdiaxSDK] \(message)")
        }
    }
    
    private func error(_ message: String) {
        print("[ProdiaxSDK ERROR] \(message)")
    }
    
    private func trackEvent(eventType: String, data: [String: Any] = [:]) {
        guard isInitialized else { return }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if !["session_start", "session_end"].contains(eventType) {
                self.checkSession()
            }
            
            var eventData = data
            eventData.merge(self.getScreenContext()) { _, new in new }
            eventData.merge(self.getUserContext()) { _, new in new }
            
            let event = ProdiaxEvent(eventType: eventType, data: eventData)
            self.eventQueue.append(event)
            
            self.log("Event: \(eventType)")
            
            if self.eventQueue.count >= self.config?.batchSize ?? 20 {
                Task { await self.sendBatch() }
            } else if self.batchTimer == nil {
                self.setupBatchTimer()
            }
        }
    }
    
    private func setupBatchTimer() {
        batchTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval((config?.batchIntervalMs ?? 3000) / 1000), repeats: false) { [weak self] _ in
            Task { await self?.sendBatch() }
            self?.batchTimer = nil
        }
    }
    
    @MainActor
    private func sendBatch() async {
        guard !eventQueue.isEmpty, let config = config else { return }
        
        let payload: [String: Any] = [
            "productId": config.productId,
            "sessionId": currentSession?.sessionId ?? "",
            "anonymousId": anonymousId,
            "userId": userId ?? NSNull(),
            "timestamp_utc": ISO8601DateFormatter().string(from: Date()),
            "device_info": getDeviceInfo(),
            "events": eventQueue.map { event in
                [
                    "event_id": event.eventId,
                    "timestamp_utc": event.timestamp,
                    "event_type": event.eventType,
                    "data": event.data
                ]
            }
        ]
        
        let eventsToSend = eventQueue
        eventQueue.removeAll()
        
        log("Sending batch with \(eventsToSend.count) events")
        await sendData(payload: payload, originalEvents: eventsToSend)
    }
    
    private func sendData(payload: [String: Any], originalEvents: [ProdiaxEvent]) async {
        guard let config = config,
              let url = URL(string: config.apiEndpoint) else { return }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                log("Batch sent successfully")
                if !failedEvents.isEmpty {
                    retryFailedEvents()
                }
            } else {
                error("HTTP Error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                handleFailedBatch(originalEvents)
            }
        } catch {
            error("Network error: \(error.localizedDescription)")
            handleFailedBatch(originalEvents)
        }
    }
    
    private func handleFailedBatch(_ events: [ProdiaxEvent]) {
        failedEvents.append(contentsOf: events)
        
        if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.retryFailedEvents()
                self?.retryTimer = nil
            }
        }
    }
    
    private func retryFailedEvents() {
        guard !failedEvents.isEmpty else { return }
        
        let eventsToRetry = failedEvents
        failedEvents.removeAll()
        
        log("Retrying \(eventsToRetry.count) failed events")
        eventQueue.append(contentsOf: eventsToRetry)
        Task { await sendBatch() }
    }
    
    // MARK: - Session Management
    private func startNewSession() {
        if currentSession != nil {
            endCurrentSession()
        }
        
        lastActivityTimestamp = Date()
        currentSession = ProdiaxSession()
        
        log("New session started: \(currentSession?.sessionId ?? "")")
        
        trackEvent(
            eventType: "session_start",
            data: [
                "session_id": currentSession?.sessionId ?? ""
            ]
        )
    }
    
    private func endCurrentSession() {
        guard let session = currentSession else { return }
        
        let sessionDuration = Date().timeIntervalSince(
            ISO8601DateFormatter().date(from: session.startTimestamp) ?? Date()
        ) * 1000 // Convert to milliseconds
        
        trackEvent(
            eventType: "session_end",
            data: [
                "session_duration_ms": Int(sessionDuration),
                "total_events": session.eventCount
            ]
        )
        
        Task { await sendBatch() }
        log("Session ended: \(session.sessionId)")
    }
    
    private func checkSession() {
        let now = Date()
        let timeSinceLastActivity = now.timeIntervalSince(lastActivityTimestamp) * 1000 // Convert to ms
        
        let shouldStartNewSession = currentSession == nil ||
            timeSinceLastActivity > Double(config?.sessionTimeoutMs ?? 1800000) ||
            (currentSession != nil && now.timeIntervalSince(
                ISO8601DateFormatter().date(from: currentSession!.startTimestamp) ?? Date()
            ) * 1000 > Double(config?.maxSessionDurationMs ?? 86400000))
        
        if shouldStartNewSession {
            startNewSession()
        }
        
        lastActivityTimestamp = now
        currentSession?.eventCount += 1
    }
    
    // MARK: - Automatic Tracking Setup
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
        }
        networkMonitor.start(queue: queue)
    }
    
    private func setupAppStateTracking() {
        guard config?.enableAutomaticAppStateTracking == true else { return }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppForeground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppBackground()
        }
        
        log("Automatic app state tracking enabled")
    }
    
    private func handleAppForeground() {
        let now = Date()
        let timeInBackground = now.timeIntervalSince(lastActivityTimestamp) * 1000
        
        trackEvent(
            eventType: "app_foreground",
            data: ["time_in_background": Int(timeInBackground)]
        )
        
        lastActivityTimestamp = now
    }
    
    private func handleAppBackground() {
        let now = Date()
        let timeInForeground = now.timeIntervalSince(lastActivityTimestamp) * 1000
        
        trackEvent(
            eventType: "app_background",
            data: ["time_in_foreground": Int(timeInForeground)]
        )
    }
    
    private func setupErrorTracking() {
        guard config?.enableAutomaticErrorTracking == true else { return }
        
        NSSetUncaughtExceptionHandler { [weak self] exception in
            self?.handleError(
                message: exception.reason ?? "Unknown exception",
                stack: exception.callStackSymbols.joined(separator: "\n"),
                type: exception.name.rawValue
            )
        }
        
        log("Automatic error tracking enabled")
    }
    
    private func setupScreenTracking() {
        guard config?.enableAutomaticScreenTracking == true else { return }
        
        // Swizzle viewDidAppear to automatically track screen views
        swizzleViewDidAppear()
        
        log("Automatic screen tracking enabled")
    }
    
    private func swizzleViewDidAppear() {
        let originalSelector = #selector(UIViewController.viewDidAppear(_:))
        let swizzledSelector = #selector(UIViewController.prodiax_viewDidAppear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) else {
            return
        }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
    
    private func handleError(message: String, stack: String? = nil, type: String = "Error") {
        trackEvent(
            eventType: "error",
            data: [
                "message": message,
                "stack": stack ?? "",
                "type": type,
                "context": [
                    "screen_name": currentScreen?["name"] ?? ""
                ]
            ]
        )
    }
    
    // MARK: - Screen Tracking
    private func trackScreenView(screenName: String, screenTitle: String?, params: [String: Any]) {
        trackEvent(
            eventType: "screen_view",
            data: [
                "screen_name": screenName,
                "screen_title": screenTitle ?? screenName,
                "screen_params": params,
                "screen_history": screenHistory.compactMap { $0["name"] }
            ]
        )
        
        currentSession?.screenViews += 1
    }
    
    private func trackAppStart() {
        let appStartTime = Date().timeIntervalSince(self.appStartTime) * 1000
        
        trackEvent(
            eventType: "app_start",
            data: ["app_start_time": Int(appStartTime)]
        )
    }
    
    // MARK: - Context Methods
    private func getScreenContext() -> [String: Any] {
        return [
            "screen_type": getScreenType(),
            "screen_section": getScreenSection(),
            "screen_params": currentScreen?["params"] ?? [:],
            "screen_history_length": screenHistory.count
        ]
    }
    
    private func getUserContext() -> [String: Any] {
        return [
            "is_authenticated": userId != nil,
            "user_id": userId ?? "",
            "engagement_level": getEngagementLevel()
        ]
    }
    
    private func getScreenType() -> String {
        let screenName = (currentScreen?["name"] as? String) ?? ""
        
        if screenName.contains("Home") || screenName.contains("Main") {
            return "home"
        } else if screenName.contains("Product") || screenName.contains("Detail") {
            return "product"
        } else if screenName.contains("Profile") || screenName.contains("Account") {
            return "profile"
        } else if screenName.contains("Settings") {
            return "settings"
        } else if screenName.contains("Login") || screenName.contains("Auth") {
            return "auth"
        }
        
        return "other"
    }
    
    private func getScreenSection() -> String {
        let screenName = (currentScreen?["name"] as? String) ?? ""
        let sections = screenName.components(separatedBy: "/").filter { !$0.isEmpty }
        return sections.first ?? "root"
    }
    
    private func getEngagementLevel() -> String {
        let sessionEvents = currentSession?.eventCount ?? 0
        
        if sessionEvents > 20 {
            return "high"
        } else if sessionEvents > 10 {
            return "medium"
        }
        
        return "low"
    }
    
    private func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        let bundle = Bundle.main
        
        return [
            "device_type": UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone",
            "device_name": device.name,
            "device_model": device.model,
            "os_name": device.systemName,
            "os_version": device.systemVersion,
            "platform": "iOS",
            "app_version": bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "app_build": bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "is_device": !device.isSimulator,
            "is_connected": isOnline
        ]
    }
}

// MARK: - UIViewController Extension for Automatic Screen Tracking
extension UIViewController {
    @objc func prodiax_viewDidAppear(_ animated: Bool) {
        prodiax_viewDidAppear(animated) // Call original implementation
        
        // Track screen view automatically
        let screenName = String(describing: type(of: self))
        ProdiaxSDK.shared.trackScreen(screenName)
    }
}

// MARK: - UIDevice Extension
extension UIDevice {
    var isSimulator: Bool {
        return TARGET_OS_SIMULATOR != 0
    }
}