---
name: app-website-checklist
description: >
  Audit or build an Apple-app marketing website against the studio needed vs
  nice-to-have list — landing, support, privacy, JSON-LD (SoftwareApplication +
  FAQPage), AppLinkMetadata, robots/sitemap, Universal Links /r/*, ASC icon,
  brand theme, and noindex for deep-link fallbacks. Use when adding a tenant
  site, reviewing SEO/AI-search metadata, wiring AppLinkMetadata or
  AppLinkRoute, adding JSON-LD, or the user runs /app-website-checklist.
---

# App website checklist

Use this when standing up or reviewing the **website** for an Apple app (IkigaiServer
tenant or any studio marketing host). The iPhone binary is out of scope — see
`apple-app-onboarding` and `apple-testflight-archive` for that.

If the repo is IkigaiServer, also read `docs/app-website-checklist.md` for the
file map. Product fields live on the tenant (`*App.swift` → `AppLinkMetadata`),
not copied into every page.

## Needed

Ship these with the tenant. Missing any of the App Store rows blocks review.

1. **Landing `/`** with a real H1 (tagline) and one-sentence description.
2. **`/support` and `/privacy`** — App Store required URLs; real prose, not
   “coming soon”. They must resolve on the **canonical https host**, not only
   via `?app=`.
3. **Unique `<title>` + meta description** on every marketing page.
4. **Canonical + `og:url`** as absolute `https://` URLs.
5. **Numeric App Store id** + store URL (`apple-itunes-app`, download CTA).
6. **JSON-LD `SoftwareApplication`** on `/` (`name`, `description`,
   `applicationCategory`, `operatingSystem`, `downloadUrl`, `offers`,
   `publisher`). Build it from `AppLinkMetadata`, do not hand-write a second
   copy of the pitch.
7. **JSON-LD `FAQPage`** on `/faq` only when the page shows those Q&As.
   Strip HTML from answers. Visible text and JSON-LD must match.
8. **`robots.txt` + `sitemap.xml`** listing `/`, `/about`, `/faq`, `/privacy`,
   `/support` (and `/features` / `/changelog` if they exist).
9. **Do not index app doors:** `/r/*`, `/api/`, item Universal Links. `Disallow`
   in robots **and** `noindex` on the `/r` fallback page.
10. **AASA** claims `/r/*` plus `/apps/{id}/*`. Extra paths go on
    `AppLinkMetadata.additionalLinkRoutes`. Never claim `/*`.
11. **ASC app icon** in the header; **brand colors** from that icon.
12. **Self-hosted CSS.** Do not load the Tailwind Play CDN (CSP blocks it).

IkigaiServer wiring:

```swift
// *App.swift — one home for product + extra Universal Link paths
var tagline: String { "…" }
var productDescription: String { "…" }
var applicationCategory: String { "UtilitiesApplication" }
var ascAppID: String? { "1234567890" }
var additionalLinkRoutes: [AppLinkRoute] {
    [AppLinkRoute(path: "/invite/*", name: "Invite", summary: "Accept an invite.")]
}

// *LandingPage.swift
return AppLandingConfig(/* copy + theme */)
    .applyingProductMetadata(from: MyApp.shared)
```

FAQ JSON-LD is emitted automatically from FAQ sections. Do not add a second
script by hand.

## Nice to have

- `/about`, `/faq` with 4–8 real questions, `/changelog`
- Dedicated 1200×630 `og:image` (icon is the fallback)
- `sameAs` (App Store, X, GitHub)
- Localized `strings.json` via `Accept-Language`
- `llms.txt` — short factual summary at the site root
- Indexable article HTML (only then set `AppLinkRoute.index = true` and add
  the path to the sitemap)
- `WebSite` / Breadcrumb JSON-LD after SoftwareApplication + FAQPage exist

## Do not

- Dual-home the pitch (JSON-LD vs H1). One source: `AppLinkMetadata` / strings.
- Invent FAQ answers that are not on the page.
- Sitemap `/r/chat/abc` or `/ask/xyz` unless that URL is a full article.
- Claim AASA `/*`.
- Load third-party CSS/JS that needs `unsafe-eval`.

## Audit

1. Open `/`, `/faq`, `/support`, `/privacy` on the canonical host (or
   `?app=<id>` locally).
2. View-source: `application/ld+json` on `/` is `SoftwareApplication`; on
   `/faq` is `FAQPage` with the same questions the page shows.
3. `curl /robots.txt` — `Disallow: /api/` and `Disallow: /r/`; sitemap lists
   only marketing paths.
4. Confirm `ascAppID`, icon PNG, and `LandingPageTheme.branded` are set.
5. In IkigaiServer: `swift test --filter SEOTests`.

schema.org categories we use: `UtilitiesApplication`, `ReferenceApplication`,
`LifestyleApplication`, `ShoppingApplication`, `SocialNetworkingApplication`,
`BusinessApplication`, `MultimediaApplication`, `GameApplication`,
`FinanceApplication`, `TravelApplication`, `NewsApplication`.