# Platform matrix & cross-platform strategy

## 14. Platform matrix: watchOS → visionOS, and where 3D fits

Honest framework picture as of 2026:

| | watchOS | iOS/iPadOS | macOS | tvOS | visionOS |
|---|---|---|---|---|---|
| SpriteKit (2D) | ✅ (SpriteView; no SKView — `sceneDidLoad()` only) | ✅ | ✅ | ✅ | ✅ windowed 2D |
| SceneKit (3D) | ✅ but **deprecated** | deprecated | deprecated | deprecated | 2D-view only, deprecated |
| RealityKit (3D) | ❌ | ✅ | ✅ | ✅ | ✅ (the native spatial framework) |

- **SceneKit was formally deprecated at WWDC25** — critical-bug-fix maintenance only, with official migrate-to-RealityKit guidance. Don't build new 3D on SceneKit, and treat SpriteKit's `SK3DNode` (which embeds SceneKit) as a legacy path.
- **RealityKit is the 3D answer everywhere except the watch**: ECS architecture, SwiftUI-first, USD-native — and it is not AR-only; it's Apple's recommended general 3D engine for iOS/macOS/tvOS/visionOS games. Apple DTS has confirmed RealityKit has no watchOS support and itself suggests SpriteKit for multiplatform apps that must include the watch.
- **Consequence for architecture:** SpriteKit is the *only* game framework spanning watchOS through visionOS. So: (1) keep the simulation/model layer pure Swift, framework-free; (2) render the universal 2D experience via SpriteView on every platform; (3) add 3D as an *optional presentation layer* in RealityKit (`RealityView` in SwiftUI, `Model3D` for simple display) on platforms that have it — immersive/volumetric on visionOS, embedded 3D on iOS/macOS/tvOS — while the watch renders the same simulation in 2D. Shared state machine + model, pluggable renderers.
- visionOS input caveat from shipping devs: no bundled physical controller — d-pad-style games need a gesture/gaze input backend or paired GCController; design the input abstraction (§6) with a spatial-tap backend in mind.
- watchOS constraints: tiny scenes, aggressive backgrounding (pause/persist on `scenePhase`), minimal node/particle counts.

