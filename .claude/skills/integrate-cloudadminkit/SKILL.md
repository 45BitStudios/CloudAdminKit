---
name: integrate-cloudadminkit
description: Use when adding the CloudAdminKit Swift package (push, analytics, feature flags, remote settings, feature requests) to an app, or when a user asks how to integrate CloudAdmin-managed features.
---

# Integrate CloudAdminKit

The full walkthrough lives in [`AGENTS.md`](../../../AGENTS.md) at the repo root — it's the
canonical, tool-agnostic source of truth (also read by Cursor and Codex), so it's kept as the
one copy instead of being duplicated here.

Read `AGENTS.md` and follow it directly: adding the package dependency, picking granular
products only (never a combined aggregate — see the ITMS-90683 note there), configuring the
CloudKit container identifier, and the starter snippets for push/analytics/feature
flags/remote settings/feature requests.
