# Architecture, scenes, input & organization

# SpriteKit Game Design & Architecture Best Practices

Synthesized from a review of open-source SpriteKit codebases:

- **terranous_spritekitswift** (jgnmoose) — complete endless runner, classic controller-based architecture, Swift 1.2 era. Useful for overall game shape; several patterns are now dated.
- **Legend-Wings** (woguan) — mid-size action game "pushing SpriteKit to the limit"; flat file-per-actor structure.
- **glide** (cocoatoucher) — production-quality 2D platformer engine on SpriteKit + GameplayKit; the best OSS reference for ECS, collision, input, and camera architecture.
- **OctopusKit** (InvadingOctopus) — ECS engine bridging SpriteKit with SwiftUI; reference for modern hosting and declarative UI overlays.
- **SKTUtils** (Ray Wenderlich team) — canonical extension/helper patterns (CGPoint/CGVector math, SKAction effects, audio).
- Apple's **DemoBots** sample — canonical GKComponent/GKStateMachine usage.
- **Orbit7** (Aaron-A-zz) — minimal shape-based arcade game; shows how small a shippable SpriteKit game can be (7 files: scene, menu, game-over, shapes factory).
- **KiiBlocks** (KiiPlatform) — Obj-C era grid/block game with cloud leaderboard integration; useful as a backend-integration shape, dated otherwise.
- **SpriteKit-tDemo** (msaveleva) — platformer demo; clean 3-layer parallax `ScrollingBackground` (one node per layer, per-layer velocity, endless platform randomizer).
- **SpriteKit-Platformer-Tutorial** (mbaranowski) — tile-map platformer with custom (non-SKPhysics) collision against Tiled maps; the historical JSTileMap approach now maps to `SKTileMapNode`.
- **Astro Flights** / **Ur Coach** / **Queah** (GitHub topic survey) — the current-generation pattern: SwiftUI app shell + SpriteKit game scene, Game Center, CoreHaptics, SwiftData persistence; board games render the board in SpriteKit inside a SwiftUI app.
- **ShaderKit** (twostraws) — library of ~25 production-ready SpriteKit fragment shaders (`.fsh`) with an `SKShader` convenience layer.
- **ios-spritekit-shader-sandbox** (eleev) — GLSL/Metal shader effects in SpriteKit: CRT, water reflection/movement, LCD, raymarched flame, procedural lightning, fractals.

---

## 1. Pick the right architecture tier

Three tiers appear in the wild. Match tier to game scope; don't over-engineer.

**Tier A — Node subclasses + controllers (Terranous pattern).** Each actor is an `SKSpriteNode` subclass (`Player`, `Meteor`, `Star`); spawning/recycling logic lives in controller nodes (`MeteorController`, `StarController`) added to the scene. Scene composes controllers and routes update/contact events. Right for: jam games, endless runners, single-mechanic arcade games.

**Tier B — GameplayKit ECS (DemoBots/glide pattern).** `GKEntity` + `GKComponent`, with node rendering delegated to a render/transform component. Behaviors are small composable components (glide: `JumpComponent`, `DasherComponent`, `HealthComponent`, `SelfFollowWaypointsComponent`, etc.), grouped by category (Ability / Autonomous / Movement / Environment / UI). Right for: games with many actor types sharing behaviors, platformers, anything with AI.

**Tier C — Engine layer.** Only if building multiple games: extract a shared package (scene base class, z-container management, input abstraction, camera entity). glide's `Sources/` layout (Collisions, Components, Entities, Input, Scene, UI, Utils, CrossPlatform) is the template.

Rule of thumb: start Tier A; refactor to components when the third actor type duplicates behavior code.

## 2. Scene structure & lifecycle

