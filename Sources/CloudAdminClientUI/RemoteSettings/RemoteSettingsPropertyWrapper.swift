//
//  RemoteSettingsPropertyWrapper.swift
//  CloudAdminClientUI
//
//  Property wrappers and SwiftUI integration for remote settings
//

import CloudAdminClient
import SwiftUI
import Observation

// MARK: - Settings Key Protocol

/// Protocol for defining type-safe setting keys
///
/// Implement this protocol to create a registry of setting keys with their types and defaults.
///
/// ## Usage
/// ```swift
/// enum AppSettings: SettingsKeyProtocol {
///     static let supportEmail = StringSettingKey("supportEmail", default: "help@example.com")
///     static let maxRetries = IntSettingKey("maxRetries", default: 3)
///     static let maintenanceMode = BoolSettingKey("maintenanceMode", default: false)
/// }
///
/// // Access via observer
/// let email = observer.value(for: AppSettings.supportEmail)
/// ```
public protocol SettingsKeyProtocol {
    associatedtype Value
    var key: String { get }
    var defaultValue: Value { get }
}

// MARK: - Typed Setting Keys

/// A string setting key
public struct StringSettingKey: SettingsKeyProtocol, Sendable {
    public let key: String
    public let defaultValue: String

    public init(_ key: String, default defaultValue: String) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// A bool setting key
public struct BoolSettingKey: SettingsKeyProtocol, Sendable {
    public let key: String
    public let defaultValue: Bool

    public init(_ key: String, default defaultValue: Bool = false) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// An int setting key
public struct IntSettingKey: SettingsKeyProtocol, Sendable {
    public let key: String
    public let defaultValue: Int

    public init(_ key: String, default defaultValue: Int = 0) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// A double setting key
public struct DoubleSettingKey: SettingsKeyProtocol, Sendable {
    public let key: String
    public let defaultValue: Double

    public init(_ key: String, default defaultValue: Double = 0.0) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

/// A URL setting key
public struct URLSettingKey: SettingsKeyProtocol, Sendable {
    public let key: String
    public let defaultValue: URL?

    public init(_ key: String, default defaultValue: URL? = nil) {
        self.key = key
        self.defaultValue = defaultValue
    }
}

// MARK: - Remote Settings Observer

/// Observable class for reactive remote settings updates in SwiftUI
///
/// `RemoteSettingsObserver` provides reactive updates when settings change.
/// Add it to your SwiftUI environment to enable automatic view updates.
///
/// ## Setup
/// ```swift
/// @main
/// struct MyApp: App {
///     @State private var settingsObserver = RemoteSettingsObserver()
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .environment(settingsObserver)
///                 .task {
///                     await settingsObserver.startObserving()
///                 }
///         }
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable
@MainActor
public final class RemoteSettingsObserver {

    /// Current settings (key -> SettingValue)
    public private(set) var settingValues: [String: SettingValue] = [:]

    /// All settings with full metadata
    public private(set) var settings: [String: RemoteSetting] = [:]

    /// Last refresh date
    public private(set) var lastRefresh: Date?

    /// Whether settings are currently being fetched
    public private(set) var isLoading: Bool = false

    /// Last error that occurred
    public private(set) var lastError: Error?

    private var refreshTask: Task<Void, Never>?

    public init() {}

    // MARK: - Type-Safe Accessors

    /// Gets a string value using a typed key
    public func value(for key: StringSettingKey) -> String {
        settingValues[key.key]?.asString ?? key.defaultValue
    }

    /// Gets a bool value using a typed key
    public func value(for key: BoolSettingKey) -> Bool {
        settingValues[key.key]?.asBool ?? key.defaultValue
    }

    /// Gets an int value using a typed key
    public func value(for key: IntSettingKey) -> Int {
        settingValues[key.key]?.asInt ?? key.defaultValue
    }

    /// Gets a double value using a typed key
    public func value(for key: DoubleSettingKey) -> Double {
        settingValues[key.key]?.asDouble ?? key.defaultValue
    }

    /// Gets a URL value using a typed key
    public func value(for key: URLSettingKey) -> URL? {
        settingValues[key.key]?.asURL ?? key.defaultValue
    }

    // MARK: - String Key Accessors

