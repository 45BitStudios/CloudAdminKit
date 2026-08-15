//
//  AnalyticsProvider.swift
//  CloudAdminClient
//
//  Protocol-based analytics abstraction for dependency injection.
//  The SwiftUI environment injection lives in CloudAdminClientUI/AnalyticsProviderUI.swift.
//

import Foundation

// MARK: - Analytics Properties

/// A Sendable wrapper for analytics properties
///
/// Use this type instead of `[String: Any]` for Sendable-compliant analytics.
/// Event metadata attached to a tracking call. Values must be `Sendable`; mixed-type
/// dictionary literals (`["count": 3, "label": "ok"]`) satisfy this directly at the call site.
public typealias AnalyticsProperties = [String: any Sendable]

// MARK: - Analytics Provider Protocol

/// Protocol for analytics providers enabling dependency injection and testing
///
/// `AnalyticsProvider` defines the interface for analytics tracking, allowing
/// you to swap implementations (CloudKit, Firebase, custom, or mock) without
/// changing your tracking code.
///
/// ## Usage
/// ```swift
/// // Inject provider via environment
/// ContentView()
///     .environment(\.analyticsProvider, CloudKitAnalyticsProvider())
///
/// // In your view
/// @Environment(\.analyticsProvider) private var analytics
///
/// func handleTap() {
///     Task {
///         await analytics?.trackEvent("button_tapped", properties: ["button": "submit"])
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public protocol AnalyticsProvider: Sendable {

    /// Tracks a screen view
    ///
    /// - Parameters:
    ///   - name: The screen name
    ///   - properties: Additional properties to track
    func trackScreenView(_ name: String, properties: AnalyticsProperties) async

    /// Tracks a custom event
    ///
    /// - Parameters:
    ///   - name: The event name
    ///   - properties: Additional properties to track
    func trackEvent(_ name: String, properties: AnalyticsProperties) async

    /// Tracks an error
    ///
    /// - Parameters:
    ///   - error: The error to track
    ///   - context: Optional context string
    func trackError(_ error: Error, context: String?) async

    /// Tracks a button tap
    ///
    /// - Parameters:
    ///   - buttonName: The button identifier
    ///   - screenName: The screen where the button was tapped
    ///   - properties: Additional properties to track
    func trackButtonTap(_ buttonName: String, screenName: String?, properties: AnalyticsProperties) async

    /// Tracks a feature being used
    ///
    /// - Parameters:
    ///   - featureName: The feature identifier
    ///   - properties: Additional properties to track
    func trackFeature(_ featureName: String, properties: AnalyticsProperties) async

    /// Identifies the user
    ///
    /// - Parameter userID: The user identifier
    func identify(userID: String) async

    /// Clears user identity (on logout)
    func logout() async

    /// Sets a user property
    ///
    /// - Parameters:
    ///   - key: The property key
    ///   - value: The property value
    func setUserProperty(_ key: String, value: any Sendable) async

    /// Flushes pending events
    func flush() async
}

// MARK: - Default Implementations

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension AnalyticsProvider {

    /// Default implementation with empty properties
    func trackScreenView(_ name: String) async {
        await trackScreenView(name, properties: [:])
    }

    /// Default implementation with empty properties
    func trackEvent(_ name: String) async {
        await trackEvent(name, properties: [:])
    }

    /// Default implementation without context
    func trackError(_ error: Error) async {
        await trackError(error, context: nil)
    }

    /// Default implementation with empty properties
    func trackButtonTap(_ buttonName: String, screenName: String? = nil) async {
        await trackButtonTap(buttonName, screenName: screenName, properties: [:])
    }

    /// Default implementation with empty properties
    func trackFeature(_ featureName: String) async {
        await trackFeature(featureName, properties: [:])
    }
}

// MARK: - No-Op Analytics Provider

/// A no-operation analytics provider for testing and previews
///
/// Use this provider when you want to disable analytics tracking,
/// such as in SwiftUI previews, unit tests, or debug builds.
///
/// ## Usage
/// ```swift
/// #if DEBUG
/// .environment(\.analyticsProvider, NoOpAnalyticsProvider())
/// #endif
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct NoOpAnalyticsProvider: AnalyticsProvider {

    public init() {}

    public func trackScreenView(_ name: String, properties: AnalyticsProperties) async {}
    public func trackEvent(_ name: String, properties: AnalyticsProperties) async {}
    public func trackError(_ error: Error, context: String?) async {}
    public func trackButtonTap(_ buttonName: String, screenName: String?, properties: AnalyticsProperties) async {}
    public func trackFeature(_ featureName: String, properties: AnalyticsProperties) async {}
    public func identify(userID: String) async {}
    public func logout() async {}
    public func setUserProperty(_ key: String, value: any Sendable) async {}
    public func flush() async {}
}

// MARK: - Console Analytics Provider

