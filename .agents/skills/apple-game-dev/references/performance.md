# Performance

## 5. Performance

- **Texture atlases always.** One `SKTextureAtlas` (or a few, grouped by scene) so SpriteKit batches draw calls. Load atlases up front (`preload(completionHandler:)`) during a loading state; keep a texture provider object (Terranous's `GameTextures`) so nodes never do `SKTexture(imageNamed:)` at spawn time.
- **Object pooling for anything spawned continuously** (bullets, meteors, coins). `removeFromParent()` + reset + reuse beats alloc/dealloc; Legend-Wings' `BulletMaker` is the factory shape — add a free-list to it. Pool `SKEmitterNode`s too; instantiating emitters from `.sks` files per-explosion is a common frame spike.
- Prefer `SKAction` for fire-and-forget animation; prefer per-frame `update` math for anything that needs to react to input or physics every frame. Don't stack `run(_:withKey:)` actions that fight `update`-driven positioning.
- `SKLabelNode` re-layout is expensive — for rapidly updating scores use a preallocated bitmap-font sprite row, or at minimum avoid changing `fontName`/`fontSize` per frame.
- Shaders: `SKShader` per node breaks batching; apply shaders on `SKEffectNode` wrapping a layer (Terranous pixelates the whole `gameNode` layer on death — one effect, not N).
- `shouldRasterize` on static `SKEffectNode` content; `view.ignoresSiblingOrder = true` + explicit zPositions for batching.
- Profile on device, never the simulator (the simulator renders on CPU; both Terranous and Legend-Wings READMEs warn about this). Watch `view.showsFPS/showsNodeCount/showsDrawCount` in debug builds behind a `kDebug` flag.

