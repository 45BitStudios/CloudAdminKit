# Deep links — universal links, custom scheme, one routing funnel

Every app gets a URL space from day one: its own domain (served by IkigaiServer — see
`ikigai-server.md`) for universal links, plus a custom scheme fallback. Retrofitting URL
routing after screens exist is far more painful than declaring it up front.

## Decide the URL space (Phase 0 interview)

- **Domain**: `<app>.example` or a subdomain — this is the app's IkigaiServer tenant domain.
  Universal links, the marketing site, and the JSON API all share it.
- **Custom scheme**: `<appname>://` — fallback for contexts where universal links don't fire
  (some in-app browsers, QR tools) and for dev/testing. Register under `CFBundleURLTypes`
  in the app's Info.plist (plist-first convention).
- Sketch the routes with the same nouns as the App Intents entities: if `card`/`deck` are
  entities, `https://<domain>/card/<id>` and `<appname>://card/<id>` should resolve them.

## App-side setup

1. **Associated Domains entitlement** on the app target:
   `applinks:<domain>` — plus `appclips:<domain>` if an App Clip target exists, and
   `webcredentials:<domain>` if passkeys/password autofill are ever planned (cheap to add
   now; each is its own AASA section).
   The **Associated Domains capability must also be enabled on the bundle ID** (portal/asc)
   or Xcode Cloud archives fail signing — same rule as every other capability (asc-setup §1).
2. **One routing funnel — reuse the intents mailbox.** `onOpenURL` (custom scheme + universal
   links) and `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` (universal links via
   Handoff path) both parse the URL into the same `LaunchAction` the launcher intents use,
   then `LaunchInbox.set(...)`; the root view already `take`s it. One navigation system —
   intents, URLs, widget taps, quick actions — not four.
3. **URL parsing lives in the Data layer**, next to `LaunchAction` — it's pure string→value
   logic, so it gets unit tests (`swift test` covers it) and both the app and the App Clip
   share it.
4. **Piggyback surfaces**: `widgetURL(_:)` in widgets and `userActivity` for Handoff should
   emit the same URLs the routes parse — never invent a second format.

## App Clip specifics

- The clip's invocation URLs must be covered by the domain's AASA `appclips` section
  (`TEAMID.<bundleID>.Clip`) *and* registered as an App Clip experience in ASC (advanced
  experiences for physical codes come later; the default link experience is enough for v1).
- The clip should parse URLs with the same shared Data-layer router as the app.

## AASA file (served by IkigaiServer)

Served at `https://<domain>/.well-known/apple-app-site-association` — no redirects,
`Content-Type: application/json`, no file extension. Shape:

```json
{
  "applinks": {
    "details": [{
      "appIDs": ["TEAMID.com.45bitstudios.App"],
      "components": [
        { "/": "/card/*" },
        { "/": "/deck/*" },
        { "/": "/site/*", "exclude": true }
      ]
    }]
  },
  "appclips": { "apps": ["TEAMID.com.45bitstudios.App.Clip"] },
  "webcredentials": { "apps": ["TEAMID.com.45bitstudios.App"] }
}
```

- `exclude: true` keeps marketing-site paths in the browser — decide the split between
  app-owned and site-owned paths deliberately.
- Apple's CDN fetches the AASA **on install** and caches it (hours-to-a-day); a wrong first
  deploy lingers. Verify before shipping: `curl -s https://<domain>/.well-known/apple-app-site-association`.
- For development, set the entitlement to `applinks:<domain>?mode=developer` and enable
  Developer ▸ Associated Domains Development on the device to bypass the CDN.

## Testing

```sh
xcrun simctl openurl booted "https://<domain>/card/123"    # universal link
xcrun simctl openurl booted "<appname>://card/123"          # custom scheme
swift test --filter <App>DataTests                          # route parsing
```

Long-press a link in Notes/Mail on device to confirm "Open in <App>" appears — the quickest
real-device AASA sanity check.
