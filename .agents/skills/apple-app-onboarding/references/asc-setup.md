# App Store Connect setup with the `asc` CLI

The exact sequence to take a new app from "repo exists" to "both Xcode Cloud workflows live."
Commands match the asc CLI usage proven on EmpressBlood; if a subcommand differs on the
installed version, check `asc --help` / `asc xcode-cloud --help` rather than guessing flags.
Authentication (ASC API key) is assumed to be configured already.

## 1. Register bundle IDs — the app AND every embedded target

Xcode Cloud's automatic signing can create *profiles* but **cannot register new App IDs**. Any
extension/watch target whose bundle ID isn't registered fails the archive export with
`Automatic signing cannot register bundle identifier ...` + `No profiles for '...' were found`.

Naming convention (children are suffixes of the app ID; the watch app uses `.watchkitapp`):

```sh
asc bundle-ids create --identifier {{BUNDLE_ID}}                        --name "{{APP_NAME}}"                --platform IOS
asc bundle-ids create --identifier {{BUNDLE_ID}}.Widget                 --name "{{APP_NAME}} Widget"         --platform IOS
asc bundle-ids create --identifier {{BUNDLE_ID}}.Message                --name "{{APP_NAME}} Message"        --platform IOS
asc bundle-ids create --identifier {{BUNDLE_ID}}.NotificationService   --name "{{APP_NAME}} NotifService"   --platform IOS
asc bundle-ids create --identifier {{BUNDLE_ID}}.NotificationContent   --name "{{APP_NAME}} NotifContent"   --platform IOS
asc bundle-ids create --identifier {{BUNDLE_ID}}.watchkitapp            --name "{{APP_NAME}} Watch"          --platform IOS
asc bundle-ids create --identifier {{BUNDLE_ID}}.watchkitapp.WatchWidget --name "{{APP_NAME}} Watch Widget"  --platform IOS
```

Only create the ones for targets that actually exist. `--platform IOS` normalizes to UNIVERSAL.

**"An App ID with Identifier '…' is not available" means ALREADY REGISTERED — not reserved by
Apple.** Usually your own, auto-created by an earlier Xcode build (`XC com example app`). Two
traps make this hard to see:

- **Bundle IDs are case-insensitive to Apple.** `com.x.EV`, `com.x.ev`, and `com.x.Ev` are one
  identifier. A *removed* app record still squats its bundle ID permanently, so an abandoned
  app can block the name years later.
- **A case-sensitive grep will miss it and send you chasing the wrong cause.** Always search
  `--limit 200` and lowercase both sides:
  ```sh
  asc bundle-ids list --limit 200 | python3 -c "
  import sys,json
  for x in json.load(sys.stdin)['data']:
      a=x['attributes']
      if 'myapp' in a['identifier'].lower(): print(x['id'], a['identifier'], a['name'])
  "
  ```

Check the child IDs against the **actual** `PRODUCT_BUNDLE_IDENTIFIER` values in the pbxproj
before creating them — Xcode names a widget target's ID after the target
(`com.x.App.AppWidget`), which is not the `.Widget` this doc's convention suggests. A child ID
that doesn't match the target signs nothing. And bundle IDs cannot be deleted once created, so
a guessed-wrong ID is permanent litter: read the pbxproj first, create second.

**Exception — do NOT pre-register the App Clip ID (`{{BUNDLE_ID}}.Clip`).** The public API
cannot set the App Clip capability (`ON_DEMAND_INSTALL_CAPABLE` is not a valid
`bundleIdCapabilities` type), and a pre-registered Clip ID *without* it actively blocks local
automatic signing: Xcode tries to register the ID itself, hits "cannot be registered … because
it is not available" (it exists), and the profile then lacks the App Clip +
`parent-application-identifiers` entitlements. Delete any such ID and let a local
`xcodebuild -allowProvisioningUpdates` build register it with the proper App Clip
configuration. (Xcode *Cloud* still can't register IDs — the local build must happen first.)

Then enable capabilities to **match each target's entitlements** (App Groups, iCloud, Game
Center, Push, **Associated Domains** for universal links/App Clips — see `deep-links.md`, …)
— a registered ID without the right capabilities still fails signing. Do this
via `asc bundle-ids` capability subcommands if available, else the developer portal.
`ICLOUD` requires the CloudKit version setting inline or the create is rejected
("CloudkitVersion 'null'"):

```sh
asc bundle-ids capabilities add --bundle <ID> --capability ICLOUD \
  --settings '[{"key":"ICLOUD_VERSION","options":[{"key":"XCODE_6","enabled":true}]}]'
```

App Group / iCloud container identifiers (`group.{{BUNDLE_ID}}`, `iCloud.{{BUNDLE_ID}}`) are
separate registrations — create them too if the app uses extensions-shared storage or KVS sync.

## 2. Create the app record

Current asc path: `asc web apps create --name … --bundle-id … --sku … --primary-locale en-US`.
This uses a **web session**, not the API key — but an agent can run it whenever the machine
already has a cached session (`--apple-id` is only needed to log in fresh). Check first rather
than assuming it's manual: if `asc web removed-apps list` returns data, the session is live and
`apps create` will work. Otherwise: App Store Connect → My Apps → **+** → New App (one minute,
manual). The record must exist before TestFlight uploads land anywhere.

Ask the user for the **name** and **SKU** before creating — the App Store name is globally
unique, and a wrong record is not cleanly reversible: a *removed* app record still squats its
bundle identifier forever (see the `.ev` case below).

- **Name collisions:** if the App Store name is taken, `asc web apps create` retries as
  `"<Name> - <Name>"` and succeeds. That placeholder name must be fixed in ASC metadata before
  submission — flag it.

