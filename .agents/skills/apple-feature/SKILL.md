---
name: apple-feature
description: >
  Multi-agent Apple feature pipeline — research, first principles, HIG/Liquid
  Glass design, App Intents, Swift/SwiftUI implementation (Ikigai reuse first),
  tests, a11y/i18n, independent review, then a hard multiplatform compile gate.
  Stops before commit. Use when the user wants to add or ship a feature in an
  Apple app, runs /apple-feature, or says implement this feature, build this
  screen, add this intent, or stop the iOS-only-green / tvOS-red loop.
---

# Apple feature

Orchestrate a feature from the user's request to a green multiplatform matrix.
You coordinate. Specialists write the artifacts. You do not implement, commit, or push.

Resolve `skill_dir` from the path of this file. Personas: `skill_dir/agents/apple-<role>.md`.
Launch rules: `references/host-launch.md`. Artifact sections: `references/artifact-schema.md`.
Sibling packages: `references/sibling-repos.md`.

## Phase 0 — Intake (in-main)

1. Slug from the request (lowercase, hyphens). Artifact dir: `<repo>/.apple-feature/<slug>/`.
2. If `.apple-feature/` is missing from `.gitignore`, append it.
3. Detect shared scheme + shipping platforms from `ci/workflow-ci.json` if present, else `Package.swift` + `*.xcscheme`. Match the repo (Watch standalone only when CI has a `WATCHOS` action).
4. If `progress.md` exists for this slug, resume from its `phase`. Do not redo completed work.
5. Write `request.md`. Update `progress.md`.

## Phase 1 — Explore (parallel)

Launch **researcher** and **first-principles** together. First-principles must not read the view layer first (its persona says so). Wait for both artifacts.

## Phase 2 — Design (after Phase 1)

Launch **designer** and **intents** (plan pass) together. Both read Phase 1 artifacts.

## Phase 3 — Synthesize + gate (in-main)

Write `plan.md` from the four briefs. Present to the user: problem, reuse, tap count, intents, files, acceptance, platforms.

Ask: **Continue** / change X / stop. Skip is refused. No code until Continue.

## Phase 4 — Implement

Launch **swift**. It writes source and `implementation.md`.

## Phase 5 — Review (parallel)

Launch **reviewer**, **a11y-i18n**, **tester**, and **intents** (code pass) together.

## Phase 6 — Fix loop

If reviewer / a11y / intents / tester reported `fix` or failed tests: resume **swift** with the open Critical/Important issues, then re-run only the roles that failed. Cap 3 rounds; then show leftovers and ask.

Nits do not block.

## Phase 7 — Compile gate

Launch **devops**. It runs `scripts/build-all-platforms.sh` (Xcode MCP allowed per its persona).

Red or `BLOCKED-NEEDS-MAC` → back to Phase 6 with the first error lines. Do not commit. Do not push. Do not `--no-verify`. Refuse even if the user asks to "just commit."

## Phase 8 — Report

Show: one-line plan, tap count, reuse decisions, leftover nits, compile matrix. Offer a commit. Run `git commit` only if they ask after a green matrix. Never push.

## Non-negotiables

- Handoffs are the artifact files, not chat. After compaction, re-read `progress.md` + the latest artifacts.
- Load existing skills by name (HIG, Liquid Glass, SwiftUI 27, App Intents). Do not copy them into this skill.
- Granular Ikigai products only. AI lives in AIKit, not Ikigai.
- Mobbin is optional; missing/unauthorized is `Mobbin: unavailable`, not a halt.
- This skill does not onboard apps (`apple-app-onboarding`) and does not archive (`apple-testflight-archive`).
