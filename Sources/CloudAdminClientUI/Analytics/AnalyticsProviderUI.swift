//
//  AnalyticsProviderUI.swift
//  CloudAdminClientUI
//
//  SwiftUI environment injection for AnalyticsProvider (split out of the core
//  AnalyticsProvider.swift in CloudAdminClient, which must stay SwiftUI-free).
//

import CloudAdminClient
import SwiftUI

// MARK: - Environment Key

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct AnalyticsProviderKey: EnvironmentKey {
    static let defaultValue: (any AnalyticsProvider)? = nil
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension EnvironmentValues {
    /// The analytics provider for dependency injection
    ///
    /// ## Usage
    /// ```swift
    /// @Environment(\.analyticsProvider) private var analytics
    ///
    /// Task {
    ///     await analytics?.trackEvent("action_performed")
    /// }
    /// ```
    var analyticsProvider: (any AnalyticsProvider)? {
        get { self[AnalyticsProviderKey.self] }
        set { self[AnalyticsProviderKey.self] = newValue }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension View {
    /// Injects an analytics provider into the environment
    ///
    /// - Parameter provider: The analytics provider to inject
    /// - Returns: A view with the analytics provider in its environment
    func analyticsProvider(_ provider: any AnalyticsProvider) -> some View {
        environment(\.analyticsProvider, provider)
    }
}
