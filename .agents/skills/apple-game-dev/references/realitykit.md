# RealityKit (3D layer)

## 16. RealityKit best practices (the 3D layer)

**Version context.** RealityKit 4 (WWDC24) aligned the framework across iOS, iPadOS, macOS, and visionOS — same APIs, plus low-level mesh/texture access, MaterialX/ShaderGraph, hover effects, spatial audio; tvOS support was added in the latest cycle. `RealityView` is the SwiftUI host everywhere (mirror of the `SpriteView` pattern: `ZStack { RealityView; overlays }`), with `attachments` for embedding live SwiftUI views *inside* the 3D scene.

**ECS is the mandatory mental model** (not optional like GameplayKit was for SpriteKit):
- `Entity` = transform container in a hierarchy; `Component` = plain data (`struct MyComponent: Component`); `System` = per-frame logic over an `EntityQuery(where: .has(MyComponent.self))`.
- **Register custom components and systems at app launch** (`MyComponent.registerComponent()`, `MySystem.registerSystem()`) — forgetting registration is the canonical silent failure.
- Composition over inheritance: behaviors as components + systems, never `Entity` subclasses with logic (the SceneKit habit to unlearn). This also mirrors glide's architecture, so a Tier-B SpriteKit game and the RealityKit layer share one design language.

**Loading & concurrency.** All asset loading is async (`try await Entity(named:in:)`) — load during a loading state, never block the main actor; bundle scenes via the Reality Composer Pro "RealityKitContent" Swift package. Transform mutations happen on the main actor; keep per-frame `System.update` work light and avoid main-thread blocking in gesture handlers.

**Interaction recipe** (memorize; it's three components, not one): an entity is only tappable/draggable when it has `InputTargetComponent` **and** `CollisionComponent` (+ `HoverEffectComponent` for visionOS gaze highlight); then SwiftUI gestures attach via `.gesture(TapGesture().targetedToAnyEntity())`. Missing `CollisionComponent` is the #1 "why doesn't my tap work" bug.

**Physics.** `PhysicsBodyComponent` (static/kinematic/dynamic) + `CollisionComponent` with collision groups/filters — apply the same documented-bitmask-matrix discipline as §4.

**Performance.** Watch entity count and draw calls: share `MeshResource`/`Material` instances across entities (instancing), use LOD for distant models, prefer ShaderGraph/MaterialX materials over custom Metal, and reach for RealityKit 4's low-level mesh/texture APIs or `DrawableQueue` only at the §11-Tier-4 equivalent escalation point.

**OSS references to mine for the skill:**
- [Awesome-RealityKit](https://github.com/divalue/Awesome-RealityKit) — the curated index; start here.
- [MyFirstECS](https://github.com/daniloc/MyFirstECS) — deliberately minimal ECS crash course for visionOS.
- [RealityKit-Sampler](https://github.com/john-rocky/RealityKit-Sampler) — grab-bag of core mechanics incl. a multiplayer mini-game; [RealityKit-CardFlip](https://github.com/maxxfrazer/RealityKit-CardFlip) — small complete game.
- Libraries: **RealityUI** (3D UI controls), **FocusEntity** (placement reticle), **RealityActions** (Cocos2D/SKAction-style action API for entities — the bridge concept for SpriteKit developers), **ShaderGraphCoder** (write shaders in Swift), **GoncharKit** (visionOS helpers).
- Games: **VisionCraft** (Minecraft clone for Vision Pro), **BeatmapVisionPro** (Beat Saber visualizer), Spatial Vacuum.
- Apple: the [RealityKit gaming sample-code collection](https://developer.apple.com/documentation/realitykit/game-development-sample-code), BOT-anist, Happy Beam, and the WWDC25 SceneKit→RealityKit sample.

