# AGENTS.md — integrating CloudAdminKit

This is the canonical guide for any coding agent (Claude Code, Cursor, Codex, or otherwise)
asked to add CloudAdminKit to an app. Claude Code's `SKILL.md` and any editor-specific rule
files just point here — this is the one copy that gets kept up to date.

## 1. Add the dependency

CloudAdminKit is a **public** repo. It resolves over plain HTTPS with no credentials, no SSH
key, and no Xcode Cloud "Repository access" grant to configure.

```swift
.package(url: "https://github.com/45BitStudios/CloudAdminKit.git", branch: "main"),
```

## 2. Pick granular products only — never a combined aggregate

Depend on exactly the products you use. `Package.swift` ships four libraries:

- `CloudAdminClient` — Analytics, FeatureFlags, FeatureRequests, RemoteSettings (no UI)
- `CloudAdminClientUI` — SwiftUI property wrappers, modifiers, debug views for the above
- `CloudAdminPush` — APNs registration/send HTTP client
- `CloudAdminPushUI` — `PushRegistrationController` and `PushAppDelegate`, an `@Observable` APNs helper

Do not create or depend on a single umbrella product that re-exports all of the above. Linking
an aggregate you don't fully use is what triggered App Store Connect's **ITMS-90683** privacy
purpose-string rejection on a prior app in this studio — the binary carried entitlement/API
surface (push, location-adjacent device info in analytics) for subsystems the app never
actually called. Link only the products you use; the purpose strings you declare should match
the code you linked.

## 3. Configure the CloudKit container

Every service takes your app's own container identifier — never hardcode a shared one.
Import `Schema/client-schema.ckdb` into that container (Development, then deploy to
Production) before first run. After `configure`, call `fetchFlags()` / `fetchSettings()`
(or `initialize()`). Values stay at the configure-time defaults until that fetch returns.
The services are actors, so reads are `await`.

```swift
import CloudAdminClient

let container = "iCloud.com.yourcompany.yourapp"
AnalyticsService.configure(with: .init(containerIdentifier: container))
FeatureFlagService.configure(with: .init(containerIdentifier: container))
RemoteSettingsService.configure(with: .init(containerIdentifier: container))
let requests = FeatureRequestService(containerIdentifier: container)

try? await FeatureFlagService.shared?.fetchFlags()
try? await RemoteSettingsService.shared?.fetchSettings()
```

## 4. Starter snippets

**Push** — register a device and send. Persist your own stable `String` device id; wire
`PushRegistrationController.onDeviceToken` so token rotations re-register:

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

// Or, in a SwiftUI App (CloudAdminPushUI — never CloudAdminClientUI):
//   import CloudAdminPushUI
//   @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
```

**Analytics** — track events:

```swift
await AnalyticsService.shared?.trackScreen("Home")
await AnalyticsService.shared?.trackCustom("purchase_completed", properties: ["sku": "pro_annual"])
```

**Feature flags** — read or gate a view. Install `FeatureFlagObserver` in the environment
so `@FeatureEnabled` redraws after a refresh:

```swift
try? await FeatureFlagService.shared?.fetchFlags()
let isOn = await FeatureFlagService.shared?.isEnabled("new_paywall") ?? false
```

```swift
import CloudAdminClientUI
import SwiftUI

struct PaywallView: View {
    @Environment(\.featureFlagObserver) private var flags
    @FeatureEnabled("new_paywall") var showsNewPaywall
    var body: some View {
        Text(showsNewPaywall ? "New paywall" : "Old paywall")
    }
}

// On the App / root view:
//   .featureFlags(FeatureFlagObserver())
//   .task { await flags.startObserving() }
```

**Remote settings** — same observer pattern as flags:

```swift
try? await RemoteSettingsService.shared?.fetchSettings()
let timeout = await RemoteSettingsService.shared?.double(for: "apiTimeout", default: 30) ?? 30
```

```swift
import CloudAdminClientUI
import SwiftUI

struct TimeoutLabel: View {
    @Environment(\.remoteSettingsObserver) private var settings
    @RemoteDoubleSetting("apiTimeout", default: 30) var apiTimeout
    var body: some View { Text("\(apiTimeout)") }
}

// On the App / root view:
//   .remoteSettings(RemoteSettingsObserver())
//   .task { await settings.startObserving() }
```

**Feature requests** — let users submit:

```swift
let submitted = try await requests.submit(FeatureRequest(title: "Dark mode", description: "Please add a dark theme."))
```

## 5. SwiftPM cache gotcha

If dependency resolution looks stale right after adding or bumping CloudAdminKit (a product
that should exist reports as missing, or an old version keeps resolving), SwiftPM's cache is
layered three deep and all three layers can hold stale state: the project's local
`.build`/`.swiftpm`, Xcode's per-user DerivedData package cache, and `~/Library/Caches/org.swift.swiftpm`.
Clearing only one layer often looks like it worked and then regresses — clear all three before
concluding something is actually broken.

## 6. Verifying the integration

After adding the dependency, `swift build` (or an Xcode build) should succeed with no
"repository access" prompt and no purpose-string warnings beyond what the products you linked
actually require. That's the signal the integration is correct.