/// A console-logging analytics provider for development
///
/// Prints all analytics events to the console. Useful for debugging
/// analytics integration during development.
///
/// ## Usage
/// ```swift
/// #if DEBUG
/// .environment(\.analyticsProvider, ConsoleAnalyticsProvider())
/// #endif
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct ConsoleAnalyticsProvider: AnalyticsProvider {

    private let prefix: String

    public init(prefix: String = "[Analytics]") {
        self.prefix = prefix
    }

    public func trackScreenView(_ name: String, properties: AnalyticsProperties) async {
        log("Screen: \(name)", properties: properties)
    }

    public func trackEvent(_ name: String, properties: AnalyticsProperties) async {
        log("Event: \(name)", properties: properties)
    }

    public func trackError(_ error: Error, context: String?) async {
        var props: AnalyticsProperties = ["error": error.localizedDescription]
        if let context = context {
            props["context"] = context
        }
        log("Error", properties: props)
    }

    public func trackButtonTap(_ buttonName: String, screenName: String?, properties: AnalyticsProperties) async {
        var props = properties
        props["button"] = buttonName
        if let screen = screenName {
            props["screen"] = screen
        }
        log("Button Tap", properties: props)
    }

    public func trackFeature(_ featureName: String, properties: AnalyticsProperties) async {
        log("Feature: \(featureName)", properties: properties)
    }

    public func identify(userID: String) async {
        log("Identify: \(userID)", properties: [:])
    }

    public func logout() async {
        log("Logout", properties: [:])
    }

    public func setUserProperty(_ key: String, value: any Sendable) async {
        log("User Property: \(key) = \(value)", properties: [:])
    }

    public func flush() async {
        log("Flush", properties: [:])
    }

    private func log(_ message: String, properties: AnalyticsProperties) {
        if properties.isEmpty {
            print("\(prefix) \(message)")
        } else {
            let propsString = properties.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            print("\(prefix) \(message) | {\(propsString)}")
        }
    }
}

// MARK: - CloudKit Analytics Provider Adapter

/// Adapter that wraps AnalyticsService to conform to AnalyticsProvider
///
/// Use this to bridge the existing CloudKit-based AnalyticsService
/// with the AnalyticsProvider protocol.
///
/// ## Usage
/// ```swift
/// let config = AnalyticsConfiguration(containerIdentifier: "iCloud.com.app")
/// AnalyticsService.configure(with: config)
///
/// ContentView()
///     .environment(\.analyticsProvider, CloudKitAnalyticsAdapter())
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct CloudKitAnalyticsAdapter: AnalyticsProvider {

    public init() {}

    public func trackScreenView(_ name: String, properties: AnalyticsProperties) async {
        let anyProps = properties
        await AnalyticsService.shared?.trackScreen(name, properties: anyProps)
    }

    public func trackEvent(_ name: String, properties: AnalyticsProperties) async {
        let anyProps = properties
        await AnalyticsService.shared?.trackCustom(name, properties: anyProps)
    }

    public func trackError(_ error: Error, context: String?) async {
        var props: AnalyticsProperties = [:]
        if let context = context {
            props["context"] = context
        }
        await AnalyticsService.shared?.trackError(error, properties: props)
    }

    public func trackButtonTap(_ buttonName: String, screenName: String?, properties: AnalyticsProperties) async {
        let anyProps = properties
        await AnalyticsService.shared?.trackButtonTap(buttonName, on: screenName, properties: anyProps)
    }

    public func trackFeature(_ featureName: String, properties: AnalyticsProperties) async {
        let anyProps = properties
        await AnalyticsService.shared?.trackFeature(featureName, properties: anyProps)
    }

    public func identify(userID: String) async {
        await AnalyticsService.shared?.identify(userID: userID)
    }

    public func logout() async {
        await AnalyticsService.shared?.logout()
    }

    public func setUserProperty(_ key: String, value: any Sendable) async {
        await AnalyticsService.shared?.setUserProperty(key, value: value)
    }

    public func flush() async {
        await AnalyticsService.shared?.flush()
    }
}

// MARK: - Composite Analytics Provider

/// A provider that forwards events to multiple analytics providers
///
/// Use this when you need to send events to multiple analytics services
/// simultaneously (e.g., CloudKit + Firebase).
///
/// ## Usage
/// ```swift
/// let composite = CompositeAnalyticsProvider(providers: [
///     CloudKitAnalyticsAdapter(),
///     FirebaseAnalyticsAdapter() // Custom implementation
/// ])
///
/// ContentView()
///     .environment(\.analyticsProvider, composite)
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public final class CompositeAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {

    private let providers: [any AnalyticsProvider]
    private let lock = NSLock()

    public init(providers: [any AnalyticsProvider]) {
        self.providers = providers
    }

    public func trackScreenView(_ name: String, properties: AnalyticsProperties) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.trackScreenView(name, properties: properties)
                }
            }
        }
    }

    public func trackEvent(_ name: String, properties: AnalyticsProperties) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.trackEvent(name, properties: properties)
                }
            }
        }
    }

    public func trackError(_ error: Error, context: String?) async {
        let errorDescription = error.localizedDescription
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    // Recreate a simple error to avoid Sendable issues
                    let simpleError = NSError(domain: "Analytics", code: 0, userInfo: [NSLocalizedDescriptionKey: errorDescription])
                    await provider.trackError(simpleError, context: context)
                }
            }
        }
    }

    public func trackButtonTap(_ buttonName: String, screenName: String?, properties: AnalyticsProperties) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.trackButtonTap(buttonName, screenName: screenName, properties: properties)
                }
            }
        }
    }

    public func trackFeature(_ featureName: String, properties: AnalyticsProperties) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.trackFeature(featureName, properties: properties)
                }
            }
        }
    }

    public func identify(userID: String) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.identify(userID: userID)
                }
            }
        }
    }

    public func logout() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.logout()
                }
            }
        }
    }

    public func setUserProperty(_ key: String, value: any Sendable) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.setUserProperty(key, value: value)
                }
            }
        }
    }

    public func flush() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.flush()
                }
            }
        }
    }
}