    /// Gets a string value by key
    public func string(for key: String, default defaultValue: String = "") -> String {
        settingValues[key]?.asString ?? defaultValue
    }

    /// Gets a bool value by key
    public func bool(for key: String, default defaultValue: Bool = false) -> Bool {
        settingValues[key]?.asBool ?? defaultValue
    }

    /// Gets an int value by key
    public func int(for key: String, default defaultValue: Int = 0) -> Int {
        settingValues[key]?.asInt ?? defaultValue
    }

    /// Gets a double value by key
    public func double(for key: String, default defaultValue: Double = 0.0) -> Double {
        settingValues[key]?.asDouble ?? defaultValue
    }

    /// Gets a URL value by key
    public func url(for key: String) -> URL? {
        settingValues[key]?.asURL
    }

    // MARK: - Observation

    /// Starts observing remote settings
    public func startObserving(refreshInterval: TimeInterval = 300) async {
        await refresh()

        // Set up periodic refresh
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval))
                await refresh()
            }
        }
    }

    /// Stops observing remote settings
    public func stopObserving() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Manually refreshes settings
    public func refresh() async {
        guard let service = RemoteSettingsService.shared else { return }

        isLoading = true
        lastError = nil

        do {
            try await service.fetchSettings(forceRefresh: true)

            // Update local state
            let allSettings = await service.allSettings
            var newValues: [String: SettingValue] = [:]
            var newSettings: [String: RemoteSetting] = [:]

            for setting in allSettings {
                newValues[setting.key] = setting.value
                newSettings[setting.key] = setting
            }

            settingValues = newValues
            settings = newSettings
            lastRefresh = Date()

        } catch {
            lastError = error
        }

        isLoading = false
    }
}

