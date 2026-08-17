//
//  AnalyticsService.swift
//  CloudAdminClient
//
//  CloudKit-based analytics service with batching, offline support, and privacy controls
//

import Foundation
import CloudKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Configuration

/// Configuration for the analytics service
public struct AnalyticsConfiguration: Sendable {
    /// CloudKit container identifier
    public let containerIdentifier: String

    /// Whether to use private database (recommended for user-linked analytics)
    public let usePrivateDatabase: Bool

    /// Batch size before automatic upload (default: 20)
    public let batchSize: Int

    /// Batch interval in seconds (default: 30)
    public let batchInterval: TimeInterval

    /// Maximum events in local queue (default: 1000)
    public let maxQueueSize: Int

    /// Background threshold for new session in seconds (default: 1800 = 30 min)
    public let sessionBackgroundThreshold: TimeInterval

    /// Enable debug logging (default: DEBUG builds only)
    public let enableDebugLogging: Bool

    /// Whether analytics is enabled (respects user consent)
    public let isEnabled: Bool

    /// Whether to anonymize data (strip userID, coarsen location)
    public let anonymizeData: Bool

    /// Sample rate for high-volume events (0.0-1.0, default: 1.0)
    public let sampleRate: Double

    public init(
        containerIdentifier: String,
        usePrivateDatabase: Bool = true,
        batchSize: Int = 20,
        batchInterval: TimeInterval = 30,
        maxQueueSize: Int = 1000,
        sessionBackgroundThreshold: TimeInterval = 1800,
        enableDebugLogging: Bool = false,
        isEnabled: Bool = true,
        anonymizeData: Bool = false,
        sampleRate: Double = 1.0
    ) {
        self.containerIdentifier = containerIdentifier
        self.usePrivateDatabase = usePrivateDatabase
        self.batchSize = batchSize
        self.batchInterval = batchInterval
        self.maxQueueSize = maxQueueSize
        self.sessionBackgroundThreshold = sessionBackgroundThreshold
        #if DEBUG
        self.enableDebugLogging = true
        #else
        self.enableDebugLogging = enableDebugLogging
        #endif
        self.isEnabled = isEnabled
        self.anonymizeData = anonymizeData
        self.sampleRate = min(max(sampleRate, 0.0), 1.0)
    }
}

// MARK: - Analytics Service