- **A bare 409 usually means the BUNDLE ID, not the name.** `com.45bitstudios.Contacts` returns
  `web api error (status 409)` with no message, no matter what `--name` is — Apple appears to
  reserve identifiers matching its own first-party apps. Renaming to `com.45bitstudios.contactshub`
  worked immediately. **Diagnose by bisecting the constants, not by re-guessing the name:** if two
  different names both 409, the name is not the variable. Rule out a real collision first —
  `asc apps list` (no record with that bundle ID?) and `asc web removed-apps list` (a removed app
  can squat a name or SKU) — then change the bundle ID. If the CLI's 409 stays opaque, create the
  app in the ASC web UI: it takes a minute and it *shows Apple's actual validation message*, which
  is worth more than another blind CLI attempt.
- **`--name` is reused for the bundle-ID preflight**, and the Developer portal only allows
  alphanumerics and spaces in a Bundle ID *name*. An App Store name containing punctuation (an
  em dash, `:`) fails with `bundle id preflight failed: … The attribute 'name' is invalid` — which
  looks like the app name was rejected, but wasn't. Pre-register the bundle ID with a clean ASCII
  name (`asc bundle-ids create --identifier … --name "Contacts"`), then `asc web apps create`
  finds it, skips preflight, and accepts the punctuated App Store name.
- **`asc web apps create` needs an interactive password prompt.** It cannot run from a
  non-interactive agent shell (`Error: password is required`) — hand this command to the user.
  Everything else here works off the API key.
- **Treat the created record as the source of truth**, not what you asked for: re-read
  `asc apps list` afterwards. Name and SKU can differ from the flags (auto-rename, manual UI
  creation) and the real values must land in CLAUDE.md.
- **Wait for propagation before doing anything that references the record** (a few minutes):
  `asc apps view --id <appId>` must resolve. Enrolling Xcode Cloud against an
  un-propagated record creates a broken product (gotchas §14).

## 3. Enroll in Xcode Cloud — manual, once per app

**Order matters: create the app record first and wait until it propagates** (`asc apps view`
resolves) — enrolling too early yields a ciProduct with a dangling app link that blocks all
archive/TestFlight configuration and can't be repaired via API (gotchas §14). If re-enrolling
after deleting a product, also `git rm` the old `xcshareddata/xcodecloud/` manifest and quit
Xcode first, or the Get Started flow fails with "Failed to create workflow".

An API key alone **cannot create the Xcode Cloud product**. In Xcode, on the Mac, with the
project open: Report Navigator → Cloud tab → **Get Started** → grant Apple ID access and
connect the GitHub repo. Let it create its default workflow; it gets replaced next
(`asc xcode-cloud workflows delete --id <id> --confirm`).

If the "Connect Source Code Repository" step lists public *transitive* package dependencies
as "Not connected" and disables Next, don't fight it — temporarily comment those dependencies
out of `Package.swift`, enroll, restore. Full recipe:
`apple-multiplatform-ci-gotchas.md` §9.

## 4. Create the workflows from the repo's JSON payloads

Fill the placeholders in `ci/workflow-ci.json` and `ci/workflow-testflight.json`:

```sh
asc xcode-cloud products list --app <appId>   # → {{PRODUCT_ID}} (the ciProducts id for this app)
# If the listing lags or comes back empty: the ID is also in the committed enrollment
# manifest — <App>.xcodeproj/xcshareddata/xcodecloud/manifest.json, targets[].id.
asc xcode-cloud xcode-versions    # → {{XCODE_VERSION_ID}} — use the "Latest Beta or Release"
                                  #   alias id; it works for BOTH the ciXcodeVersions and
                                  #   ciMacOsVersions relationships
# repository id: asc xcode-cloud products relationships, or the scmRepositories listing
```

Then:

```sh
asc xcode-cloud workflows create --file ci/workflow-ci.json
asc xcode-cloud workflows create --file ci/workflow-testflight.json
```

Rules that bite (proven on EmpressBlood):

- `workflows update` requires `data.id` in the body and **rejects** the `product`/`repository`
  relationships (they're create-only) — strip them before updating.
- The JSON files in `ci/` are reference exports / creation payloads, **not** live config. After
  any hand-edit in the ASC UI, re-export so the repo stays truthful.
- A TEST action needs `testConfiguration.testDestinations` (valid IDs come from the Xcode
  version's `testDestinations`). This template avoids TEST actions entirely — tests run in
  `ci_post_clone.sh` — so you only need this if you add native test tiles later.
- API-triggered runs count as "manual": keep `manualBranchStartCondition` /
  `manualTagStartCondition` in the payloads so `asc xcode-cloud run --branch ...` works.
- If any deployment target needs a beta-only SDK, you **cannot** pin a release Xcode — stay on
  "Latest Beta or Release" until those OSes are GA (App Store *release* submission rejects
  beta-Xcode binaries; TestFlight doesn't).

## 5. Manual toggles — once, in the ASC UI

- TestFlight workflow → Start Conditions/Versioning → enable **"Xcode Cloud automatically
  manages build number"** (keeps `CURRENT_PROJECT_VERSION` monotonic; nothing in the repo
  manages build numbers).
- Add internal testers to the TestFlight internal group if this is the first app on the team
  they're testing.

## 6. Smoke-test the pipeline

```sh
asc xcode-cloud run --workflow <CI-workflow-id> --branch main   # or open a trivial PR
```

First build ~15–20 min (fresh VM), later ones ~5–8. Then cut `Tools/tag-release.sh 0.1.0` and
confirm the TestFlight workflow fires on the tag, stamps the version, and uploads all platforms.
ITMS validation errors (icons, plist keys, platform filters) only surface on a real upload —
expect the first tag to shake one or two out; fixes are catalogued in
`docs/apple-multiplatform-ci-gotchas.md` §5–§7.
