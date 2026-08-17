//
//  RemoteSettingsService.swift
//  CloudAdminClient
//
//  CloudKit-based remote settings service with caching and type-safe access
//

import Foundation
import CloudKit

// MARK: - Configuration

/// Configuration for the remote settings service
public struct RemoteSettingsConfiguration: Sendable {
    /// CloudKit container identifier
    public let containerIdentifier: String

    /// Whether to use the public or private database
    public let usePublicDatabase: Bool

    /// Cache expiration interval in seconds (default: 1 hour)
    public let cacheExpirationInterval: TimeInterval

    /// Whether to enable CloudKit subscriptions for real-time updates
    public let enableSubscriptions: Bool

    /// Default values for settings (key -> SettingValue)
    public let defaults: [String: SettingValue]

    /// Required settings that must exist (fatal in debug if missing)
    public let requiredKeys: Set<String>

    /// Creates a remote settings configuration
    ///
    /// - Parameters:
    ///   - containerIdentifier: CloudKit container ID
    ///   - usePublicDatabase: Use public database (default: true)
    ///   - cacheExpirationInterval: Cache TTL in seconds (default: 3600)
    ///   - enableSubscriptions: Enable real-time updates (default: true)
    ///   - defaults: Default values for settings
    ///   - requiredKeys: Keys that must exist
    public init(
        containerIdentifier: String,
        usePublicDatabase: Bool = true,
        cacheExpirationInterval: TimeInterval = 3600,
        enableSubscriptions: Bool = true,
        defaults: [String: SettingValue] = [:],
        requiredKeys: Set<String> = []
    ) {
        self.containerIdentifier = containerIdentifier
        self.usePublicDatabase = usePublicDatabase
        self.cacheExpirationInterval = cacheExpirationInterval
        self.enableSubscriptions = enableSubscriptions
        self.defaults = defaults
        self.requiredKeys = requiredKeys
    }
}

// MARK: - Evaluation cache

/// Last-known setting values published by ``RemoteSettingsService``.
///
/// `@Remote*Setting` wrappers read this when no `RemoteSettingsObserver` is in the environment.
/// Updated after `configure`, `fetchSettings()`, and cache load.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
@MainActor
public enum RemoteSettingsEvaluationCache {
    /// Whether ``RemoteSettingsService/configure(with:)`` has run in this process.
    public private(set) static var isConfigured = false

    /// Key → value, defaults merged under fetched settings.
    public private(set) static var values: [String: SettingValue] = [:]

    public static func string(for key: String, default defaultValue: String) -> String {
        guard isConfigured else { return defaultValue }
        return values[key]?.asString ?? defaultValue
    }

    public static func bool(for key: String, default defaultValue: Bool) -> Bool {
        guard isConfigured else { return defaultValue }
        return values[key]?.asBool ?? defaultValue
    }

    public static func int(for key: String, default defaultValue: Int) -> Int {
        guard isConfigured else { return defaultValue }
        return values[key]?.asInt ?? defaultValue
    }

    public static func double(for key: String, default defaultValue: Double) -> Double {
        guard isConfigured else { return defaultValue }
        return values[key]?.asDouble ?? defaultValue
    }

    public static func url(for key: String, default defaultValue: URL?) -> URL? {
        guard isConfigured else { return defaultValue }
        return values[key]?.asURL ?? defaultValue
    }

    /// Test hook — clears the process-wide snapshot.
    public static func reset() {
        isConfigured = false
        values = [:]
    }

    static func markConfigured(defaults: [String: SettingValue]) {
        isConfigured = true
        values = defaults
    }

    static func replace(_ newValues: [String: SettingValue]) {
        isConfigured = true
        values = newValues
    }
}

// MARK: - Errors

/// Errors that can occur in the remote settings service
public enum RemoteSettingsError: Error, LocalizedError {
    case cloudKitNotAvailable
    case fetchFailed(Error)
    case subscriptionFailed(Error)
    case settingNotFound(String)
    case typeMismatch(key: String, expected: SettingValueType, actual: SettingValueType)
    case requiredSettingMissing(String)

