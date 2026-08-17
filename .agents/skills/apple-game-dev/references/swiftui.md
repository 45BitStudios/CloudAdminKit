# SwiftUI integration & layout

## 3. Sizing, scaling, and safe areas

- Design in a fixed logical scene size (e.g. 1024-wide or 2048-wide) with `scaleMode = .aspectFill`, then position UI relative to the *visible* rect, not the scene rect. Compute the visible inset from `view.safeAreaInsets` converted into scene coordinates.
- **Anti-pattern (seen in Terranous):** global `kViewSize = UIScreen.main.bounds` constants captured at launch, and magic fractions like `height * 0.945`. These break on rotation, iPad multitasking, Dynamic Island devices, and macOS/Catalyst windows. Derive layout from the scene/view at `didMove(to:)` and re-layout in `didChangeSize(_:)`.
- Support `.resizeFill` only if all layout is dynamic.

## 10. SwiftUI integration (make this a first-class part of the skill)

**Hosting.** `SpriteView(scene:)` (iOS 14+/macOS 11+/tvOS 14+/watchOS 7+) is the default host — no UIKit needed. Its full signature matters; a skill should use it deliberately:
- `transition:` — SKTransition applied when the `scene` parameter changes (scene-to-scene navigation without SKView access).
- `isPaused:` — bind to app lifecycle: `@Environment(\.scenePhase)` → pass `scenePhase != .active` so the game auto-pauses on backgrounding.
- `preferredFramesPerSecond:` — 60 default; 120 for ProMotion action games, 30 for board/idle games (battery).
- `options:` — set `[.ignoresSiblingOrder]` for batching (the SwiftUI-era replacement for `skView.ignoresSiblingOrder`); add `.allowsTransparency` + `scene.backgroundColor = .clear` to composite SpriteKit over SwiftUI content (particle layers above SwiftUI backgrounds); `.shouldCullNonVisibleNodes`.
- `debugOptions:` — `[.showsFPS, .showsNodeCount, .showsDrawCount]` behind a debug flag.

**The #1 SwiftUI gotcha: scene identity.** Most tutorials (including HWS's canonical example) build the scene in a computed `var scene` inside the view — that constructs a *new scene on every body evaluation*, silently resetting the game; Apple forum threads confirm SwiftUI view updates losing the SKScene reference when it's built ad hoc. The scene must be owned outside `body`:
- `@State private var scene = GameScene(size: ...)` (value-stable across renders), or
- owned by the game model: `@State private var game = GameModel()` where `GameModel` creates and retains the scene, or
- the scene itself as `@StateObject`/observable object.
Encode this as a hard rule in the skill: **scene construction never happens in `body`.**

**Bidirectional communication.** Replace NotificationCenter entirely:
- *Scene → SwiftUI:* the scene holds a reference to a shared `@Observable` (iOS 17+) or `ObservableObject` game model and writes score/lives/phase on the main actor; SwiftUI HUD text/bars read it reactively. Simplest variant for small games: make `GameScene` itself an `ObservableObject` with `@Published var score` and inject it into views.
- *SwiftUI → Scene:* call methods directly on the retained scene instance (pause, restart, spawn), or write *intents* into the model that the scene consumes in `update(_:)`. For continuous controls (virtual d-pad, thumbstick built in SwiftUI), set flags/vectors in a small `InputState` the scene polls per frame — same input-abstraction pattern as §6, which is why that abstraction matters.

**Division of labor (the OctopusKit `OKContainerView` pattern).** `ZStack { SpriteView(...) ; overlayForCurrentState }` — SpriteKit owns the simulated world; SwiftUI owns *everything screen-space*: menus, HUD, pause sheet, settings, shop, onboarding. Drive the overlay with the game state machine: publish the current state (enum or GKState type) from the model and `switch` on it to choose the overlay view. This kills three legacy problems at once: SKLabelNode layout cost for scores (§5), safe-area math in scene coordinates (§3 — put `.ignoresSafeArea()` on the SpriteView only, and let HUD overlays respect safe areas natively), and hand-rolled button nodes (§6 — SwiftUI buttons get accessibility, Dynamic Type, and animations free). In-world UI (damage numbers, speech bubbles, pickups) stays SpriteKit.

**Input coexistence.** Touches pass through SpriteView to the scene's `touches*` handlers normally. Overlay views intercept touches wherever they have content — mark decorative overlays `.allowsHitTesting(false)`. GCController/keyboard input is framework-independent and unaffected.

**Platform notes.** watchOS has no SKView: `didMove(to:)` never fires — do setup in `sceneDidLoad()` for cross-platform scenes. SpriteView never exposes its underlying SKView, so APIs like `textureFromNode(_:)` or attaching an SKRenderer pipeline (§11 Tier 4) require dropping to a `UIViewRepresentable`-wrapped SKView / MTKView — that's the documented escape hatch, not the default.

**Persistence & services.** Keep SwiftData/UserDefaults/GameKit in the model/service layer the SwiftUI app owns; the scene stays a pure simulation that reads/writes the model. This is what makes the game testable and lets the same scene run on iOS/macOS/tvOS.

