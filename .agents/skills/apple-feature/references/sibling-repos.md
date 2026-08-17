# Sibling packages to search before writing new types

Default root: `$STUDIO45` or `~/Dev/Studio45`. Override with `STUDIO45=…`.
Run `scripts/find-reuse.sh <query>` — do not browse from memory.

| Repo | Path | Search it for | Do not |
|---|---|---|---|
| **Ikigai** | `$STUDIO45/Ikigai` | Shared infra + UI. Read `docs/Ikigai-Integration-Guide.md` first. | Rebuild router, keychain, CloudKit, auth, networking, charts, forms, a11y modifiers, `LaunchInbox`. |
| **CloudAdminKit** | `$STUDIO45/CloudAdminKit` | Analytics, feature flags, remote settings, feature requests (`CloudAdminClient` / `CloudAdminClientUI`). | Add a local Analytics/Flags/Settings service. Those left Ikigai. |
| **AI / AIKit** | `$STUDIO45/AI` | LLM / on-device models (`AIEngine`, `AIModelCatalog`, `AIMLX`). | Look in Ikigai for AI — `IkigaiAI` was removed. |
| **IkigaiServer** | `$STUDIO45/IkigaiServer` | Tenant domain, AASA, marketing pages, push/Live Activities, CloudKit S2S, JSON API. | Only if the feature has a server, universal-link, or HTTP surface. |

## Ikigai link rule

Link the **granular** product the target needs (`IkigaiKeychain`, `IkigaiUIComponents`). Never link `IkigaiCore` / `IkigaiUI` aggregates into a shipping app target — they pull permission-touching subsystems and fail TestFlight purpose-string scan (ITMS-90683). Full product list is in that repo's `Package.swift` / README.

## Also in the current app repo

Read, in this order if present: `CLAUDE.md`, `AGENTS.md`, `ARCHITECTURE.md`, `Package.swift`, `docs/app-intents-playbook.md`, `docs/ikigai-adoption.md`, `PRD.md`, `description.md`.