    public var errorDescription: String? {
        switch self {
        case .cloudKitNotAvailable:
            return "CloudKit is not available"
        case .fetchFailed(let error):
            return "Failed to fetch settings: \(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "Failed to set up subscription: \(error.localizedDescription)"
        case .settingNotFound(let key):
            return "Setting not found: \(key)"
        case .typeMismatch(let key, let expected, let actual):
            return "Type mismatch for '\(key)': expected \(expected.displayName), got \(actual.displayName)"
        case .requiredSettingMissing(let key):
            return "Required setting missing: \(key)"
        }
    }
}

// MARK: - Remote Settings Service

/// Service for managing remote settings with CloudKit backend and local caching
///
/// `RemoteSettingsService` provides type-safe access to remotely configured settings:
/// - Fetches settings from CloudKit public database
/// - Caches settings locally for offline access
/// - Supports real-time updates via CloudKit subscriptions
/// - Provides type-safe accessors for different value types
///
/// ## Usage
/// ```swift
/// let config = RemoteSettingsConfiguration(
///     containerIdentifier: "iCloud.com.company.app",
///     defaults: [
///         "supportEmail": .string("help@example.com"),
///         "maxRetries": .int(3)
///     ]
/// )
///
/// let service = RemoteSettingsService(configuration: config)
/// await service.fetchSettings()
///
/// let email = await service.string(for: "supportEmail")
/// let retries = await service.int(for: "maxRetries", default: 5)
/// ```
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public actor RemoteSettingsService {

    // MARK: - Properties

    private let configuration: RemoteSettingsConfiguration
    private var container: CKContainer {
        CKContainer(identifier: configuration.containerIdentifier)
    }
    private var database: CKDatabase {
        configuration.usePublicDatabase
            ? container.publicCloudDatabase
            : container.privateCloudDatabase
    }

    private var settings: [String: RemoteSetting] = [:]
    private var lastFetchDate: Date?
    private var subscriptionID: CKSubscription.ID?

    private let cache: RemoteSettingsCache

    // MARK: - Singleton

    /// Shared instance (must be configured before use)
    @MainActor
    public static var shared: RemoteSettingsService?

    /// Configures the shared instance
    @MainActor
    @discardableResult
    public static func configure(with configuration: RemoteSettingsConfiguration) -> RemoteSettingsService {
        RemoteSettingsEvaluationCache.markConfigured(defaults: configuration.defaults)
        let service = RemoteSettingsService(configuration: configuration)
        shared = service
        return service
    }

    // MARK: - Initialization

    /// Creates a remote settings service
    public init(configuration: RemoteSettingsConfiguration) {
        self.configuration = configuration
        self.cache = RemoteSettingsCache(
            suiteName: configuration.containerIdentifier,
            expirationInterval: configuration.cacheExpirationInterval
        )

        // Load cached settings immediately
        Task {
            await loadCachedSettings()
            await publishEvaluationCache()
        }
    }

    // MARK: - Type-Safe Accessors

    /// Gets a string setting value
    ///
    /// - Parameters:
    ///   - key: The setting key
    ///   - defaultValue: Default value if setting not found or wrong type
    /// - Returns: The string value or default
    public func string(for key: String, default defaultValue: String? = nil) -> String? {
        if let setting = settings[key], let value = setting.value.asString {
            return value
        }
        if let defaultSetting = configuration.defaults[key], let value = defaultSetting.asString {
            return value
        }
        return defaultValue
    }

    /// Gets a bool setting value
    ///
    /// - Parameters:
    ///   - key: The setting key
    ///   - defaultValue: Default value if setting not found or wrong type
    /// - Returns: The bool value or default
    public func bool(for key: String, default defaultValue: Bool = false) -> Bool {
        if let setting = settings[key], let value = setting.value.asBool {
            return value
        }
        if let defaultSetting = configuration.defaults[key], let value = defaultSetting.asBool {
            return value
        }
        return defaultValue
    }

    /// Gets an int setting value
    ///
    /// - Parameters:
    ///   - key: The setting key
    ///   - defaultValue: Default value if setting not found or wrong type
    /// - Returns: The int value or default
    public func int(for key: String, default defaultValue: Int = 0) -> Int {
        if let setting = settings[key], let value = setting.value.asInt {
            return value
        }
        if let defaultSetting = configuration.defaults[key], let value = defaultSetting.asInt {
            return value
        }
        return defaultValue
    }

    /// Gets a double setting value
    ///
    /// - Parameters:
    ///   - key: The setting key
    ///   - defaultValue: Default value if setting not found or wrong type
    /// - Returns: The double value or default
    public func double(for key: String, default defaultValue: Double = 0.0) -> Double {
        if let setting = settings[key], let value = setting.value.asDouble {
            return value
        }
        if let defaultSetting = configuration.defaults[key], let value = defaultSetting.asDouble {
            return value
        }
        return defaultValue
    }

    /// Gets a URL setting value
    ///
    /// - Parameters:
    ///   - key: The setting key
    ///   - defaultValue: Default value if setting not found or wrong type
    /// - Returns: The URL value or default
    public func url(for key: String, default defaultValue: URL? = nil) -> URL? {
        if let setting = settings[key], let value = setting.value.asURL {
            return value
        }
        if let defaultSetting = configuration.defaults[key], let value = defaultSetting.asURL {
            return value
        }
        return defaultValue
    }

    /// Gets the raw SettingValue for a key
    ///
    /// - Parameter key: The setting key
    /// - Returns: The setting value or nil
    public func value(for key: String) -> SettingValue? {
        if let setting = settings[key] {
            return setting.value
        }
        return configuration.defaults[key]
    }

    /// Gets a setting by key
    ///
    /// - Parameter key: The setting key
    /// - Returns: The full RemoteSetting or nil
    public func setting(for key: String) -> RemoteSetting? {
        return settings[key]
    }

    /// Gets all settings
    public var allSettings: [RemoteSetting] {
        return Array(settings.values)
    }

    /// Gets all setting keys
    public var allKeys: [String] {
        return Array(settings.keys).sorted()
    }

    // MARK: - Fetch and Sync

    /// Fetches settings from CloudKit
    ///
    /// - Parameter forceRefresh: Bypass cache and fetch from CloudKit
    /// - Throws: RemoteSettingsError if fetch fails
    public func fetchSettings(forceRefresh: Bool = false) async throws {
        // Check cache validity
        if !forceRefresh, let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < configuration.cacheExpirationInterval {
            return
        }

        // Use TRUEPREDICATE to fetch all records without requiring indexed fields
        let query = CKQuery(recordType: RemoteSetting.recordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
        // Note: Sort locally to avoid requiring CloudKit indexes

        do {
            let (results, _) = try await database.records(matching: query)

            var newSettings: [String: RemoteSetting] = [:]

            for (_, result) in results {
                if case .success(let record) = result,
                   let setting = RemoteSetting(from: record) {
                    newSettings[setting.key] = setting
                }
            }

            self.settings = newSettings
            self.lastFetchDate = Date()

            // Validate required settings
            try validateRequiredSettings()

            // Update cache
            await saveToCache()
            await publishEvaluationCache()

        } catch {
            // On failure, use cached data if available
            if settings.isEmpty {
                await loadCachedSettings()
            }
            throw RemoteSettingsError.fetchFailed(error)
        }
    }

    /// Validates that all required settings exist
    private func validateRequiredSettings() throws {
        for key in configuration.requiredKeys {
            if settings[key] == nil && configuration.defaults[key] == nil {
                #if DEBUG
                assertionFailure("Required setting missing: \(key)")
                #endif
                throw RemoteSettingsError.requiredSettingMissing(key)
            }
        }
    }

    /// Sets up CloudKit subscription for real-time updates
    public func setupSubscription() async throws {
        guard configuration.enableSubscriptions else { return }

        let subscriptionID = "remote-settings-changes"

        let subscription = CKQuerySubscription(
            recordType: RemoteSetting.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            self.subscriptionID = subscriptionID
        } catch {
            throw RemoteSettingsError.subscriptionFailed(error)
        }
    }

    /// Handles a CloudKit notification for setting updates
    public func handleNotification() async {
        do {
            try await fetchSettings(forceRefresh: true)
        } catch {
            print("Failed to refresh settings after notification: \(error)")
        }
    }

    /// Removes the CloudKit subscription
    public func removeSubscription() async throws {
        guard let subscriptionID = subscriptionID else { return }

        do {
            try await database.deleteSubscription(withID: subscriptionID)
            self.subscriptionID = nil
        } catch {
            throw RemoteSettingsError.subscriptionFailed(error)
        }
    }

    /// Clears all cached settings
    public func clearCache() async {
        await cache.clear()
        settings.removeAll()
        lastFetchDate = nil
        await publishEvaluationCache()
    }

    // MARK: - Private Methods

    private func publishEvaluationCache() async {
        var merged = configuration.defaults
        for (key, setting) in settings {
            merged[key] = setting.value
        }
        await MainActor.run {
            RemoteSettingsEvaluationCache.replace(merged)
        }
    }

    private func loadCachedSettings() async {
        let cached = await cache.loadSettings()
        if !cached.isEmpty {
            for setting in cached {
                settings[setting.key] = setting
            }
        }
    }

    private func saveToCache() async {
        let settingsArray = Array(settings.values)
        await cache.saveSettings(settingsArray)
    }
}

// MARK: - Convenience Extensions

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
extension RemoteSettingsService {

    /// Fetches settings and sets up subscription in one call
    public func initialize() async throws {
        try await fetchSettings()
        try await setupSubscription()
    }

    /// Checks if a setting exists
    public func exists(_ key: String) -> Bool {
        return settings[key] != nil || configuration.defaults[key] != nil
    }

    /// Gets a required string (fatal in debug if missing)
    public func requiredString(for key: String) -> String {
        guard let value = string(for: key) else {
            #if DEBUG
            fatalError("Required string setting missing: \(key)")
            #else
            return ""
            #endif
        }
        return value
    }

    /// Gets a required URL (fatal in debug if missing)
    public func requiredURL(for key: String) -> URL {
        guard let value = url(for: key) else {
            #if DEBUG
            fatalError("Required URL setting missing: \(key)")
            #else
            return URL(string: "https://example.com")!
            #endif
        }
        return value
    }
}

// MARK: - Remote Settings Cache

/// Local cache for remote settings using UserDefaults
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
actor RemoteSettingsCache {
    private let defaults: UserDefaults
    private let cacheKey = "com.cloudadminkit.remotesettings.cache"
    private let timestampKey = "com.cloudadminkit.remotesettings.timestamp"
    private let expirationInterval: TimeInterval

    init(suiteName: String?, expirationInterval: TimeInterval) {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.expirationInterval = expirationInterval
    }

    func saveSettings(_ settings: [RemoteSetting]) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: cacheKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }

    func loadSettings() -> [RemoteSetting] {
        // Check if cache is expired
        let timestamp = defaults.double(forKey: timestampKey)
        if timestamp > 0 {
            let cacheDate = Date(timeIntervalSince1970: timestamp)
            if Date().timeIntervalSince(cacheDate) > expirationInterval {
                return []
            }
        }

        guard let data = defaults.data(forKey: cacheKey),
              let settings = try? JSONDecoder().decode([RemoteSetting].self, from: data) else {
            return []
        }
        return settings
    }

    func clear() {
        defaults.removeObject(forKey: cacheKey)
        defaults.removeObject(forKey: timestampKey)
    }

    var isCacheValid: Bool {
        let timestamp = defaults.double(forKey: timestampKey)
        guard timestamp > 0 else { return false }
        let cacheDate = Date(timeIntervalSince1970: timestamp)
        return Date().timeIntervalSince(cacheDate) <= expirationInterval
    }
}
