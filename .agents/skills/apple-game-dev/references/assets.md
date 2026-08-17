# Asset & content pipeline

## 15. Asset & content pipeline (textures, characters, objects, 3D)

**2D sprites/textures/characters**
- [Kenney.nl](https://kenney.nl) — the default answer: thousands of CC0 sprites, characters, tilesets, UI packs, *plus* matching low-poly 3D kits (Terranous's art is Kenney's).
- [OpenGameArt.org](https://opengameart.org) — CC0/CC-BY sprites, tiles, music, SFX (sourced most surveyed games' assets).
- [itch.io game assets](https://itch.io/game-assets) — huge marketplace, many free/CC0 animated character sheets.
- Tools: **Aseprite** (pixel art + animation frames) → **TexturePacker** or Xcode's native `.spriteatlas` folders for atlas generation (§5); animate via `SKAction.animate(with:)`.

**3D objects/characters (for the RealityKit layer)**
- Format: **USDZ** end-to-end — RealityKit is built around USD. Convert with Apple's **Reality Converter**, or export USD from **Blender**.
- **Reality Composer Pro** (ships with Xcode): scene assembly, ShaderGraph materials, particles, spatial audio — the RealityKit analog of the SpriteKit scene editor.
- CC0 low-poly libraries that drop straight in: **Kenney 3D kits**, **Quaternius** (rigged/animated characters), **Poly Pizza** (searchable low-poly aggregator), **KayKit** (Kay Lousberg's CC0 character/dungeon packs); **Sketchfab** for higher fidelity (check per-model licenses).
- **[Mixamo](https://www.mixamo.com)** (free, Adobe) — auto-rigging + thousands of character animations; retarget/export through Blender to USDZ. The fastest path from "static character model" to "walking, jumping character."
- **[Poly Haven](https://polyhaven.com)** — CC0 HDRIs (crucial for RealityKit image-based lighting via `EnvironmentResource`), plus PBR textures and models.
- **[ambientCG](https://ambientcg.com)** — CC0 PBR material sets (albedo/normal/roughness) that map directly onto RealityKit `PhysicallyBasedMaterial`.
- Apple samples worth mining: the WWDC25 "Bring your SceneKit project to RealityKit" sample game, visionOS samples (BOT-anist, Happy Beam) for RealityKit game structure, DemoBots for 2D ECS.

**Audio/fonts**
- Freesound.org and Sonniss GDC bundles (royalty-free SFX); OpenGameArt music (SketchyLogic's chiptune packs are Terranous's soundtrack); dafont/Google Fonts for display fonts — embed once, use in both `SKLabelNode` and SwiftUI `Font.custom`.

**Pipeline rules for the skill**
- One naming convention shared across atlas names, `SKTexture` lookups, and USDZ entity names; typed accessors, no raw strings at call sites (§12).
- 2D: everything through preloaded atlases (§5). 3D: load `Entity`/`TextureResource` async during load screens.
- Keep source art (Aseprite/Blender files) in-repo beside exports; regenerate exports via scripts, never hand-edit exports.

