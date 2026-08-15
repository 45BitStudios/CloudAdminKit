# AGENTS.md — integrating CloudAdminKit

This is the canonical guide for any coding agent (Claude Code, Cursor, Codex, or otherwise)
asked to add CloudAdminKit to an app. Claude Code's `SKILL.md` and any editor-specific rule
files just point here — this is the one copy that gets kept up to date.

## 1. Add the dependency

CloudAdminKit is a **public** repo. It resolves over plain HTTPS with no credentials, no SSH
key, and no Xcode Cloud "Repository access" grant to configure.

```swift
.package(url: "https://github.com/45BitStudios/CloudAdminKit.git", from: "1.0.0"),
```

## 2. Pick granular products only — never a combined aggregate

Depend on exactly the products you use:

- `CloudAdminClient` — Analytics, FeatureFlags, FeatureRequests, RemoteSettings (no UI)
- `CloudAdminClientUI` — SwiftUI property wrappers, modifiers, debug views for the above
- `CloudAdminPush` — APNs registration/send HTTP client
- `CloudAdminPushUI` — `PushRegistrationController`, an `@Observable` APNs delegate helper
- `CloudAdminModels` — shared model types (usually pulled in transitively; rarely a direct dependency)

Do not create or depend on a single umbrella product that re-exports all of the above. Linking
an aggregate you don't fully use is what triggered App Store Connect's **ITMS-90683** privacy
purpose-string rejection on a prior app in this studio — the binary carried entitlement/API
surface (push, location-adjacent device info in analytics) for subsystems the app never
actually called. Link only the products you use; the purpose strings you declare should match
the code you linked.

## 3. Configure the CloudKit container

Every service takes your app's own container identifier — never hardcode a shared one:

```swift
AnalyticsService.configure(with: .init(containerIdentifier: "iCloud.com.yourcompany.yourapp"))
FeatureFlagService.configure(with: .init(containerIdentifier: "iCloud.com.yourcompany.yourapp"))
RemoteSettingsService.configure(with: .init(containerIdentifier: "iCloud.com.yourcompany.yourapp"))
let requests = FeatureRequestService(containerIdentifier: "iCloud.com.yourcompany.yourapp")
```

## 4. Starter snippets

**Push** — register a device and send:

```swift
import CloudAdminPush
import CloudAdminPushUI

let push = CloudAdminPushClient(
    baseURL: URL(string: "https://your-cloudadmin-server")!,
    appId: "yourapp",
    apiKey: yourApiKey,
    deviceId: yourStableDeviceId
)

await PushRegistrationController.shared.requestAuthorization()
PushRegistrationController.shared.registerForRemoteNotifications()
// AppDelegate: didRegisterForRemoteNotificationsWithDeviceToken
try await push.registerDevice(token: deviceToken)
```

**Analytics** — track events:

```swift
await AnalyticsService.shared?.trackScreen("Home")
await AnalyticsService.shared?.trackCustom("purchase_completed", properties: ["sku": "pro_annual"])
```

**Feature flags** — read or gate a view:

```swift
let isOn = FeatureFlagService.shared?.isEnabled("new_paywall") ?? false
```

```swift
struct PaywallView: View {
    @FeatureEnabled("new_paywall") var showsNewPaywall
    var body: some View { /* ... */ }
}
```

**Remote settings**:

```swift
@RemoteDoubleSetting("apiTimeout", default: 30) var apiTimeout
```

**Feature requests** — let users submit:

```swift
let submitted = try await requests.submit(FeatureRequest(title: "Dark mode", description: "…"))
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
