//
//  FeatureFlagPropertyWrapper.swift
//  CloudAdminClientUI
//
//  Property wrapper for convenient feature flag access in SwiftUI
//

import CloudAdminClient
import SwiftUI
import Observation

/// Property wrapper for accessing feature flags in SwiftUI views
///
/// `@FeatureEnabled` provides a convenient way to check if a feature flag is enabled
/// directly within SwiftUI views. It automatically reads from the shared
/// `FeatureFlagService` instance.
///
/// ## Usage
/// ```swift
/// struct MyView: View {
///     @FeatureEnabled("newOnboarding") var showNewOnboarding
///     @FeatureEnabled("darkMode", default: true) var darkModeEnabled
///
///     var body: some View {
///         if showNewOnboarding {
///             NewOnboardingView()
///         } else {
///             LegacyOnboardingView()
///         }
///     }
/// }
/// ```
///
/// ## Requirements
/// - `FeatureFlagService.shared` must be configured before use
/// - For reactive updates, use with `FeatureFlagObserver` in the environment
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@propertyWrapper
public struct FeatureEnabled: DynamicProperty {
    @Environment(\.featureFlagObserver) private var observer

    private let key: String
    private let defaultValue: Bool

    /// Creates a feature flag property wrapper
    ///
    /// - Parameters:
    ///   - key: The feature flag key
    ///   - default: Default value if flag is not found (default: false)
    public init(_ key: String, default defaultValue: Bool = false) {
        self.key = key
        self.defaultValue = defaultValue
    }

    @MainActor
    public var wrappedValue: Bool {
        Self.resolvedValue(key, default: defaultValue, observer: observer)
    }

    /// Resolves a flag without constructing a SwiftUI view. Observer wins when
    /// present; otherwise the service evaluation cache (or `defaultValue` if
    /// the service was never configured).
    @MainActor
    public static func resolvedValue(
        _ key: String,
        default defaultValue: Bool = false,
        observer: FeatureFlagObserver? = nil
    ) -> Bool {
        if let observer {
            return observer.flagStates[key] ?? defaultValue
        }
        return FeatureFlagEvaluationCache.isEnabled(key, default: defaultValue)
    }
}

/// Observable class for reactive feature flag updates in SwiftUI
///
/// `FeatureFlagObserver` provides reactive updates when feature flags change.
/// Add it to your SwiftUI environment to enable automatic view updates.
///
/// ## Setup
/// ```swift
/// @main
/// struct MyApp: App {
///     @State private var flagObserver = FeatureFlagObserver()
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .environment(flagObserver)
///                 .task {
///                     await flagObserver.startObserving()
///                 }
///         }
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable
@MainActor
public final class FeatureFlagObserver {

    /// Current flag states (key -> enabled)
    public private(set) var flagStates: [String: Bool] = [:]

    /// Last refresh date
    public private(set) var lastRefresh: Date?

    /// Whether flags are currently being fetched
    public private(set) var isLoading: Bool = false

    /// Last error that occurred
    public private(set) var lastError: Error?

    private var refreshTask: Task<Void, Never>?

    public init() {}

    /// Checks if a feature flag is enabled
    ///
    /// - Parameters:
    ///   - key: The flag key
    ///   - defaultValue: Default if flag not found
    /// - Returns: Whether the flag is enabled
    public func isEnabled(_ key: String, default defaultValue: Bool = false) -> Bool {
        return flagStates[key] ?? defaultValue
    }

    /// Starts observing feature flags
    ///
    /// This fetches initial flags and sets up periodic refresh
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

    /// Stops observing feature flags
    public func stopObserving() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Manually refreshes feature flags
    public func refresh() async {
        guard let service = FeatureFlagService.shared else { return }

        isLoading = true
        lastError = nil

        do {
            try await service.fetchFlags(forceRefresh: true)

            // Update local state
            let flags = await service.allFlags
            var newStates: [String: Bool] = [:]
            for flag in flags {
                newStates[flag.key] = await service.isEnabled(flag.key)
            }
            flagStates = newStates
            lastRefresh = Date()

        } catch {
            lastError = error
        }

        isLoading = false
    }

    #if DEBUG
    /// Sets a local override (debug only)
    public func setOverride(_ key: String, value: Bool?) async {
        guard let service = FeatureFlagService.shared else { return }
        await service.setOverride(key, value: value)

        // Update local state
        if let value = value {
            flagStates[key] = value
        } else {
            await refresh()
        }
    }
    #endif
}

// MARK: - Environment Key

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct FeatureFlagObserverKey: EnvironmentKey {
    static let defaultValue: FeatureFlagObserver? = nil
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension EnvironmentValues {
    /// The feature flag observer for reactive updates
    var featureFlagObserver: FeatureFlagObserver? {
        get { self[FeatureFlagObserverKey.self] }
        set { self[FeatureFlagObserverKey.self] = newValue }
    }
}

// MARK: - View Extensions

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension View {

    /// Adds feature flag observer to the environment
    ///
    /// - Parameter observer: The observer instance
    /// - Returns: Modified view with observer in environment
    func featureFlags(_ observer: FeatureFlagObserver) -> some View {
        environment(\.featureFlagObserver, observer)
    }

    /// Conditionally shows content based on a feature flag
    ///
    /// - Parameters:
    ///   - flag: The flag key to check
    ///   - defaultValue: Default if flag not found
    ///   - content: Content to show when flag is enabled
    /// - Returns: Modified view
    @ViewBuilder
    func featureFlag<Content: View>(
        _ flag: String,
        default defaultValue: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        FeatureFlagConditionalView(flag: flag, defaultValue: defaultValue, content: content)
    }
}

/// Internal view for conditional feature flag rendering
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct FeatureFlagConditionalView<Content: View>: View {
    @Environment(\.featureFlagObserver) private var observer

    let flag: String
    let defaultValue: Bool
    let content: () -> Content

    var body: some View {
        if observer?.isEnabled(flag, default: defaultValue) ?? defaultValue {
            content()
        }
    }
}

// MARK: - Feature Flag View Modifier

/// View modifier that shows/hides content based on feature flag
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct FeatureFlagModifier: ViewModifier {
    @Environment(\.featureFlagObserver) private var observer

    let flag: String
    let defaultValue: Bool
    let showWhenEnabled: Bool

    public init(flag: String, default defaultValue: Bool = false, showWhenEnabled: Bool = true) {
        self.flag = flag
        self.defaultValue = defaultValue
        self.showWhenEnabled = showWhenEnabled
    }

    public func body(content: Content) -> some View {
        let isEnabled = observer?.isEnabled(flag, default: defaultValue) ?? defaultValue
        let shouldShow = showWhenEnabled ? isEnabled : !isEnabled

        if shouldShow {
            content
        }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension View {
    /// Shows the view only when a feature flag is enabled
    ///
    /// - Parameters:
    ///   - flag: The flag key
    ///   - default: Default value if flag not found
    /// - Returns: Modified view
    func showWhenFeatureEnabled(_ flag: String, default defaultValue: Bool = false) -> some View {
        modifier(FeatureFlagModifier(flag: flag, default: defaultValue, showWhenEnabled: true))
    }

    /// Hides the view when a feature flag is enabled
    ///
    /// - Parameters:
    ///   - flag: The flag key
    ///   - default: Default value if flag not found
    /// - Returns: Modified view
    func hideWhenFeatureEnabled(_ flag: String, default defaultValue: Bool = false) -> some View {
        modifier(FeatureFlagModifier(flag: flag, default: defaultValue, showWhenEnabled: false))
    }
}
