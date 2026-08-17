---
name: apple-game-dev
description: Build 2D and 3D games for Apple platforms with SpriteKit, SwiftUI, and RealityKit, spanning watchOS through visionOS. Use this skill whenever the user wants to create, extend, debug, or optimize a game, game prototype, or game mechanic — or mentions SpriteKit, SKScene, SpriteView, RealityKit, RealityView, GameplayKit, game physics, sprites, texture atlases, particle effects, shaders in games, game juice, or porting a game between Apple platforms. Also use it when adding game-like interactive scenes (physics toys, animated playgrounds) to a regular app, even if the user doesn't say "game".
---

# Apple Game Development (SpriteKit + SwiftUI + RealityKit)

Best practices distilled from reviewing production SpriteKit/RealityKit codebases (glide, OctopusKit, Terranous, Legend-Wings, DemoBots, ShaderKit, Awesome-RealityKit) plus Apple's current guidance. SpriteKit is the only game framework spanning watchOS → visionOS; RealityKit is the 3D layer everywhere except watchOS; SceneKit is deprecated (WWDC25) — never build new work on it.

## Non-negotiable rules (apply to every game task)

1. **SwiftUI-first scaffold.** SwiftUI `App` → game model owning the scene → `ZStack { SpriteView(scene:) ; state-driven overlay views }`. Never the Xcode UIKit Game template, never storyboards.
2. **Scene identity:** the `SKScene` is constructed exactly once, owned by `@State` or the game model — NEVER built in a computed property inside `body` (silently resets the game on view updates).
3. **SpriteKit owns the world; SwiftUI owns screen-space UI** (HUD, menus, pause, settings). In-world UI (damage numbers, speech bubbles) stays SpriteKit.
4. **Simulation stays pure Swift** (framework-free model layer) so it renders via SpriteKit everywhere and optionally RealityKit in 3D. Scene reads/writes an `@Observable` game model; no NotificationCenter.
5. **Physics categories** as shifted-bit `OptionSet` in one file with a documented collision matrix.
6. **All textures through preloaded atlases** (`.spriteatlas`); pool anything spawned repeatedly; typed asset-name accessors, no raw strings at call sites.
7. **Delta-time clamped** in `update`; camera work in `didSimulatePhysics`; layers via ordered container nodes.
8. **SceneKit and SK3DNode are off-limits for new code.** 3D = RealityKit (`RealityView`), and it must be an optional layer since watchOS lacks RealityKit.

## Workflow for a new game

1. **Choose architecture tier** (read `references/architecture.md`): Tier A node-subclass + controllers for single-mechanic arcade games; Tier B GameplayKit/custom ECS when actor types share behaviors; Tier C shared engine package only for multi-game portfolios. Start A; refactor to components when the third actor type duplicates behavior.
2. **Scaffold** per the non-negotiables above (details + SpriteView options: `references/swiftui.md`).
3. **Mechanics**: physics setup (`references/physics.md`), input abstraction with pluggable backends — touch, GCController, spatial tap (`references/architecture.md` §6).
4. **Juice pass** (read `references/game-feel.md`): screen shake, hit-stop, squash-stretch, particles, parallax, easing on everything, centralized audio.
5. **Perf pass** (read `references/performance.md`): atlases, pooling, draw-call checks, device profiling.
6. **Ship targets** (read `references/platforms.md` for the watchOS→visionOS matrix and per-platform constraints).

## When to read each reference

| Read | When the task involves |
|---|---|
| `references/architecture.md` | Project structure, scenes, state machines, ECS, input, persistence, anti-patterns |
| `references/swiftui.md` | SpriteView hosting, scene↔SwiftUI communication, HUD/overlays, sizing & safe areas |
| `references/physics.md` | Collisions, contact handling, physics bodies, platformer movement |
| `references/performance.md` | Frame drops, atlases, pooling, profiling |
| `references/game-feel.md` | Polish, effects, difficulty curves, audio |
| `references/metal-shaders.md` | SKShader effects, Core Image filters, SKRenderer/custom Metal |
| `references/platforms.md` | watchOS, tvOS, macOS, visionOS targets; where 3D is possible |
| `references/realitykit.md` | Any 3D content: RealityView, ECS, entities, materials, interaction |
| `references/assets.md` | Finding/creating sprites, characters, 3D models, textures, audio; USDZ pipeline |

Read the relevant reference BEFORE writing code for that area — these encode trap-avoidance (scene identity, component registration, the 3-component interaction recipe) that tutorials commonly get wrong.