- **Layer via container nodes, not raw zPosition on leaves.** Terranous uses `gameNode` / `statusBarNode`; glide formalizes this as ordered `ZPositionContainer` definitions. Declare layers as an enum (`background`, `world`, `effects`, `hud`, `overlay`) and parent nodes into containers. Pausing `gameNode.isPaused = true` then pauses gameplay without freezing the HUD.
- **Do setup in `didMove(to:)`, not `init`.** View-dependent work (scale, physics edges, camera) belongs there.
- **One scene class per screen state is optional.** Terranous uses separate `MenuScene`/`GameScene`/`GameOverScene` with `SKTransition`s; equally valid is one scene with overlay nodes swapped by a state machine. Separate scenes give free memory teardown; overlays give seamless transitions. Choose deliberately.
- **Explicit game state.** Even the simplest games need it — Terranous: `enum GameState { tutorial, running, gameOver }` gating the update loop and touch handling. For anything bigger, use `GKStateMachine` with `GKState` subclasses per state (DemoBots pattern); put per-state enter/exit logic in `didEnter(from:)`/`willExit(to:)`.
- **Delta-time correctly.** Track `lastUpdateTime` in `update(_ currentTime:)`, compute `dt`, clamp it (e.g. `min(dt, 1/30)`) to avoid physics tunneling after app suspension. Never assume 60 fps frame steps.
- **Respect the frame-cycle ordering:** `update` → SKActions evaluated → physics simulation → `didSimulatePhysics` → constraints → `didFinishUpdate`. Camera follow and position clamping go in `didSimulatePhysics` or via `SKConstraint`, not `update`, or you get one-frame lag/jitter.
- **Use `SKCameraNode`** for any scrolling world. Attach HUD as a child of the camera so it stays screen-fixed. glide wraps the camera in an entity with a focus/bounding-box component — a good pattern for smooth follow + level-bounds clamping.

## 6. Input

- Route touches by scene state first, then hit-test. Buttons as dedicated node subclasses with a tap closure/delegate (Terranous's `TapButton`/`StartButton` pattern) rather than name-string checks scattered in `touchesBegan`.
- Abstract input if targeting >1 platform: glide's `Input` module maps touch/keyboard/game-controller into logical actions; even a small `InputState` struct (left/right/jump flags polled in `update`) decouples mechanics from event callbacks and makes controller support (GCController) a drop-in.
- Support the modern niceties: haptics via `CoreHaptics`/`UIImpactFeedbackGenerator` on hits, and GCController with `GCVirtualController` fallback for action games.

## 9. Persistence & services

- One thin `GameKitHelper`-style wrapper for Game Center: authenticate at launch (handling the login VC presentation via the hosting VC), submit scores fire-and-forget, expose leaderboard presentation. Fail silently offline.
- Keep meta-state (high score, currency, unlocks) in a codable model persisted to `UserDefaults`/file — Legend-Wings' `AccountInfo`/`GameInfo` split (session state vs. persistent account) is a clean separation.
- Never gate the game loop on network/GameCenter (Terranous notes simulator logins stall; that's a design smell to isolate).

## 12. Code organization conventions

- File-per-actor + file-per-service, grouped: `Scenes/`, `Nodes/` (or `Entities/`+`Components/`), `Services/` (audio, textures, settings, GameKit), `Support/` (constants, extensions). All three games converge on roughly this.
- One `Constants`/`Tuning` file: bitmasks, z-layers, colors, font names, gameplay tuning values. Prefer nested enums/`OptionSet` over Terranous-era `class var` stringly-typed lookups; use `enum SpriteName: String` + typed accessors so texture names are compiler-checked at one boundary.
- Shared singletons are acceptable for pure services (textures, audio, settings) but keep them stateless w.r.t. gameplay; never let gameplay state live in a singleton.
- Extensions library: adopt/port SKTUtils-style helpers (CGPoint/CGVector arithmetic, clamp, lerp, random ranges, `SKAction` effects). Every serious SpriteKit codebase carries one.

## 13. Anti-patterns observed (encode as "don'ts")

1. `UIScreen.main.bounds` layout constants captured at launch (Terranous) — breaks on modern devices/windows.
2. Stringly-typed node names driving touch handling and lookups.
3. Creating `SKPhysicsBody(texture:)` or new `CGPath`s per spawn.
4. `NotificationCenter` as the primary scene↔host communication channel.
5. Per-node `SKShader` on many nodes (kills batching).
6. Loading emitters/textures lazily inside gameplay (first-use hitches).
7. Mutating the node tree inside `didBegin(contact:)` without parent-nil guards.
8. Testing performance on the simulator.
9. God-object `GameScene` (>300 lines is the smell threshold; Terranous stays under it only by pushing logic into controllers — that's the fix).

---

