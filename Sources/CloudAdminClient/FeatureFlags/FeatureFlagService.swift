//
//  FeatureFlagService.swift
//  CloudAdminClient
//
//  CloudKit-based feature flag service with caching and real-time updates
//

import Foundation
import CloudKit
import Observation

/// Configuration for the feature flag service
public struct FeatureFlagConfiguration: Sendable {
    /// CloudKit container identifier
    public let containerIdentifier: String

    /// Whether to use the public or private database
    public let usePublicDatabase: Bool

    /// Cache expiration interval in seconds (default: 1 hour)
    public let cacheExpirationInterval: TimeInterval

    /// Whether to enable CloudKit subscriptions for real-time updates
    public let enableSubscriptions: Bool

    /// Current app version for version filtering
    public let appVersion: String?

    /// Default flag values when CloudKit is unavailable
    public let defaultFlags: [String: Bool]

    /// Creates a feature flag configuration
    ///
    /// - Parameters:
    ///   - containerIdentifier: CloudKit container ID (e.g., "iCloud.com.company.app")
    ///   - usePublicDatabase: Use public database (default: true)
    ///   - cacheExpirationInterval: Cache TTL in seconds (default: 3600)
    ///   - enableSubscriptions: Enable real-time updates (default: true)
    ///   - appVersion: Current app version for filtering
    ///   - defaultFlags: Default values for flags
    public init(
        containerIdentifier: String,
        usePublicDatabase: Bool = true,
        cacheExpirationInterval: TimeInterval = 3600,
        enableSubscriptions: Bool = true,
        appVersion: String? = nil,
        defaultFlags: [String: Bool] = [:]
    ) {
        self.containerIdentifier = containerIdentifier
        self.usePublicDatabase = usePublicDatabase
        self.cacheExpirationInterval = cacheExpirationInterval
        self.enableSubscriptions = enableSubscriptions
        self.appVersion = appVersion
        self.defaultFlags = defaultFlags
    }
}

/// Errors that can occur in the feature flag service
public enum FeatureFlagError: Error, LocalizedError {
    case cloudKitNotAvailable
    case fetchFailed(Error)
    case subscriptionFailed(Error)
    case cacheFailed(Error)
    case flagNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .cloudKitNotAvailable:
            return "CloudKit is not available"
        case .fetchFailed(let error):
            return "Failed to fetch feature flags: \(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "Failed to set up subscription: \(error.localizedDescription)"
        case .cacheFailed(let error):
            return "Failed to cache flags: \(error.localizedDescription)"
        case .flagNotFound(let key):
            return "Feature flag not found: \(key)"
        }
    }
}