/// Main analytics service for tracking events with CloudKit backend
///
/// `AnalyticsService` provides comprehensive analytics tracking:
/// - Event batching and offline support
/// - Session management
/// - User identity linking
/// - Privacy controls and consent management
///
/// ## Usage
/// ```swift
/// let config = AnalyticsConfiguration(
///     containerIdentifier: "iCloud.com.company.app"
/// )
/// AnalyticsService.configure(with: config)
///
/// // Track events
/// await AnalyticsService.shared?.trackScreen("HomeView")
/// await AnalyticsService.shared?.trackButtonTap("Subscribe", on: "Paywall")
/// ```
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public actor AnalyticsService {

    // MARK: - Properties

    private let configuration: AnalyticsConfiguration
    private var container: CKContainer {
        CKContainer(identifier: configuration.containerIdentifier)
    }
    private var database: CKDatabase {
        configuration.usePrivateDatabase
            ? container.privateCloudDatabase
            : container.publicCloudDatabase
    }

    /// Current session ID
    private var sessionID: UUID = UUID()

    /// Authenticated user ID (nil for anonymous)
    private var userID: String?

    /// Anonymous device ID (persisted in Keychain)
    private var anonymousID: String

    /// Event queue for batching
    private var eventQueue: [AnalyticsEvent] = []

    /// Last background timestamp for session management
    private var lastBackgroundTime: Date?

    /// Current screen name for automatic tracking
    private var currentScreenName: String?

    /// Previous screen name for navigation flow
    private var previousScreenName: String?

    /// Screen appear time for duration tracking
    private var screenAppearTime: Date?

    /// User properties for persistent traits
    private var userProperties: [String: AnyCodable] = [:]

    /// Upload retry count
    private var retryCount: Int = 0
    private let maxRetries = 3

    /// Batch timer task
    private var batchTimerTask: Task<Void, Never>?

    /// UserDefaults key for the process-and-relaunch opt-out flag.
    static let optOutStorageKey = "com.cloudadminkit.analytics.optedOut"

    /// Local persistence file URL
    private var persistenceURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("analytics_queue.json")
    }

    // MARK: - Singleton

    @MainActor
    public static var shared: AnalyticsService?

    @MainActor
    @discardableResult
    public static func configure(with configuration: AnalyticsConfiguration) -> AnalyticsService {
        let service = AnalyticsService(configuration: configuration)
        shared = service
        return service
    }

    // MARK: - Initialization

    public init(configuration: AnalyticsConfiguration) {
        self.configuration = configuration
        self.anonymousID = Self.getOrCreateAnonymousID()

        // Load persisted queue
        Task {
            await loadPersistedQueue()
            await startBatchTimer()
            await setupLifecycleObservers()
        }
    }

    // MARK: - Public Tracking Methods

    /// Whether tracking is currently accepted (configure-time flag and opt-out).
    public var isEnabled: Bool {
        configuration.isEnabled && !isOptedOut
    }

    /// Whether the user has opted out. Survives process relaunch via UserDefaults.
    public var isOptedOut: Bool {
        UserDefaults.standard.bool(forKey: Self.optOutStorageKey)
    }

    /// Tracks a screen view
    public func trackScreen(_ screenName: String, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        // Calculate duration of previous screen
        var duration: TimeInterval? = nil
        if let appearTime = screenAppearTime {
            duration = Date().timeIntervalSince(appearTime)
        }

        // Update screen tracking state
        previousScreenName = currentScreenName
        currentScreenName = screenName
        screenAppearTime = Date()

        let event = createEvent(
            type: .screenView,
            name: screenName,
            properties: properties,
            duration: duration
        )

        await queueEvent(event)
        log("Screen: \(screenName)")
    }

    /// Tracks a button tap
    public func trackButtonTap(_ buttonName: String, on screenName: String? = nil, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["button_name"] = buttonName

        let event = createEvent(
            type: .buttonTap,
            name: buttonName,
            screenName: screenName ?? currentScreenName,
            properties: props
        )

        await queueEvent(event)
        log("Button tap: \(buttonName)")
    }

    /// Tracks a feature being used
    public func trackFeature(_ featureName: String, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        let event = createEvent(
            type: .featureUsed,
            name: featureName,
            properties: properties
        )

        await queueEvent(event)
        log("Feature: \(featureName)")
    }

    /// Tracks a search
    public func trackSearch(_ query: String, results: Int, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["query"] = query
        props["result_count"] = results

        let event = createEvent(
            type: .search,
            name: query,
            properties: props
        )

        await queueEvent(event)
        log("Search: \(query) (\(results) results)")
    }

    /// Tracks an error
    public func trackError(_ error: Error, isFatal: Bool = false, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        let errorInfo = ErrorInfo(from: error, isFatal: isFatal)

        let event = createEvent(
            type: .error,
            name: error.localizedDescription,
            properties: properties,
            errorInfo: errorInfo
        )

        await queueEvent(event)
        log("Error: \(error.localizedDescription)")
    }

    /// Tracks a purchase
    public func trackPurchase(productID: String, price: Decimal, currency: String, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["product_id"] = productID
        props["price"] = NSDecimalNumber(decimal: price).doubleValue
        props["currency"] = currency

        let event = createEvent(
            type: .purchase,
            name: productID,
            properties: props
        )

        await queueEvent(event)
        log("Purchase: \(productID) - \(price) \(currency)")
    }

    /// Tracks an onboarding step
    public func trackOnboardingStep(_ step: Int, of total: Int, name: String? = nil, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["step"] = step
        props["total_steps"] = total
        props["progress"] = Double(step) / Double(total)

        let event = createEvent(
            type: .onboardingStep,
            name: name ?? "Step \(step)",
            properties: props
        )

        await queueEvent(event)
        log("Onboarding: Step \(step)/\(total)")
    }

    /// Tracks a share action
    public func trackShare(_ contentType: String, method: String? = nil, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["content_type"] = contentType
        if let method = method {
            props["share_method"] = method
        }

        let event = createEvent(
            type: .share,
            name: contentType,
            properties: props
        )

        await queueEvent(event)
        log("Share: \(contentType)")
    }

    /// Tracks a notification interaction
    public func trackNotification(_ action: String, notificationID: String? = nil, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["action"] = action
        if let id = notificationID {
            props["notification_id"] = id
        }

        let event = createEvent(
            type: .notification,
            name: action,
            properties: props
        )

        await queueEvent(event)
        log("Notification: \(action)")
    }

    /// Tracks a deep link
    public func trackDeepLink(_ url: URL, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        var props = properties
        props["url"] = url.absoluteString
        props["host"] = url.host ?? ""
        props["path"] = url.path

        let event = createEvent(
            type: .deepLink,
            name: url.host ?? url.absoluteString,
            properties: props
        )

        await queueEvent(event)
        log("Deep link: \(url.absoluteString)")
    }

    /// Tracks a custom event
    public func trackCustom(_ eventName: String, properties: AnalyticsProperties = [:]) async {
        guard isEnabled else { return }

        let event = createEvent(
            type: .custom,
            name: eventName,
            properties: properties
        )

        await queueEvent(event)
        log("Custom: \(eventName)")
    }

    /// Generic track method
    public func track(_ event: AnalyticsEvent) async {
        guard isEnabled else { return }
        await queueEvent(event)
        log("Event: \(event.eventType.rawValue)")
    }

    // MARK: - User Identity

    /// Identifies the user (links anonymous events to authenticated user)
    public func identify(userID: String) async {
        self.userID = userID
        log("Identified user: \(userID)")

        // Track identification event
        await trackCustom("user_identified", properties: ["user_id": userID])
    }

    /// Clears the user identity (on logout)
    public func logout(clearAnonymousID: Bool = false) async {
        let previousUserID = userID
        userID = nil

        if clearAnonymousID {
            Self.clearAnonymousID()
            anonymousID = Self.getOrCreateAnonymousID()
        }

        // Start new session on logout
        sessionID = UUID()

        log("User logged out (was: \(previousUserID ?? "anonymous"))")
    }

    /// Sets user properties (persistent traits)
    public func setUserProperty(_ key: String, value: Any) {
        userProperties[key] = AnyCodable(value)
        log("User property: \(key) = \(value)")
    }

    /// Sets multiple user properties
    public func setUserProperties(_ properties: [String: Any]) {
        for (key, value) in properties {
            userProperties[key] = AnyCodable(value)
        }
        log("User properties set: \(properties.keys.joined(separator: ", "))")
    }

    // MARK: - Session Management

    /// Called when app enters foreground
    public func handleForeground() async {
        if let lastBackground = lastBackgroundTime {
            let backgroundDuration = Date().timeIntervalSince(lastBackground)

            // Start new session if background threshold exceeded
            if backgroundDuration > configuration.sessionBackgroundThreshold {
                sessionID = UUID()
                log("New session started (background: \(Int(backgroundDuration))s)")
            }
        }

        lastBackgroundTime = nil
    }

    /// Called when app enters background
    public func handleBackground() async {
        lastBackgroundTime = Date()

        // Flush events on background
        await flush()
    }

    /// Called when app will terminate
    public func handleTerminate() async {
        // Persist queue and attempt final upload
        await persistQueue()
        await flush()
    }

    // MARK: - Queue Management

    /// Forces an immediate upload of queued events
    public func flush() async {
        guard !eventQueue.isEmpty else { return }

        await uploadBatch()
    }

    /// Clears all queued events (without uploading)
    public func clearQueue() async {
        eventQueue.removeAll()
        await persistQueue()
        log("Queue cleared")
    }

    /// Gets the current queue size
    public var queueSize: Int {
        eventQueue.count
    }

    /// Gets recent events (for debug view)
    public var recentEvents: [AnalyticsEvent] {
        Array(eventQueue.suffix(50))
    }

    // MARK: - Privacy Controls

    /// Deletes all data for the current user (GDPR compliance)
    public func purgeUserData() async throws {
        // Clear local queue
        eventQueue.removeAll()
        await persistQueue()

        // Delete from CloudKit (if authenticated)
        if let userID = userID {
            let query = CKQuery(
                recordType: AnalyticsEvent.recordType,
                predicate: NSPredicate(format: "userID == %@", userID)
            )

            do {
                let (results, _) = try await database.records(matching: query)
                let recordIDs = results.compactMap { $0.0 }

                if !recordIDs.isEmpty {
                    _ = try await database.modifyRecords(saving: [], deleting: recordIDs)
                    log("Purged \(recordIDs.count) records for user \(userID)")
                }
            } catch {
                log("Failed to purge user data: \(error)")
                throw error
            }
        }

        // Clear identity
        await logout(clearAnonymousID: true)
    }

    /// Opts out of analytics. Persists across process relaunch. Subsequent
    /// `track*` calls do not enqueue or write `analytics_queue.json`.
    public func optOut() async {
        UserDefaults.standard.set(true, forKey: Self.optOutStorageKey)
        await clearQueue()
        log("User opted out of analytics")
    }

    /// Re-enables tracking after ``optOut()``. Does not restore previously
    /// cleared events; new `track*` calls enqueue again.
    public func optIn() async {
        UserDefaults.standard.set(false, forKey: Self.optOutStorageKey)
        log("User opted in to analytics")
    }

    // MARK: - Private Methods

    private func createEvent(
        type: AnalyticsEventType,
        name: String? = nil,
        screenName: String? = nil,
        properties: AnalyticsProperties = [:],
        duration: TimeInterval? = nil,
        errorInfo: ErrorInfo? = nil
    ) -> AnalyticsEvent {
        // Apply sampling for high-volume events
        if configuration.sampleRate < 1.0 && Double.random(in: 0...1) > configuration.sampleRate {
            // Event sampled out - return a placeholder that won't be queued
            // We still create it for logging purposes
        }

        var finalUserID = userID
        let latitude: Double? = nil
        let longitude: Double? = nil

        // Apply anonymization if required
        if configuration.anonymizeData {
            finalUserID = nil
            // Location would be coarsened here if we were tracking it
        }

        // Convert properties to AnyCodable
        var codableProperties: [String: AnyCodable] = [:]
        for (key, value) in properties {
            codableProperties[key] = AnyCodable(value)
        }

        // Add user properties
        for (key, value) in userProperties {
            codableProperties["user_\(key)"] = value
        }

        return AnalyticsEvent(
            sessionID: sessionID,
            userID: finalUserID,
            anonymousID: anonymousID,
            eventType: type,
            eventName: name,
            deviceInfo: DeviceInfoCollector.shared.deviceInfo,
            latitude: latitude,
            longitude: longitude,
            screenName: screenName ?? currentScreenName,
            previousScreenName: previousScreenName,
            duration: duration,
            properties: codableProperties,
            errorInfo: errorInfo
        )
    }

    private func queueEvent(_ event: AnalyticsEvent) async {
        // Apply sampling
        if configuration.sampleRate < 1.0 && Double.random(in: 0...1) > configuration.sampleRate {
            return
        }

        eventQueue.append(event)

        // Enforce queue size limit (FIFO eviction)
        if eventQueue.count > configuration.maxQueueSize {
            eventQueue.removeFirst(eventQueue.count - configuration.maxQueueSize)
            log("Queue trimmed to \(configuration.maxQueueSize) events")
        }

        // Check if batch size reached
        if eventQueue.count >= configuration.batchSize {
            await uploadBatch()
        }

        // Persist queue
        await persistQueue()
    }

    private func uploadBatch() async {
        guard !eventQueue.isEmpty else { return }

        let batch = Array(eventQueue.prefix(configuration.batchSize))
        let records = batch.map { $0.toRecord() }

        do {
            _ = try await database.modifyRecords(saving: records, deleting: [])

            // Remove uploaded events from queue
            eventQueue.removeFirst(min(batch.count, eventQueue.count))
            retryCount = 0

            log("Uploaded \(batch.count) events, \(eventQueue.count) remaining")
            await persistQueue()

        } catch {
            retryCount += 1
            log("Upload failed (attempt \(retryCount)): \(error.localizedDescription)")

            // Exponential backoff retry
            if retryCount < maxRetries {
                let delay = pow(2.0, Double(retryCount))
                try? await Task.sleep(for: .seconds(delay))
                await uploadBatch()
            }
        }
    }

    private func startBatchTimer() {
        batchTimerTask?.cancel()
        batchTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(configuration.batchInterval))
                if !eventQueue.isEmpty {
                    await uploadBatch()
                }
            }
        }
    }

    private func persistQueue() async {
        guard let data = try? JSONEncoder().encode(eventQueue) else { return }
        try? data.write(to: persistenceURL)
    }

    private func loadPersistedQueue() async {
        guard let data = try? Data(contentsOf: persistenceURL),
              let events = try? JSONDecoder().decode([AnalyticsEvent].self, from: data) else {
            return
        }
        eventQueue = events
        log("Loaded \(events.count) persisted events")
    }

    private func setupLifecycleObservers() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleForeground() }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleBackground() }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleTerminate() }
        }
        #elseif os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleForeground() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleBackground() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleTerminate() }
        }
        #endif
    }

    private func log(_ message: String) {
        guard configuration.enableDebugLogging else { return }
        print("[Analytics] \(message)")
    }

    // MARK: - Anonymous ID Management

    private static let anonymousIDKey = "com.cloudadminkit.analytics.anonymousID"

    private static func getOrCreateAnonymousID() -> String {
        // Try to get from Keychain first
        if let existingID = KeychainHelper.get(key: anonymousIDKey) {
            return existingID
        }

        // Fall back to UserDefaults
        if let existingID = UserDefaults.standard.string(forKey: anonymousIDKey) {
            // Migrate to Keychain
            KeychainHelper.set(existingID, for: anonymousIDKey)
            return existingID
        }

        // Create new ID
        let newID = UUID().uuidString
        KeychainHelper.set(newID, for: anonymousIDKey)
        UserDefaults.standard.set(newID, forKey: anonymousIDKey)
        return newID
    }

    private static func clearAnonymousID() {
        KeychainHelper.delete(key: anonymousIDKey)
        UserDefaults.standard.removeObject(forKey: anonymousIDKey)
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