// MARK: - Environment Key

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct RemoteSettingsObserverKey: EnvironmentKey {
    static let defaultValue: RemoteSettingsObserver? = nil
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension EnvironmentValues {
    /// The remote settings observer for reactive updates
    var remoteSettingsObserver: RemoteSettingsObserver? {
        get { self[RemoteSettingsObserverKey.self] }
        set { self[RemoteSettingsObserverKey.self] = newValue }
    }
}

// MARK: - Property Wrappers

/// Property wrapper for string remote settings
///
/// ## Usage
/// ```swift
/// struct MyView: View {
///     @RemoteStringSetting("supportEmail", default: "help@app.com")
///     var supportEmail: String
///
///     var body: some View {
///         Text(supportEmail)
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@propertyWrapper
public struct RemoteStringSetting: DynamicProperty {
    @Environment(\.remoteSettingsObserver) private var observer

    private let key: String
    private let defaultValue: String

    public init(_ key: String, default defaultValue: String = "") {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: String {
        Self.resolvedValue(key, default: defaultValue, observer: observer)
    }

    @MainActor
    public static func resolvedValue(
        _ key: String,
        default defaultValue: String = "",
        observer: RemoteSettingsObserver? = nil
    ) -> String {
        if let observer {
            return observer.string(for: key, default: defaultValue)
        }
        return RemoteSettingsEvaluationCache.string(for: key, default: defaultValue)
    }
}

/// Property wrapper for bool remote settings
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@propertyWrapper
public struct RemoteBoolSetting: DynamicProperty {
    @Environment(\.remoteSettingsObserver) private var observer

    private let key: String
    private let defaultValue: Bool

    public init(_ key: String, default defaultValue: Bool = false) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: Bool {
        Self.resolvedValue(key, default: defaultValue, observer: observer)
    }

    @MainActor
    public static func resolvedValue(
        _ key: String,
        default defaultValue: Bool = false,
        observer: RemoteSettingsObserver? = nil
    ) -> Bool {
        if let observer {
            return observer.bool(for: key, default: defaultValue)
        }
        return RemoteSettingsEvaluationCache.bool(for: key, default: defaultValue)
    }
}

/// Property wrapper for int remote settings
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@propertyWrapper
public struct RemoteIntSetting: DynamicProperty {
    @Environment(\.remoteSettingsObserver) private var observer

    private let key: String
    private let defaultValue: Int

    public init(_ key: String, default defaultValue: Int = 0) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: Int {
        Self.resolvedValue(key, default: defaultValue, observer: observer)
    }

    @MainActor
    public static func resolvedValue(
        _ key: String,
        default defaultValue: Int = 0,
        observer: RemoteSettingsObserver? = nil
    ) -> Int {
        if let observer {
            return observer.int(for: key, default: defaultValue)
        }
        return RemoteSettingsEvaluationCache.int(for: key, default: defaultValue)
    }
}

/// Property wrapper for double remote settings
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@propertyWrapper
public struct RemoteDoubleSetting: DynamicProperty {
    @Environment(\.remoteSettingsObserver) private var observer

    private let key: String
    private let defaultValue: Double

    public init(_ key: String, default defaultValue: Double = 0.0) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: Double {
        Self.resolvedValue(key, default: defaultValue, observer: observer)
    }

    @MainActor
    public static func resolvedValue(
        _ key: String,
        default defaultValue: Double = 0.0,
        observer: RemoteSettingsObserver? = nil
    ) -> Double {
        if let observer {
            return observer.double(for: key, default: defaultValue)
        }
        return RemoteSettingsEvaluationCache.double(for: key, default: defaultValue)
    }
}

/// Property wrapper for URL remote settings
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@propertyWrapper
public struct RemoteURLSetting: DynamicProperty {
    @Environment(\.remoteSettingsObserver) private var observer

    private let key: String
    private let defaultValue: URL?

    public init(_ key: String, default defaultValue: URL? = nil) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: URL? {
        Self.resolvedValue(key, default: defaultValue, observer: observer)
    }

    @MainActor
    public static func resolvedValue(
        _ key: String,
        default defaultValue: URL? = nil,
        observer: RemoteSettingsObserver? = nil
    ) -> URL? {
        if let observer {
            return observer.url(for: key) ?? defaultValue
        }
        return RemoteSettingsEvaluationCache.url(for: key, default: defaultValue)
    }
}

// MARK: - View Extensions

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension View {

    /// Adds remote settings observer to the environment
    func remoteSettings(_ observer: RemoteSettingsObserver) -> some View {
        environment(\.remoteSettingsObserver, observer)
    }
}

// MARK: - Example Settings Key Registry

/// Example settings key registry showing recommended patterns
///
/// Create your own registry by defining static properties for each setting.
///
/// ## Usage
/// ```swift
/// // Define your settings
/// enum MyAppSettings {
///     static let supportEmail = StringSettingKey("supportEmail", default: "help@app.com")
///     static let maintenanceMode = BoolSettingKey("maintenanceMode", default: false)
///     static let apiTimeout = DoubleSettingKey("apiTimeout", default: 30.0)
///     static let privacyURL = URLSettingKey("privacyPolicyURL")
/// }
///
/// // Use in SwiftUI
/// struct MyView: View {
///     @Environment(\.remoteSettingsObserver) var settings
///
///     var body: some View {
///         if let settings {
///             Text(settings.value(for: MyAppSettings.supportEmail))
///         }
///     }
/// }
/// ```
public enum ExampleSettingsKeys {
    // App Configuration
    public static let minimumSupportedVersion = StringSettingKey("minimumSupportedVersion", default: "1.0.0")
    public static let maintenanceMode = BoolSettingKey("maintenanceMode", default: false)
    public static let apiTimeout = DoubleSettingKey("apiTimeout", default: 30.0)

    // Content/Links
    public static let privacyPolicyURL = URLSettingKey("privacyPolicyURL")
    public static let termsURL = URLSettingKey("termsURL")
    public static let supportEmail = StringSettingKey("supportEmail", default: "support@example.com")
    public static let appStoreURL = URLSettingKey("appStoreURL")

    // Tunable Parameters
    public static let maxRetryCount = IntSettingKey("maxRetryCount", default: 3)
    public static let cacheExpirationHours = DoubleSettingKey("cacheExpirationHours", default: 24.0)
    public static let defaultPageSize = IntSettingKey("defaultPageSize", default: 20)

    // Marketing/Dynamic Content
    public static let promoMessage = StringSettingKey("promoMessage", default: "")
    public static let showPromoBanner = BoolSettingKey("showPromoBanner", default: false)
    public static let promoDeepLink = URLSettingKey("promoDeepLink")
}
