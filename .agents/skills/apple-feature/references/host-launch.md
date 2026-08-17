# How to launch a specialist

The pipeline is the contract. Parallelism is an optimization. Detect capabilities; do not branch on the product name.

## 1. Spawn if the host has a child-agent tool

| If you can call | Use it like this |
|---|---|
| Grok `spawn_subagent` | `subagent_type: general-purpose`. Read-only roles: `capability_mode: read-only`. Swift/tester: `read-write`. Devops: `execute` or `all`. `background: true` when launching a parallel pair. |
| Claude `Task` / `Agent` | Named subagent if `apple-<role>` is installed under `~/.claude/agents`; otherwise a general child with the persona prepended. |
| Cursor Task / named subagent | Same: `apple-<role>` under `~/.cursor/agents` after `install.sh`. |
| Codex child agent | Same injection. If none exists, sequential fallback. |

Prefix the child description with the role tag: `[researcher]`, `[first-principles]`, `[designer]`, `[intents]`, `[swift]`, `[tester]`, `[reviewer]`, `[a11y-i18n]`, `[devops]`.

## 2. Inject the persona — do not pass a `persona` parameter

1. Resolve `skill_dir` from the path of this skill's `SKILL.md`.
2. Read `skill_dir/agents/apple-<role>.md`.
3. Prepend that file to the child prompt.
4. Give the child the artifact directory, the file it must write, and the files it may read.
5. Command tool use: "use grep / read_file / the named script; an empty result is valid only after you searched."

## 3. Sequential fallback

If there is no spawn tool, the orchestrator reads the persona and performs that role **in the main context**, still writing the same artifact. One role at a time, in pipeline order. Do not skip a role because you cannot parallelize it.

## 4. Capability

| Role | Writes source? | Runs builds? | Host capability |
|---|---|---|---|
| researcher, first-principles, designer, intents (plan + code pass), reviewer, a11y-i18n | no | no | most restricted (`read-only`) |
| swift, tester | yes | tests only | `read-write` |
| devops | no | yes | `execute` / `all` |

The orchestrator does not implement, does not run `git commit` / `git push`, and does not `--no-verify`.
