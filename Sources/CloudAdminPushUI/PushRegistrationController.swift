//
//  PushRegistrationController.swift
//  CloudAdminPushUI
//
//  Observable, transport-agnostic push registration state for SwiftUI.
//  Upstreamed from CloudAdmin's PushRegistrationController.
//

// canImport(UIKit) is true on tvOS, but the alert/sound authorization options and
// notification-response handling used here are unavailable there — exclude tvOS.
// ua-debt: duplicated from Ikigai's Sources/IkigaiCore/PushNotifications/PushRegistrationController.swift
// to avoid a circular package dependency (CloudAdminKit needs this type; Ikigai depends on
// CloudAdminKit for the converged Analytics/FeatureFlags/FeatureRequests/RemoteSettings —
// CloudAdminKit -> Ikigai -> CloudAdminKit is rejected by SwiftPM). Upgrade path: drop this
// file and depend on Ikigai's copy directly if Ikigai ever splits PushRegistrationController
// into its own zero-dependency package that both repos can depend on as a leaf.
#if !os(tvOS) && !os(watchOS)
import Foundation
import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Observable bridge between the app delegate and SwiftUI for push registration state.
///
/// An app delegate created by `@UIApplicationDelegateAdaptor` is owned by the framework and
/// awkward to read from views, so the shared `PushAppDelegate` (in `CloudAdminClientUI`) writes
/// every push event into this `@MainActor` `@Observable` object. Views observe it directly;
/// app-specific glue can
/// set ``onDeviceToken`` to forward the token somewhere custom (the built-in forwarding to
/// `PushNotificationService` / `IkigaiPushRegistrar` happens regardless).
///
/// This type is intentionally **transport-agnostic** — it knows nothing about IkigaiServer,
/// APNs auth, or any specific backend.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@MainActor
@Observable
public final class PushRegistrationController {
    /// The most recent raw APNs device token, or `nil` before registration completes.
    public private(set) var deviceToken: Data?

    /// Hex encoding of ``deviceToken`` — the form servers and dashboards display.
    public private(set) var deviceTokenHex: String?

    /// The user's current notification authorization status.
    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The last registration failure message, if remote-notification registration failed.
    public private(set) var lastRegistrationError: String?

    /// Invoked on the main actor whenever a fresh device token arrives (first registration
    /// and every APNs rotation). Set this to forward the token to a custom backend.
    public var onDeviceToken: ((Data) -> Void)?

    /// Invoked when the user taps a delivered notification, including a cold-launch tap.
    public var onNotificationResponse: ((UNNotificationResponse) -> Void)?

    /// The process-wide instance the delegate reports into and views read from.
    public static let shared = PushRegistrationController()

    /// Creates a controller. Prefer ``shared`` in app code; the initializer is public only
    /// so tests can make isolated instances.
    public init() {}

    // MARK: - Authorization

    /// Requests user-notification authorization and refreshes ``authorizationStatus``.
    ///
    /// Not required for silent or Live Activity pushes (those flow to the device token
    /// regardless) — call it only when you want user-visible alerts.
    ///
    /// - Returns: `true` if the user granted the requested options.
    @discardableResult
    public func requestAuthorization(
        options: UNAuthorizationOptions = [.alert, .badge, .sound]
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: options)) ?? false
        authorizationStatus = await center.notificationSettings().authorizationStatus
        return granted
    }

    /// Registers with APNs for a device token. Safe to call on every launch; the token
    /// arrives via the app delegate into ``onDeviceToken``.
    public func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif canImport(AppKit)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    // MARK: - Delegate callbacks (called by AppDelegate)

    public func didRegister(token: Data) {
        deviceToken = token
        deviceTokenHex = token.map { String(format: "%02x", $0) }.joined()
        lastRegistrationError = nil
        onDeviceToken?(token)
    }

    public func didFailToRegister(error: any Error) {
        lastRegistrationError = error.localizedDescription
    }

    public func didReceive(response: UNNotificationResponse) {
        onNotificationResponse?(response)
    }
}
#endif
