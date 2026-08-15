# Integrating the Cloud Admin client SDK

Wire a managed app to the feature flags, remote settings, analytics, and feature requests you
control from the Cloud Admin app.

## Overview

This guide is for a **managed app** (e.g. EmpressBlood) that wants its feature flags, remote
settings, analytics, and feature requests controlled from Cloud Admin. It talks to the app's
**own CloudKit container** — no admin credentials ship in the client.

### What you link

Two products from `CloudAdminKit`:

| Product | Use | Imports |
|---|---|---|
| ``CloudAdminClient`` | Models + services (flags, settings, analytics, feature requests) | Foundation, CloudKit, Observation — **no SwiftUI** |
| `CloudAdminClientUI` | `@FeatureEnabled` / `@Remote*Setting` property wrappers + analytics view modifiers | SwiftUI |

**The SDK is UI-agnostic** — it renders none of your chrome. `CloudAdminClientUI` only adds
property wrappers (which return *values*) and tracking modifiers (invisible side effects). Apps
with heavily custom UIs typically link **only ``CloudAdminClient``** and read values through their
own app model. Link `CloudAdminClientUI` only if you want the property-wrapper ergonomics in a
view.

## 1. Add the dependency

Track the `main` branch during rapid development (pin to a tag once it stabilizes):

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/45BitStudios/CloudAdminKit.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourAppKit", dependencies: [
        .product(name: "CloudAdminClient", package: "CloudAdminKit"),
        // .product(name: "CloudAdminClientUI", package: "CloudAdminKit"),  // only if using wrappers
    ]),
]
```

The `package:` label is the dependency's **identity** (`CloudAdminKit`, the repo/dir name), which
matches the manifest name here. SPM pulls in only the products you list — CloudAdminKit's push
targets (`CloudAdminPush`/`CloudAdminPushUI`) never compile into your app unless you list them
too. Run `swift package update CloudAdminKit` (or Xcode → Packages → Update) to pull newer
versions.

**Requirements:** the app must own a CloudKit container (`iCloud.<bundle-id>` in its
entitlements), on the same Apple Developer team you administer from Cloud Admin.

## 2. Import the schema (one-time, per container)

The record types + indexes must exist in the container or reads come back empty. Import
`Schema/client-schema.ckdb` from this repo into your container's CloudKit Console
(**your container → Development → Schema → Import Schema**), then deploy to Production before
shipping.

## 3. Configure at launch

All three services are **actors** with a `@MainActor` `configure(with:)` that sets a shared
instance. Configure once, early (app `init()` or your app-model `init`):

```swift
import CloudAdminClient

let container = "iCloud.com.yourcompany.yourapp"

FeatureFlagService.configure(with: FeatureFlagConfiguration(
    containerIdentifier: container,
    usePublicDatabase: true,
    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
    defaultFlags: ["someFlag": false]     // offline / pre-fetch fallbacks
))

RemoteSettingsService.configure(with: RemoteSettingsConfiguration(
    containerIdentifier: container,
    usePublicDatabase: true,
    defaults: ["supportEmail": .string("help@yourapp.com")]
))

// Analytics defaults to the PRIVATE database (privacy-correct). See the caveat below.
AnalyticsService.configure(with: AnalyticsConfiguration(containerIdentifier: container))
```

## 4. Consume the values

### Feature flags

Because the service is an actor, `isEnabled(_:)` is `async`. Two patterns:

**A. Snapshot into your `@Observable` model (recommended for custom-UI apps).** Fetch, then
mirror the flags your UI reads into an observable property so views read synchronously:

```swift
@MainActor @Observable final class AppModel {
    private let flags = FeatureFlagService.shared!
    private(set) var enabledFlags: [String: Bool] = [:]

    func refreshRemoteConfig() async {
        try? await flags.fetchFlags()
        enabledFlags["seasonalArena"] = await flags.isEnabled("seasonalArena")
    }
    func isFeatureEnabled(_ key: String, default d: Bool = false) -> Bool {
        enabledFlags[key] ?? d
    }
}
```
```swift
if app.isFeatureEnabled("seasonalArena", default: true) {
    SeasonalArenaTile()      // your component, your styling
}
```

**B. Property wrapper (view-local, needs `CloudAdminClientUI`).** For a leaf SwiftUI view:

```swift
import CloudAdminClientUI
struct MyView: View {
    @FeatureEnabled("seasonalArena") private var isOn
    var body: some View { if isOn { /* … */ } }
}
```

Always pass a sensible **default** — flags resolve to defaults offline and before the first fetch,
so the app never breaks waiting on CloudKit. Gating an existing element? Default it to *shown* so
setting the flag off is a remote kill-switch, not a surprise removal.

### Remote settings

Typed key/value, actor-isolated (async), same snapshot-or-wrapper choice as flags:

```swift
let email = await RemoteSettingsService.shared?.string(for: "supportEmail", default: "help@app.com")
// or, view-local: @RemoteStringSetting("supportEmail", default: "help@app.com") var email
```

### Analytics (note the database)

```swift
await AnalyticsService.shared?.trackScreen("Home")
await AnalyticsService.shared?.trackFeature("startedDuel")
```

**Visibility caveat:** analytics default to the **private** database, which is correct for user
privacy but means Cloud Admin's dashboard (which reads the public DB) won't see them. To make
events admin-visible, configure `usePrivateDatabase: false` — but then every user's events are
world-readable in the public container. Choose deliberately; for many apps, private + a future
aggregation record is the right call.

### Feature requests

```swift
let service = FeatureRequestService(containerIdentifier: container, usePublicDatabase: true)
_ = try await service.submit(FeatureRequest(title: "Dark mode", description: "Please!"))
let top = try await service.fetchAll(includePrivate: true).sorted { $0.votes > $1.votes }
```

## 5. Refresh

Call your `refreshRemoteConfig()` on launch and on foreground so admin changes land without a
relaunch. (Flags/settings also support CloudKit subscriptions via `enableSubscriptions`.)

## Worked example: EmpressBlood

- `Package.swift` — the git dependency above + `CloudAdminClient` on the `GameUI` target.
- `Sources/GameUI/AppModel.swift` — configures `FeatureFlagService`/`RemoteSettingsService` in
  `init()`, exposes `enabledFlags` + `isFeatureEnabled(_:default:)`, refreshes via
  `refreshRemoteConfig()` (kicked off from `init`).
- `Sources/GameUI/MenuScreens.swift` — the Home "Music" tile is gated behind
  `isFeatureEnabled("musicRoom", default: true)`: a remote kill-switch that changes nothing until
  the flag is set to off in Cloud Admin. None of the custom `Theme`/ShaderKit UI was touched.
