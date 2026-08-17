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

## Import the CloudKit schema (required before first run)

CloudAdminKit reads and writes record types that must already exist in **your app's** container.
Import `Schema/client-schema.ckdb` from this repo in CloudKit Console:

1. Open your container → **Development** → **Schema** → **Import Schema**
2. Choose `Schema/client-schema.ckdb`
3. Deploy the schema to **Production** before shipping

Until the schema is imported, fetches return empty and saves fail. Do not invent extra fields —
the shipped `.ckdb` is the contract.

## Usage

Every service takes your app's own CloudKit container identifier — CloudAdminKit never assumes a
shared container. Feature flags and remote settings stay at their configure-time defaults until
you call `fetchFlags()` / `fetchSettings()` (or `initialize()`). The services are actors, so
reads are `await`.

```swift
import CloudAdminClient

let container = "iCloud.com.yourcompany.yourapp"

AnalyticsService.configure(with: .init(containerIdentifier: container))
FeatureFlagService.configure(with: .init(containerIdentifier: container))
RemoteSettingsService.configure(with: .init(containerIdentifier: container))
let requests = FeatureRequestService(containerIdentifier: container)

try? await FeatureFlagService.shared?.fetchFlags()
try? await RemoteSettingsService.shared?.fetchSettings()

await AnalyticsService.shared?.trackScreen("Home")
let isOn = await FeatureFlagService.shared?.isEnabled("new_paywall") ?? false
let timeout = await RemoteSettingsService.shared?.double(for: "apiTimeout", default: 30) ?? 30
let submitted = try await requests.submit(FeatureRequest(title: "Dark mode", description: "Please add a dark theme."))
```

SwiftUI wrappers need an observer in the environment so views update after a refresh. Put the
observers on your `App` (or a root view) — the wrappers read the configured services even
without them, but they will not redraw when CloudKit values change.

```swift
import CloudAdminClient
import CloudAdminClientUI
import SwiftUI

@main
struct MyApp: App {
    @State private var flags = FeatureFlagObserver()
    @State private var settings = RemoteSettingsObserver()

    var body: some Scene {
        WindowGroup {
            PaywallView()
                .featureFlags(flags)
                .remoteSettings(settings)
                .task {
                    await flags.startObserving()
                    await settings.startObserving()
                }
        }
    }
}

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

Push registration — persist your own stable `deviceId` string (UserDefaults, Keychain, or a
file). Wire `PushRegistrationController.onDeviceToken` to the HTTP client so APNs rotations
re-register automatically:

```swift
import CloudAdminPush
import CloudAdminPushUI

let deviceId = UserDefaults.standard.string(forKey: "deviceId") ?? {
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: "deviceId")
    return id
}()

let push = CloudAdminPushClient(
    baseURL: URL(string: "https://your-cloudadmin-server")!,
    appId: "yourapp",
    apiKey: ProcessInfo.processInfo.environment["CLOUDADMIN_API_KEY"] ?? "",
    deviceId: deviceId
)

PushRegistrationController.shared.onDeviceToken = { token in
    Task { try? await push.registerDevice(token: token) }
}
await PushRegistrationController.shared.requestAuthorization()
PushRegistrationController.shared.registerForRemoteNotifications()
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
