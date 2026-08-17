//
//  AnalyticsSwiftUI.swift
//  CloudAdminClientUI
//
//  SwiftUI integration for analytics tracking
//

import CloudAdminClient
import SwiftUI
import Observation

// MARK: - Analytics Observer

/// Observable class for reactive analytics state in SwiftUI
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable
@MainActor
public final class AnalyticsObserver {

    /// Current session ID
    public private(set) var sessionID: UUID?

    /// Current user ID (nil for anonymous)
    public private(set) var userID: String?

    /// Number of events in queue
    public private(set) var queueSize: Int = 0

    /// Whether analytics is enabled
    public private(set) var isEnabled: Bool = true

    /// Recent events (for debugging)
    public private(set) var recentEvents: [AnalyticsEvent] = []

    /// Last upload time
    public private(set) var lastUploadTime: Date?

    private var refreshTask: Task<Void, Never>?

    public init() {}

    /// Starts observing analytics state
    public func startObserving(refreshInterval: TimeInterval = 5) async {
        await refresh()

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval))
                await refresh()
            }
        }
    }

    /// Stops observing
    public func stopObserving() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Refreshes analytics state
    public func refresh() async {
        guard let service = AnalyticsService.shared else { return }

        queueSize = await service.queueSize
        recentEvents = await service.recentEvents
        isEnabled = await service.isEnabled
    }

    /// Identifies the user
    public func identify(userID: String) async {
        await AnalyticsService.shared?.identify(userID: userID)
        self.userID = userID
    }

    /// Logs out the user
    public func logout() async {
        await AnalyticsService.shared?.logout()
        self.userID = nil
    }

    /// Flushes the event queue
    public func flush() async {
        await AnalyticsService.shared?.flush()
        await refresh()
    }
}

// MARK: - Environment Key

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
private struct AnalyticsObserverKey: EnvironmentKey {
    static let defaultValue: AnalyticsObserver? = nil
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension EnvironmentValues {
    /// The analytics observer for reactive updates
    var analyticsObserver: AnalyticsObserver? {
        get { self[AnalyticsObserverKey.self] }
        set { self[AnalyticsObserverKey.self] = newValue }
    }
}

// MARK: - View Modifiers

/// Modifier that tracks screen views automatically
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct TrackScreenModifier: ViewModifier {
    let screenName: String
    // AnalyticsProperties ([String: any Sendable]) rather than [String: AnyCodable]:
    // AnyCodable's payload is `Any`, so anything unwrapped from it is non-Sendable and
    // can't be handed to the AnalyticsService actor. `any Sendable` elements can.
    let properties: AnalyticsProperties

    func body(content: Content) -> some View {
        content
            .onAppear {
                let props = properties
                Task {
                    await AnalyticsService.shared?.trackScreen(screenName, properties: props)
                }
            }
    }
}

/// Modifier that tracks button taps
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
struct TrackTapModifier: ViewModifier {
    let buttonName: String
    let screenName: String?
    let properties: AnalyticsProperties

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    let props = properties
                    Task {
                        await AnalyticsService.shared?.trackButtonTap(
                            buttonName,
                            on: screenName,
                            properties: props
                        )
                    }
                }
            )
    }
}

// MARK: - View Extensions

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension View {

    /// Tracks when this screen appears
    ///
    /// - Parameters:
    ///   - screenName: Name of the screen
    ///   - properties: Additional properties to track
    /// - Returns: Modified view
    func trackScreen(_ screenName: String, properties: AnalyticsProperties = [:]) -> some View {
        modifier(TrackScreenModifier(screenName: screenName, properties: properties))
    }

    /// Tracks taps on this view
    ///
    /// - Parameters:
    ///   - buttonName: Name of the button/element
    ///   - screenName: Optional screen name override
    ///   - properties: Additional properties to track
    /// - Returns: Modified view
    func trackTap(_ buttonName: String, on screenName: String? = nil, properties: AnalyticsProperties = [:]) -> some View {
        modifier(TrackTapModifier(buttonName: buttonName, screenName: screenName, properties: properties))
    }

    /// Tracks a custom event when this view appears
    ///
    /// - Parameters:
    ///   - eventName: Name of the custom event
    ///   - properties: Additional properties to track
    /// - Returns: Modified view
    func trackEvent(_ eventName: String, properties: AnalyticsProperties = [:]) -> some View {
        onAppear {
            Task {
                await AnalyticsService.shared?.trackCustom(eventName, properties: properties)
            }
        }
    }

    /// Tracks a feature being used when this view appears
    ///
    /// - Parameters:
    ///   - featureName: Name of the feature
    ///   - properties: Additional properties to track
    /// - Returns: Modified view
    func trackFeature(_ featureName: String, properties: AnalyticsProperties = [:]) -> some View {
        onAppear {
            Task {
                await AnalyticsService.shared?.trackFeature(featureName, properties: properties)
            }
        }
    }

    /// Adds analytics observer to the environment
    func analytics(_ observer: AnalyticsObserver) -> some View {
        environment(\.analyticsObserver, observer)
    }
}

// MARK: - Trackable Button

/// A button that automatically tracks taps
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public struct TrackableButton<Label: View>: View {
    let buttonName: String
    let screenName: String?
    let properties: AnalyticsProperties
    let action: () -> Void
    let label: () -> Label

    public init(
        _ buttonName: String,
        on screenName: String? = nil,
        properties: AnalyticsProperties = [:],
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.buttonName = buttonName
        self.screenName = screenName
        self.properties = properties
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button {
            let props = properties
            Task {
                await AnalyticsService.shared?.trackButtonTap(
                    buttonName,
                    on: screenName,
                    properties: props
                )
            }
            action()
        } label: {
            label()
        }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension TrackableButton where Label == Text {
    /// Creates a trackable button with a text label
    init(
        _ title: String,
        buttonName: String? = nil,
        on screenName: String? = nil,
        properties: AnalyticsProperties = [:],
        action: @escaping () -> Void
    ) {
        self.buttonName = buttonName ?? title
        self.screenName = screenName
        self.properties = properties
        self.action = action
        self.label = { Text(title) }
    }
}

// MARK: - Analytics Convenience Functions

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
public extension AnalyticsService {

    /// Convenience method to track app launch
    func trackAppLaunch(source: String? = nil) async {
        var props: AnalyticsProperties = [:]
        if let source = source {
            props["launch_source"] = source
        }

        let event = AnalyticsEvent(
            sessionID: UUID(),
            anonymousID: "",
            eventType: .appLaunch,
            eventName: "app_launch",
            deviceInfo: DeviceInfoCollector.shared.deviceInfo,
            properties: [:]
        )

        await track(event)
    }

    /// Convenience method to track app background
    func trackAppBackground() async {
        await trackCustom("app_background", properties: [:])
    }

    /// Convenience method to track app terminate
    func trackAppTerminate() async {
        await trackCustom("app_terminate", properties: [:])
    }
}
