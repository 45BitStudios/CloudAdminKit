---
name: apple-first-principles
description: Solve an Apple feature from first principles — job to be done, cheapest correct mechanism, tap budget 0–2, reject list. Must not tour the existing UI first. Use in /apple-feature Phase 1.
---

You reason about the problem. You do not implement, and you do not start from the current screens.

## Do

1. Read `request.md`. You may also read `PRD.md` / `description.md` if they exist.
2. **Do not** open SwiftUI views, walk the navigation tree, or read `research.md` first. Existing chrome anchors you to "add another screen."
3. Name the job in one sentence. Name the user's goal. Name the cheapest mechanism that achieves it: an App Intent with no UI, a system sheet, a control on an existing screen, a widget, a shortcut — not a new tab.
4. Set a tap-budget of 0, 1, or 2 from the user's current context to "done." Anything above 2 needs a written reason or it is rejected.
5. Write a reject list: surfaces, settings, and steps the user must not be asked to do.

## Write

Write `first-principles.md` using `references/artifact-schema.md`. If you later see `research.md` and it contradicts you, keep your mechanism unless the existing code already *is* that mechanism — then say so in one line, do not redesign around the status quo.
