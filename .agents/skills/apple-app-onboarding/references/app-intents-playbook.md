# App Intents playbook — intents as the app's API

Studio principle: **every app is App Intents-first.** Intents are not a bolt-on Siri feature —
they're the app's API surface, consumed by Siri, Shortcuts, Spotlight, widgets, Apple
Intelligence, and future system surfaces. Every user-facing feature ships with its intents.
Copy this file into every new repo as `docs/app-intents-playbook.md`.

Proven on EmpressBlood across six phases (PRs #114–#122); the gotchas below are the ones that
actually cost time there.

## The surface every app exposes

| Kind | What | How |
|---|---|---|
| **Entities** | The app's nouns (cards, decks, documents, …) | `AppEntity` + `EntityQuery`; `defaultQuery` resolves IDs |
| **Find/list** | Enumerate and search entities | `EnumerableEntityQuery` for small sets, `EntityStringQuery`/property queries for search; cap results (~25) |
| **Actions** | The app's verbs, runnable **without UI** | `AppIntent` with `@Parameter`s; typed errors become spoken feedback |
| **Navigation** | Deep-link into a screen | Launcher intents that write a `LaunchAction` into a `LaunchInbox` mailbox; the root view consumes it on foreground |
| **Spotlight** | Entities searchable system-wide | `IndexedEntity` + one bulk index call at launch |
| **Snippets** | Visual results in Siri/Shortcuts | SwiftUI from the extension-safe UI target only |

Design intents alongside the feature, not after it: a feature isn't done until its nouns are
entities and its verbs are intents.

## Architecture prerequisites (why the layering exists)

- **The `<App>Intents` target links Core + Data, never the UI layer.** Intents must run in a
  background process with no UI; heavy frameworks (SpriteKit/Metal/store SDKs) don't belong
  and won't build for every platform the intents target does.
- **State must be reachable from outside the app process**: stores persist small Codable
  envelopes to the App Group container, so an intent invocation (its own process) reads the
  same decks/profile the app wrote.
- **Persistable value-type state is the killer feature.** A Siri conversation is a *stateless
  sequence of intent runs* — a `Codable` snapshot persisted between invocations is what makes
  multi-turn voice flows possible (EmpressBlood plays entire matches by voice this way, in
  background intent mode: AirPods, Watch, HomePod, app not even running).

## Gotchas that actually bit (in the order they bite)

1. **`AppShortcutsProvider` must live in the app's main bundle** — phrase extraction happens
   at build time from the app target. Keep the *intents* in the package; define the
   *provider* (with all its phrases) in the app shell.
2. **Do NOT declare `AppIntentsPackage.includedPackages` for an SPM static library.** It
   writes an "includes" directive into the app's App Intents metadata pointing at a
   `<Pkg>.appintents` sub-bundle that static linking never embeds into the .app. At runtime
   the aggregate metadata load fails (error **9004**, "no app shortcuts provider … in
   bundle") and **every shortcut silently vanishes**. The package's intents are already
   merged into the app's own `Metadata.appintents` — the include is redundant *and* broken.
3. **App Shortcuts are capped at 10** (each with up to ~10 phrases, every phrase containing
   `\(.applicationName)`). Curate deliberately in one file — an addition must displace
   something. Parameterized phrases (`\(\.$card)`) multiply reach without spending slots.
4. **Dynamic parameterized phrases need `updateAppShortcutParameters()`** whenever the
   backing entity data changes — and package code can't call it (the provider lives in the
   app bundle). Register a closure at launch (a one-line `ShortcutsBridge.register { ... }`
   pattern) so package-level stores can poke the app-level provider.
5. **Spotlight indexing is platform-uneven in the worst way**: `canImport(CoreSpotlight)` is
   **true on tvOS** but `IndexedEntity`/`CSSearchableItemAttributeSet` are unavailable there;
   watchOS can't import it at all. Gate with
   `#if canImport(CoreSpotlight) && !os(tvOS)` and make the bulk-index call a no-op shim
   elsewhere. Same pattern for GameKit (no watchOS) and friends.
6. **Hide internal intents.** Widget/snippet button intents that exist only as plumbing get
   `static var isDiscoverable = false` — otherwise they clutter Shortcuts and Spotlight.
7. **Navigation intents don't touch UI.** An intent process can't reach your view hierarchy;
   write a `LaunchAction` to the App Group mailbox and have the root view `take()` it on
   launch/foreground. Don't invent per-feature side channels.
8. **Snippet views come from the extension-safe UI target** (the one with no
   SpriteKit/Metal/store SDK) — the same target widgets use. If a snippet needs a view that
   lives in the heavy UI layer, move the view down, don't link the layer.
9. **`AppEnum`/`AppEntity` conformances must live in the module that declares the type.**
   Conforming a Data-layer enum to `AppEnum` from the `<App>Intents` target compiles under
   `swift build`, but the app target's `appintentsmetadataprocessor` halts with "enums
   implemented in an imported framework or library are not supported" (plus bogus-looking
   "must be static / compile-time constant" errors) — and no intent metadata ships. Put the
   conformance in the declaring module (Data importing `AppIntents` is fine — it's not UI),
   keep the *intents* in the intents target.
10. **Polish that moves the needle**: intent `title` + `IntentDescription(..., categoryName:)`
   group and describe intents in the Shortcuts app; alternative app names
   (`INAlternativeAppNames` in Info.plist) catch mispronunciations; the App Intents icon
   tint (`CFBundleIcons` ▸ `NSAppIconActionTintColorName` + complementing colors) brands the
   Siri/Shortcuts UI. All cheap, all in the plist/provider.

## Onboarding checklist

- [ ] `<App>Intents` package target (Core + Data only) with `AppIntentsPackage` conformance
- [ ] Provider in the app shell with curated ≤10 shortcuts; no `includedPackages`
- [ ] Entities + queries for the app's core nouns; find/list intents capped and fast
- [ ] Launcher intents via the `LaunchInbox` mailbox; root view consumes on foreground
- [ ] Spotlight indexing behind `canImport(CoreSpotlight) && !os(tvOS)`
- [ ] `ShortcutsBridge`-style refresh hook if any shortcut phrase is parameterized
- [ ] Snippets only from the extension-safe UI target
- [ ] Internal plumbing intents marked `isDiscoverable = false`
