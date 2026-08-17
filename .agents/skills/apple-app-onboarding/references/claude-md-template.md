# CLAUDE.md template for new apps

Create the new repo's `CLAUDE.md` from the skeleton below. Fill every `{{...}}` and the
layering table from the onboarding interview; delete rows for targets the app doesn't have.
Keep it honest — CLAUDE.md describes what IS, not what's aspirational. Update it in the same
PR whenever a rule here changes.

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

{{APP_NAME}} — {{ONE_LINE_DESCRIPTION}} for {{PLATFORMS}}, built as a thin Xcode app shell
(`{{APP_NAME}}/`) over the `{{APP_NAME}}Kit` SwiftPM package (`Sources/`). Swift 6 language
mode, Swift Testing, SwiftUI.

## Commands

```sh
swift build                                   # build the package libraries
swift test                                    # all test suites (what CI gates on)
swift test --filter {{APP_NAME}}CoreTests     # one target
Tools/lint.sh                                 # SwiftLint + SwiftFormat, same checks as CI
Tools/lint.sh --fix                           # auto-fix what the tools can
Tools/check-docs.sh                           # public API missing /// docs (must stay green)
```

- App/extension targets build only in Xcode (scheme **{{APP_NAME}}**); `swift test` can't
  reach them. UI/runtime behavior must be verified through Xcode.
- CI: Xcode Cloud runs `ci_scripts/ci_post_clone.sh` (lint + format + `swift test`) before
  every build. Workflow payloads in `ci/`.

## Architecture — the rules that span multiple files

**Module layering (dependencies point up; violating these boundaries is the #1 review concern):**

| Target | Rule |
|---|---|
| `{{APP_NAME}}Core` | Pure Swift. No UI/platform imports. `Sendable`+`Codable` value types. |
| `{{APP_NAME}}Data` | Persistence/content over Core. No SwiftUI — extensions link it. |
| `{{APP_NAME}}Intents` | App Intents surface. Links Core + Data, **never** the UI layer. |
| `{{APP_NAME}}UI` | SwiftUI presentation. The app target is a thin shell over this. |

**App Intents are a first-class API surface, not a bolt-on.** Every user-facing feature ships
with its intents: the feature's nouns as `AppEntity` + queries (list/find), its verbs as
action intents runnable without UI, and its screens reachable via launcher intents. Intents →
app routing goes through the `LaunchInbox` mailbox in `{{APP_NAME}}Data` (an intent `set`s a
`LaunchAction`; the root view `take`s it on foreground) — don't invent new side channels. The
`AppShortcutsProvider` lives in the **app shell** (main-bundle phrase extraction), intents
stay in the package, and the app must NOT declare `AppIntentsPackage.includedPackages` for
the SPM target (breaks all shortcuts at runtime, error 9004). Full rules and gotchas:
`docs/app-intents-playbook.md`.

**Third-party SDKs stay behind protocol seams** defined in `{{APP_NAME}}Data` and are linked by
the app target ONLY — never by a target an extension embeds. Implement against the seam, not
the SDK.

**Persistence pattern:** stores are `@MainActor @Observable` classes persisting small Codable
envelopes to `UserDefaults` in the shared App Group container so extensions read the same
data. Never rename persistence keys once shipped — players' data lives there.

**Navigation has ONE funnel:** deep links (`onOpenURL`/universal links), launcher intents,
widget taps, and quick actions all parse into a `LaunchAction` and go through the
`LaunchInbox` mailbox in `{{APP_NAME}}Data`; the root view `take`s it. Don't invent side
channels. URL routes and their parsing live in the Data layer (unit-tested).

**Backend:** the app's domain is a tenant on IkigaiServer (Host-routed multi-tenant: marketing
site, AASA, push/Live Activities, CloudKit server-to-server, JSON API). The API client sits
behind a protocol seam in `{{APP_NAME}}Data`; base URL is the app's own domain. See
`docs/deep-links.md` and `docs/ikigai-server.md`.

## Gotchas that have actually bitten agents

- **Compiling requires a Mac with Xcode — check which environment you're in.** In a local
  session, always run `swift test` and `Tools/lint.sh` before committing, and build the app
  scheme when the change touches `{{APP_NAME}}/`. In a cloud/Linux session nothing here
  compiles — don't misread "can't build" as "change is broken"; verify by inspection and let
  Xcode Cloud gate the push.
- **Tests are Swift Testing (`@Suite`/`@Test`), not XCTest.** Match that style in new tests.
- **New files under `Sources/` are auto-discovered by SwiftPM.** Files under `{{APP_NAME}}/`
  (app/extension targets) must be registered in the `.xcodeproj` — don't create them from
  outside Xcode and assume they'll build.
- Platform availability is uneven by design: guard with `#if canImport(...)` + `#if os(...)`
  the way neighboring code does, and check `docs/apple-multiplatform-ci-gotchas.md` before
  fighting a platform-specific build error.
- **Never hand-edit `MARKETING_VERSION` in `project.pbxproj`.** Releases are cut with
  `Tools/tag-release.sh MAJOR.MINOR.PATCH`; Xcode Cloud stamps the version and manages build
  numbers. See `docs/release-process.md`.

## Conventions

- Doc comments are Apple-style `///` and explain *why*; each library target has a DocC catalog
  (`Sources/<Target>/<Target>.docc`) — keep the curated Topics lists in sync when adding
  public types.
- **After touching public API, run `Tools/check-docs.sh`** (toolchain-free; works in cloud
  sessions). It must stay green.
- Lint/format are CI-gated: `.swiftlint.yml` + `.swiftformat` are the law; disable a rule only
  with a written reason.
- User-facing strings are String-Catalog-backed (`Localizable.xcstrings`); don't build display
  text through concatenation that can't localize.
- Info.plist keys live in each target's Info.plist file, not `INFOPLIST_KEY_*` build settings
  (exceptions: per-configuration values, and targets with no plist file).
- Design/decision records live in `docs/`.
- **Task tracking is GitHub Issues, not a `TASKS.md` file.** Don't create one — a local task
  file duplicates Issues and drifts stale immediately (found and removed across a dozen+ repos
  in a 2026-08-12 cleanup pass). Reference issues by number when relevant.
```
