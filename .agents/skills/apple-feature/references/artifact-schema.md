# Artifact files

All paths are under `<repo>/.apple-feature/<slug>/`. Create the dir; add `.apple-feature/` to the repo `.gitignore` if missing. Never commit this tree.

Resume from `progress.md`. Do not redo a completed phase.

| File | Author | Required sections |
|---|---|---|
| `request.md` | orchestrator | Verbatim user ask. App / repo. Shared scheme. Shipping platforms (from `ci/workflow-ci.json` else `Package.swift`). Slug. |
| `research.md` | researcher | Existing in-repo code (paths). Sibling hits (`find-reuse.sh` output). Do-not-rebuild list. Mobbin: findings **or** `Mobbin: unavailable`. Notes for designer. |
| `first-principles.md` | first-principles | Problem in one sentence. User goal. Tap-budget (0–2). Simplest mechanism. Reject list. |
| `design.md` | designer | Happy path with **tap count**. Screen it lives on (prefer existing). Empty / error / permission. Liquid Glass primitives used. What not to add. Skills loaded. |
| `intents.md` | intents | Nouns → entities + queries. Verbs → action intents (no UI). Screens → launcher intents via `LaunchInbox`. Shortcuts phrases. App-shell `AppShortcutsProvider` reminder. After code: pass/fail vs the plan. |
| `plan.md` | orchestrator | Problem. Reuse. Tap count. Intents surface. Files to add/change. Acceptance lines. Platforms. Open questions (resolved or asked). |
| `implementation.md` | swift | Files changed. Reuse decisions (what was found, what was new and why). Conflicts between briefs and how they were resolved. Availability guards added. |
| `tests.md` | tester | Suites added/updated. `swift test` result. Acceptance lines covered. |
| `review.md` | reviewer | Verdict `ship` or `fix`. Issues as `### Issue N — Severity: critical\|important\|nit` with File, Description, Suggestion, Status. |
| `a11y-i18n.md` | a11y-i18n | VoiceOver / Dynamic Type / Reduce Motion / catalogs / locale formatting / RTL. Verdict `pass` or `fix` with the same issue format. |
| `devops.md` | devops | One row per tool and per platform: `PASS` / `FAIL` / `SKIP` / `BLOCKED-NEEDS-MAC`. First error line on each `FAIL`. |
| `progress.md` | orchestrator | `phase: 0-8`. `status: in-progress\|gated\|done`. Timestamp. Last artifact written. |

Empty findings are valid **only** after the role has searched (or run the named tool). Write that you searched and found nothing — do not leave the file blank.