/// Service for managing feature flags with CloudKit backend and local caching
///
/// `FeatureFlagService` provides a complete solution for remote feature flags:
/// - Fetches flags from CloudKit public database
/// - Caches flags locally for offline access
/// - Supports real-time updates via CloudKit subscriptions
/// - Filters flags by platform and app version
///
/// ## Usage
/// ```swift
/// let config = FeatureFlagConfiguration(
///     containerIdentifier: "iCloud.com.company.app",
///     appVersion: "2.0.0",
///     defaultFlags: ["newFeature": false]
/// )
///
/// let service = FeatureFlagService(configuration: config)
/// await service.fetchFlags()
///
/// if await service.isEnabled("newFeature") {
///     // Show new feature
/// }
/// ```
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public actor FeatureFlagService {

    // MARK: - Properties

    private let configuration: FeatureFlagConfiguration
    private let container: CKContainer
    private let database: CKDatabase

    private var flags: [String: FeatureFlag] = [:]
    private var lastFetchDate: Date?
    private var subscriptionID: CKSubscription.ID?

    private let cache: FeatureFlagCache

    // MARK: - Singleton

    /// Shared instance (must be configured before use)
    @MainActor
    public static var shared: FeatureFlagService?

    /// Configures the shared instance
    ///
    /// - Parameter configuration: Service configuration
    /// - Returns: The configured shared instance
    @MainActor
    @discardableResult
    public static func configure(with configuration: FeatureFlagConfiguration) -> FeatureFlagService {
        let service = FeatureFlagService(configuration: configuration)
        shared = service
        return service
    }

    // MARK: - Initialization

    /// Creates a feature flag service
    ///
    /// - Parameter configuration: Service configuration
    public init(configuration: FeatureFlagConfiguration) {
        self.configuration = configuration
        self.container = CKContainer(identifier: configuration.containerIdentifier)
        self.database = configuration.usePublicDatabase
            ? container.publicCloudDatabase
            : container.privateCloudDatabase
        self.cache = FeatureFlagCache(
            suiteName: configuration.containerIdentifier,
            expirationInterval: configuration.cacheExpirationInterval
        )

        // Load cached flags immediately
        Task {
            await loadCachedFlags()
        }
    }

    // MARK: - Public API

    /// Checks if a feature flag is enabled
    ///
    /// - Parameter key: The flag key to check
    /// - Returns: true if the flag is enabled and applicable
    public func isEnabled(_ key: String) -> Bool {
        if let flag = flags[key] {
            return flag.evaluate(appVersion: configuration.appVersion)
        }

        // Fall back to default value
        return configuration.defaultFlags[key] ?? false
    }

    /// Gets a feature flag by key
    ///
    /// - Parameter key: The flag key
    /// - Returns: The feature flag or nil if not found
    public func flag(forKey key: String) -> FeatureFlag? {
        return flags[key]
    }

    /// Gets all feature flags
    public var allFlags: [FeatureFlag] {
        return Array(flags.values)
    }

    /// Gets flags applicable to the current platform
    public var applicableFlags: [FeatureFlag] {
        return flags.values.filter { $0.isApplicableToCurrentPlatform }
    }

    /// Fetches feature flags from CloudKit
    ///
    /// - Parameter forceRefresh: Bypass cache and fetch from CloudKit
    /// - Throws: FeatureFlagError if fetch fails
    public func fetchFlags(forceRefresh: Bool = false) async throws {
        // Check cache validity
        if !forceRefresh, let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < configuration.cacheExpirationInterval {
            return
        }

        // Use TRUEPREDICATE to fetch all records without requiring indexed fields
        let query = CKQuery(recordType: FeatureFlag.recordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
        // Note: Sort locally to avoid requiring CloudKit indexes

        do {
            let (results, _) = try await database.records(matching: query)

            var newFlags: [String: FeatureFlag] = [:]

            for (_, result) in results {
                if case .success(let record) = result,
                   let flag = FeatureFlag(from: record) {
                    newFlags[flag.key] = flag
                }
            }

            self.flags = newFlags
            self.lastFetchDate = Date()

            // Update cache
            await saveToCache()

        } catch {
            // On failure, use cached data if available
            if flags.isEmpty {
                await loadCachedFlags()
            }
            throw FeatureFlagError.fetchFailed(error)
        }
    }

    /// Sets up CloudKit subscription for real-time updates
    ///
    /// - Throws: FeatureFlagError if subscription fails
    public func setupSubscription() async throws {
        guard configuration.enableSubscriptions else { return }

        let subscriptionID = "feature-flag-changes"

        let subscription = CKQuerySubscription(
            recordType: FeatureFlag.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // Silent notification
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            self.subscriptionID = subscriptionID
        } catch {
            throw FeatureFlagError.subscriptionFailed(error)
        }
    }

    /// Handles a CloudKit notification for flag updates
    ///
    /// Call this from your app delegate when receiving a CloudKit notification
    public func handleNotification() async {
        do {
            try await fetchFlags(forceRefresh: true)
        } catch {
            print("Failed to refresh flags after notification: \(error)")
        }
    }

    /// Removes the CloudKit subscription
    public func removeSubscription() async throws {
        guard let subscriptionID = subscriptionID else { return }

        do {
            try await database.deleteSubscription(withID: subscriptionID)
            self.subscriptionID = nil
        } catch {
            throw FeatureFlagError.subscriptionFailed(error)
        }
    }

    /// Clears all cached flags
    public func clearCache() async {
        await cache.clear()
        flags.removeAll()
        lastFetchDate = nil
    }

    // MARK: - Local Overrides (Debug)

    #if DEBUG
    private var localOverrides: [String: Bool] = [:]

    /// Sets a local override for a flag (debug only)
    ///
    /// - Parameters:
    ///   - key: Flag key
    ///   - value: Override value (nil to remove override)
    public func setOverride(_ key: String, value: Bool?) {
        if let value = value {
            localOverrides[key] = value
        } else {
            localOverrides.removeValue(forKey: key)
        }
    }

    /// Checks if a flag has a local override
    public func hasOverride(_ key: String) -> Bool {
        return localOverrides[key] != nil
    }

    /// Gets all local overrides
    public var overrides: [String: Bool] {
        return localOverrides
    }

    /// Clears all local overrides
    public func clearOverrides() {
        localOverrides.removeAll()
    }

    /// Checks if a feature flag is enabled (with override support)
    public func isEnabledWithOverrides(_ key: String) -> Bool {
        if let override = localOverrides[key] {
            return override
        }
        return isEnabled(key)
    }
    #endif

    // MARK: - Private Methods

    private func loadCachedFlags() async {
        let cached = await cache.loadFlags()
        if !cached.isEmpty {
            for flag in cached {
                flags[flag.key] = flag
            }
        }
    }

    private func saveToCache() async {
        let flagsArray = Array(flags.values)
        await cache.saveFlags(flagsArray)
    }
}

// MARK: - Feature Flag Cache

/// Local cache for feature flags using UserDefaults
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
actor FeatureFlagCache {
    private let defaults: UserDefaults
    private let cacheKey = "com.cloudadminkit.featureflags.cache"
    private let timestampKey = "com.cloudadminkit.featureflags.timestamp"
    private let expirationInterval: TimeInterval

    init(suiteName: String?, expirationInterval: TimeInterval) {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.expirationInterval = expirationInterval
    }

    func saveFlags(_ flags: [FeatureFlag]) {
        guard let data = try? JSONEncoder().encode(flags) else { return }
        defaults.set(data, forKey: cacheKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }

    func loadFlags() -> [FeatureFlag] {
        // Check if cache is expired
        let timestamp = defaults.double(forKey: timestampKey)
        if timestamp > 0 {
            let cacheDate = Date(timeIntervalSince1970: timestamp)
            if Date().timeIntervalSince(cacheDate) > expirationInterval {
                return [] // Cache expired
            }
        }

        guard let data = defaults.data(forKey: cacheKey),
              let flags = try? JSONDecoder().decode([FeatureFlag].self, from: data) else {
            return []
        }
        return flags
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

// MARK: - Convenience Extensions

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
extension FeatureFlagService {

    /// Fetches flags and sets up subscription in one call
    public func initialize() async throws {
        try await fetchFlags()
        try await setupSubscription()
    }

    /// Gets a typed payload value from a flag
    ///
    /// - Parameters:
    ///   - key: Flag key
    ///   - payloadKey: Key within the payload JSON
    /// - Returns: The value or nil
    public func payloadValue<T>(forFlag key: String, payloadKey: String) -> T? {
        return flags[key]?.payloadValue(forKey: payloadKey)
    }

    /// Decodes a flag's payload to a specific type
    ///
    /// - Parameters:
    ///   - key: Flag key
    ///   - type: Type to decode to
    /// - Returns: Decoded value or nil
    public func decodePayload<T: Decodable>(forFlag key: String, as type: T.Type) -> T? {
        return flags[key]?.decodePayload(as: type)
    }
}
