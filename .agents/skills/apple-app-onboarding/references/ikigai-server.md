# IkigaiServer — onboarding a new app as a tenant

[IkigaiServer](https://github.com/45BitStudios/IkigaiServer) is the studio's multi-tenant
backend: **one deployment serves every app**, routed by the request's Host header, so each app
gets its own domain from the same binary. Per app it renders the marketing site (landing +
secondary pages), serves the AASA file for Universal Links / App Clips, sends push
notifications and Live Activities, talks to CloudKit server-to-server, and exposes JSON APIs.

Onboarding a new app therefore has a server half: **register the app as a tenant.** The
checklist below is the contract; the *concrete config format* (where tenants are declared,
how the marketing content is authored, how keys are stored) lives in the IkigaiServer repo —
confirm mechanics against its README/docs when executing, and keep this file updated when the
server's tenant interface changes.

## Tenant checklist (server side)

1. **Domain**: pick the app's domain (from the Phase 0 interview), point DNS at the
   IkigaiServer deployment, and provision TLS for it. The Host header is the tenant key —
   everything below hangs off this domain.
2. **Tenant registration**: add the app to the server's tenant config — app name, domain,
   bundle ID, Team ID. This is what turns on Host-routing for the new domain.
3. **AASA**: add the app's `applinks` / `appclips` / `webcredentials` entries (shape and
   path rules in `deep-links.md`). Verify with `curl` before the first TestFlight build that
   uses universal links — Apple's CDN caches a bad first fetch.
4. **Marketing site**: landing + secondary pages. Two of these do double duty as the App
   Store's **required URLs** — the support page and the privacy policy page
   (`app-store-listing.md` §1) — so stand them up before the listing, not after.
5. **Push + Live Activities**: register the APNs auth key (.p8 + key ID + Team ID) for the
   app. Topics: `<bundleID>` for pushes, `<bundleID>.push-type.liveactivity` for Live
   Activity updates. Expose/confirm the device-token registration endpoint for this tenant.
6. **CloudKit server-to-server** (if the app uses it): create the S2S key in CloudKit
   Console for the app's container (`iCloud.<bundleID>`) and register it with the server's
   tenant config.
7. **JSON API**: the app's API base URL is its own domain — version the path (`/api/v1/…`)
   from day one.

## App-side integration conventions

- **Use the Ikigai package's built-in wiring — do not hand-roll push plumbing.** Link the
  granular `IkigaiPushNotifications` product, not the `IkigaiCore` aggregate — linking the
  aggregate pulls in unrelated subsystems (Contacts, Speech, NearbyInteraction, Bluetooth,
  Location) that trip Apple's Info.plist purpose-string scan on TestFlight upload (ITMS-90683)
  even though the app never calls those APIs; see `Ikigai/docs/Ikigai-Integration-Guide.md`'s
  "Products & Imports" section for the full granular-product rationale. `IkigaiPushNotifications`
  pulls in [IkigaiPush](https://github.com/45BitStudios/IkigaiPush) and ships
  `IkigaiPushRegistrar`: call
  `IkigaiPushRegistrar.configure(with: IkigaiPushConfiguration(appId: "<tenant>", apiKey: …))`
  at launch and the shared `AppDelegate` forwards the APNs device token automatically;
  `LiveActivityManager` forwards per-activity update tokens (with optional `correlationId`
  for multi-device fan-out) and push-to-start tokens. Full setup + new-app checklist:
  `Ikigai/docs/Ikigai-Integration-Guide.md`.
- **API client behind a protocol seam in the Data layer** — same pattern as every SDK seam
  (`AssetBackend`, `CosmeticsStore`): define the protocol next to the models, implement it
  with URLSession against the app's domain, inject at launch. Extensions and tests get fakes.
- **One domain everywhere**: universal links, API base, marketing links in-app ("Privacy
  Policy" in Settings should open `https://<domain>/privacy`) — never hardcode a second host.
- **Environment switching**: a Debug-only override for the base URL (staging/local server)
  behind the same seam; never ship a toggle in Release.

## Interaction with the rest of onboarding

| Onboarding step | IkigaiServer dependency |
|---|---|
| Phase 7 (asc capabilities) | Associated Domains capability on the bundle ID |
| Deep links phase | AASA served by the tenant; entitlement lists the tenant domain |
| App Store listing | Support + privacy URLs = tenant marketing pages |
| Push/Live Activities | APNs key registered for the tenant; token endpoints live |
| CloudKit | S2S key per container registered server-side |
