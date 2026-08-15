# CloudAdminKit

Client SDK for apps managed by [CloudAdmin](https://github.com/45BitStudios/CloudAdmin): CloudKit-backed
analytics, feature flags, remote settings, feature requests, and APNs push, plus the SwiftUI layer on top.

Public, dependency-free of any other 45BitStudios repo — resolves over plain HTTPS, no repository-access
grants needed in Xcode Cloud or anywhere else.

## Products

Always depend on the granular product(s) you need, never all of them through one umbrella import —
linking only what you use keeps Info.plist purpose-string requirements (privacy manifests, APNs
entitlements, etc.) scoped to the features you actually ship.

- **`CloudAdminClient`** — Analytics, FeatureFlags, FeatureRequests, RemoteSettings services. No UI.
- **`CloudAdminClientUI`** — SwiftUI property wrappers, view modifiers, and debug views for the above.
- **`CloudAdminPush`** — APNs registration and send/update HTTP client (`CloudAdminPushClient`).
- **`CloudAdminPushUI`** — `PushRegistrationController`, an `@Observable` APNs delegate helper.

## Add the package

```swift
.package(url: "https://github.com/45BitStudios/CloudAdminKit.git", from: "1.0.0"),
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "CloudAdminClient", package: "CloudAdminKit"),
        .product(name: "CloudAdminClientUI", package: "CloudAdminKit"),
        .product(name: "CloudAdminPush", package: "CloudAdminKit"),
        .product(name: "CloudAdminPushUI", package: "CloudAdminKit"),
    ]
)
```

## Usage

Every service takes your app's own CloudKit container identifier — CloudAdminKit never assumes a
shared container.

```swift
import CloudAdminClient

AnalyticsService.configure(with: .init(containerIdentifier: "iCloud.com.yourcompany.yourapp"))
FeatureFlagService.configure(with: .init(containerIdentifier: "iCloud.com.yourcompany.yourapp"))
RemoteSettingsService.configure(with: .init(containerIdentifier: "iCloud.com.yourcompany.yourapp"))
let requests = FeatureRequestService(containerIdentifier: "iCloud.com.yourcompany.yourapp")

await AnalyticsService.shared?.trackScreen("Home")
let isOn = FeatureFlagService.shared?.isEnabled("new_paywall") ?? false
let timeout = RemoteSettingsService.shared?.double(for: "apiTimeout", default: 30) ?? 30
let submitted = try await requests.submit(FeatureRequest(title: "Dark mode", description: "…"))
```

```swift
import CloudAdminClientUI

struct PaywallView: View {
    @FeatureEnabled("new_paywall") var showsNewPaywall
    @RemoteDoubleSetting("apiTimeout", default: 30) var apiTimeout

    var body: some View {
        Text(showsNewPaywall ? "New paywall" : "Old paywall")
            .trackScreen("Paywall")
    }
}
```

Debug views (drop into a settings screen during development):

```swift
NavigationStack { AnalyticsDebugView() }
NavigationStack { FeatureFlagDebugView() }
NavigationStack { RemoteSettingsDebugView() }
```

Push registration:

```swift
import CloudAdminPush
import CloudAdminPushUI

let push = CloudAdminPushClient(
    baseURL: URL(string: "https://your-cloudadmin-server")!,
    appId: "yourapp",
    apiKey: ProcessInfo.processInfo.environment["CLOUDADMIN_API_KEY"] ?? "",
    deviceId: Keychain.deviceId
)

await PushRegistrationController.shared.requestAuthorization()
PushRegistrationController.shared.registerForRemoteNotifications()
// In your AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken:
try await push.registerDevice(token: deviceToken)
```

## Documentation

Generate DocC locally:

```swift
swift package generate-documentation --target CloudAdminClient
```

## Contributing / AI agents

See [AGENTS.md](AGENTS.md) for the integration walkthrough — it's what Claude Code, Cursor, and
Codex read when asked to add this package to an app.

## License

MIT — see [LICENSE](LICENSE).
