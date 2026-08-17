// canImport(UIKit) is true on tvOS and watchOS, but the notification-presentation APIs used
// below (UNNotificationPresentationOptions.banner/.list, UNNotificationResponse handling) are
// unavailable on tvOS, and UIApplication/UIApplicationDelegate are unavailable on watchOS —
// exclude both (docs/apple-multiplatform-ci-gotchas.md §3).
#if canImport(UIKit) && !os(tvOS) && !os(watchOS)
import Foundation
import UIKit
import UserNotifications

/// A drop-in application delegate that wires up remote-notification registration and
/// notification handling, then forwards everything to ``PushRegistrationController/shared``.
///
/// Adopt it from a SwiftUI `App` with a single line — no `AppDelegate` boilerplate, and
/// nothing app-specific baked in, so it is reusable across apps:
///
/// ```swift
/// import CloudAdminPushUI
///
/// @main
/// struct MyApp: App {
///     #if os(iOS)
///     @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
///     #endif
///     var body: some Scene {
///         WindowGroup {
///             RootView()
///                 .environment(PushRegistrationController.shared)
///         }
///     }
/// }
/// ```
///
/// It registers for remote notifications unconditionally in `didFinishLaunching` (the
/// device/Live-Activity token flows regardless of alert authorization) and sets itself as
/// the `UNUserNotificationCenter` delegate there too, so a cold-launch notification tap is
/// not missed. Requesting user-visible alert authorization is left to the app, via
/// ``PushRegistrationController/requestAuthorization(options:)``.
@MainActor
public final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Sets the notification-center delegate and kicks off remote-notification registration.
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    /// Forwards the freshly minted APNs token to the shared controller.
    public func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrationController.shared.didRegister(token: deviceToken)
    }

    /// Records a registration failure for display/diagnostics.
    public func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        PushRegistrationController.shared.didFailToRegister(error: error)
    }

    /// Shows alerts even while the app is foregrounded.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    /// Forwards a notification tap (including cold-launch) to the shared controller.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        PushRegistrationController.shared.didReceive(response: response)
    }
}
#endif
